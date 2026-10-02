import Cocoa
import ScreenCaptureKit

/// Owns one assist sequence. Tokens prevent late animation/capture callbacks from
/// reviving a dismissed picker or placing a window into a newer layout.
final class LayoutHelperManager {
    static let shared = LayoutHelperManager()
    static var enabled: Bool {
        Defaults.layoutHelper.userEnabled && !(StageUtil.stageCapable && StageUtil.stageEnabled)
    }
    private(set) var token = UUID()
    private var pending: DispatchWorkItem?
    private let previews = LayoutHelperPreviewStore()
    private let catalog = LayoutHelperWindowCatalog()
    private let screenDetection = ScreenDetection()
    private var prefetchScreen: NSScreen?
    private var prefetchWindow: CGWindowID?
    private var prefetchTask: DispatchWorkItem?
    private var prefetchGeneration = 0
    private var permissionPrefetch: (() -> Void)?
    private var pendingImages: [LayoutHelperPreviewKey: NSImage] = [:]
    private var imageDelivery: DispatchWorkItem?
    private var previewKeys: [CGWindowID: LayoutHelperPreviewKey] = [:]
    private var displayedIDs: [CGWindowID] = []
    private var icons: [pid_t: NSImage] = [:]
    private var appOrder = LayoutHelperWindowOrder()
    private var keyboardTriggered = false
    private var layout: LayoutHelperLayout?
    private var screen: NSScreen?
    private var retained: [AccessibilityElement: CGRect] = [:]
    private var retainedLaunches: [CGWindowID: TimeInterval] = [:]
    private var existingNeighbor: (window: WindowInfo, launch: TimeInterval)?
    private var candidates: [CGWindowID: LayoutHelperWindowSnapshot] = [:]
    private var completedCells: Set<Int> = []
    private var currentCell: Int?
    private var selecting = false
    private var statusMessage: String?
    private var placingWindow: AccessibilityElement?
    private var pendingRestore: WindowPlacementCoordinator.Cancellation?
    private var restorationFrames = LayoutHelperRestorationFrames()
    private var placementActivationObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let panel = LayoutHelperPanel()
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var stageObservation: NSObject?

    func containsPointerEvent(_ event: NSEvent) -> Bool {
        panel.containsPointerEvent(event)
    }

    var isPresenting: Bool { panel.isVisible || selecting }

    private init() {
        observers.append(NotificationCenter.default.addObserver(forName: .windowActionWillExecute,
            object: nil, queue: .main) { [weak self] note in
                if note.object == nil { self?.cancel() }
            })
        stageObservation = StageUtil.observeEnabled { [weak self] in
            if !Self.enabled { self?.cancel() }
        }
        panel.onVisiblePreviewsChanged = { [weak self] in self?.refreshPreviews() }
        panel.onDismiss = { [weak self] in self?.cancel() }
        panel.onSelect = { [weak self] id in self?.select(id) }
        panel.onPermission = { [weak self] in
            self?.cancel()
            LayoutHelperPermission.guideIfNeeded()
        }
        let distributed = DistributedNotificationCenter.default()
        lockObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.cancel(); self?.previews.suspend("lock")
        })
        lockObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.previews.resume("lock")
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
        }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.previews.suspend(name == NSWorkspace.screensDidSleepNotification ? "screen" : "session") })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.previews.resume(name == NSWorkspace.screensDidWakeNotification ? "screen" : "session") })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.previews.removeClosedWindows(live: Set(WindowUtil.getWindowList(all: true, forceRefresh: true, cacheResult: false).map(\.id)))
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in self?.cancel() })
        observers.append(NotificationCenter.default.addObserver(forName: LayoutHelperPermission.changed,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if LayoutHelperPermission.previewsAllowed {
                    let resume = self.permissionPrefetch
                    self.permissionPrefetch = nil
                    resume?()
                } else {
                    self.cancelImageDelivery()
                    self.previews.clear()
                }
                guard self.layout != nil, !self.selecting else { return }
                self.showNext()
            })
    }

    func beginSnap(source: ExecutionSource, windowID: CGWindowID?, screen: NSScreen?) -> UUID {
        guard Self.enabled else { return cancel() }
        if source == .dragToSnap, let windowID, windowID == prefetchWindow,
           let screen, screen == prefetchScreen, !panel.isVisible, layout == nil {
            return token
        }
        return cancel()
    }

    @discardableResult func cancel() -> UUID {
        WindowAnimationDiagnostics.event("helper-cancel", fields: ["visible": panel.isVisible, "selecting": selecting])
        token = UUID()
        stopPlacementActivationObservation()
        pendingRestore?.cancel(); pendingRestore = nil
        if let placingWindow { WindowPlacementCoordinator.shared.cancel(placingWindow) }
        catalog.stop()
        placingWindow = nil
        pending?.cancel(); pending = nil
        cancelPrefetch()
        previews.stop()
        cancelImageDelivery()
        if !Self.enabled { previews.clear() }
        previewKeys.removeAll(); displayedIDs.removeAll()
        icons.removeAll()
        appOrder = LayoutHelperWindowOrder()
        refreshTimer?.invalidate(); refreshTimer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        panel.dismiss()
        layout = nil; screen = nil; currentCell = nil
        selecting = false
        statusMessage = nil
        retained.removeAll(); retainedLaunches.removeAll(); candidates.removeAll()
        existingNeighbor = nil
        completedCells.removeAll()
        return token
    }

    static func allows(_ source: ExecutionSource) -> Bool {
        switch source {
        case .dragToSnap: return true
        case .keyboardShortcut, .menuItem: return Defaults.layoutHelperKeyboard.enabled
        default: return false
        }
    }

    func didSnap(result: ResultParameters, frame: CGRect) {
        WindowAnimationDiagnostics.event("helper-consider", fields: ["enabled": Defaults.layoutHelper.userEnabled,
            "keyboard": Defaults.layoutHelperKeyboard.enabled, "source": String(describing: result.source),
            "tokenMatches": result.layoutHelperToken == token, "fixed": result.isFixedSize])
        if !result.isFixedSize {
            WindowDividerManager.shared.record(result.windowElement, id: result.windowId,
                                                   frame: frame, screen: result.calcResult.screen)
        }
        guard let requestToken = result.layoutHelperToken, requestToken == token,
              Self.enabled,
              Self.allows(result.source),
              !result.isFixedSize,
              result.windowElement.isMinimized != true else { return }
        let screenFrame = result.visibleFrameOfScreen.screenFlipped
        // Reverse precisely the padding used by the originating action. Use the
        // achieved frame, including minimum-size or cooperative split adjustments.
        let initial = result.calcResult.initialRect.screenFlipped
        let action = result.calcResult.resultingAction
        let edges = result.calcResult.resultingSubAction?.gapSharedEdge ?? action.gapSharedEdge
        let planned = GapCalculation.applyGaps(result.calcResult.initialRect, dimension: action.gapsApplicable,
                                               sharedEdges: edges, gapSize: Defaults.gapSize.value,
                                               skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
        let anchor = CGRect(x: frame.minX - (planned.minX - initial.minX),
                            y: frame.minY - (planned.minY - initial.minY),
                            width: frame.width + initial.width - planned.width,
                            height: frame.height + initial.height - planned.height)
        guard let plan = LayoutHelperLayout.make(action: result.calcResult.resultingAction,
                                               screen: screenFrame, anchor: anchor,
                                               gap: CGFloat(Defaults.gapSize.value),
                                               skipTopGap: Defaults.skipGapTopEdge.enabled,
                                               includeDenseGrids: Defaults.layoutHelperDenseGrids.enabled),
              LayoutHelperLayout.matches(plan.target(for: plan.cells[plan.anchorIndex]), frame) else { return }
        pending?.cancel()
        installInputMonitors()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == requestToken else { return }
            guard Self.enabled else { self.cancel(); return }
            guard let id = result.windowId, let actual = WindowUtil.getWindowFrame(id: id),
                  LayoutHelperLayout.matches(actual, frame) else { self.cancel(); return }
            self.existingNeighbor = self.occupiedFrontWindow(in: plan, excluding: id, on: result.calcResult.screen)
            let occupied = self.existingNeighbor.map { plan.occupiedCells(by: $0.window.frame) } ?? []
            guard !plan.remaining(excluding: occupied).isEmpty else {
                WindowAnimationDiagnostics.event("helper-already-filled")
                self.cancel()
                return
            }
            self.keyboardTriggered = result.source == .keyboardShortcut
            self.layout = plan
            self.screen = result.calcResult.screen
            self.retained = [result.windowElement: frame]
            self.retainedLaunches[id] = result.windowElement.pid.flatMap { WindowProcessIdentity.launchTime(for: $0) }
            self.catalog.didUpdate = { [weak self] in
                guard let self, self.token == requestToken, !self.selecting else { return }
                self.showNext()
            }
            self.catalog.refresh()
            WindowAnimationDiagnostics.event("helper-open", fields: ["candidates": self.catalog.snapshots.count])
            self.showNext()
            if self.layout != nil {
                self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                    self?.validateSession()
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (result.source == .dragToSnap ? 0.05 : 0.08), execute: work)
    }

    private func installInputMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return }
            if event.type != .keyDown || event.keyCode == 53 || self.placingWindow != nil { self.cancel() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.cancel()
                return nil
            }
            if event.type == .keyDown, self.placingWindow != nil { self.cancel() }
            if event.type != .keyDown, !self.panel.owns(event.window) { self.cancel() }
            return event
        }
    }

    private func availableWindows(on requestedScreen: NSScreen? = nil) -> [LayoutHelperWindowSnapshot] {
        guard let screen = requestedScreen ?? screen else { return [] }
        return catalog.windows(on: screen)
    }

    private func occupiedFrontWindow(in plan: LayoutHelperLayout, excluding anchorID: CGWindowID,
                                     on screen: NSScreen) -> (window: WindowInfo, launch: TimeInterval)? {
        let detection = ScreenDetection()
        let windows = WindowUtil.getWindowList(forceRefresh: true, cacheResult: false)
        guard let window = windows.first(where: {
            guard $0.id != anchorID, $0.pid != getpid(), $0.level == 0, $0.isOnScreen, $0.alpha > 0,
                  WindowAnimationGeometry.valid($0.frame),
                  detection.screenContaining($0.frame, screens: NSScreen.screens) == screen,
                  let app = NSRunningApplication(processIdentifier: $0.pid) else { return false }
            return !app.isHidden && !app.isTerminated && app.activationPolicy == .regular
        }) else { return nil }
        // Consider only the frontmost eligible neighbor. A window behind it
        // must not be treated as part of the visible layout.
        let occupied = plan.occupiedCells(by: window.frame)
        guard !occupied.isEmpty, !occupied.contains(plan.anchorIndex),
              let launch = WindowProcessIdentity.launchTime(for: window.pid) else { return nil }
        return (window, launch)
    }

    private func retainedIsValid() -> Bool {
        let ids = retained.keys.compactMap(\.windowId) + (existingNeighbor.map { [$0.window.id] } ?? [])
        let live = WindowUtil.getWindowList(ids: ids, forceRefresh: true)
        if let neighbor = existingNeighbor {
            guard WindowProcessIdentity.launchTime(for: neighbor.window.pid) == neighbor.launch,
                  let info = live.first(where: { $0.id == neighbor.window.id && $0.pid == neighbor.window.pid }),
                  info.isOnScreen, LayoutHelperLayout.matches(info.frame, neighbor.window.frame) else { return false }
        }
        return retained.allSatisfy { window, frame in
            guard let id = window.windowId, let pid = window.pid,
                  let launch = retainedLaunches[id], WindowProcessIdentity.launchTime(for: pid) == launch,
                  let info = live.first(where: { $0.id == id && $0.pid == pid }), info.isOnScreen else { return false }
            return LayoutHelperLayout.matches(info.frame, frame)
        }
    }

    private func showNext(message: String? = nil) {
        guard Self.enabled else { cancel(); return }
        guard let layout, let screen else { return }
        if let message { statusMessage = message }
        let windows = availableWindows()
        WindowAnimationDiagnostics.event("helper-render", fields: ["candidates": windows.count])
        var occupied = completedCells.union([layout.anchorIndex])
        for frame in retained.values {
            occupied.formUnion(layout.occupiedCells(by: frame))
        }
        if let neighbor = existingNeighbor { occupied.formUnion(layout.occupiedCells(by: neighbor.window.frame)) }
        guard let next = layout.remaining(excluding: occupied).first else {
            cancel()
            return
        }
        let occupiedIDs = Set(retained.keys.compactMap(\.windowId) + (existingNeighbor.map { [$0.window.id] } ?? []))
        candidates = Dictionary(uniqueKeysWithValues: windows.filter { !occupiedIDs.contains($0.id) }.map { ($0.id, $0) })
        guard !candidates.isEmpty else {
            if !catalog.isRefreshing { cancel() }
            return
        }
        if currentCell != next { cancelImageDelivery() }
        currentCell = next
        let target = layout.target(for: layout.cells[next])
        let candidateWindows = windows.filter { candidates[$0.id] != nil }
        let currentWindowID = candidateWindows.first { !$0.isMinimized && LayoutHelperLayout.matches($0.frame, target) }?.id
        let appOrderedIDs = appOrder.ordered(candidateWindows.map { ($0.id, $0.bundleID.isEmpty ? "pid:\($0.pid)" : $0.bundleID) })
        let orderedIDs = appOrderedIDs.filter { $0 == currentWindowID } + appOrderedIDs.filter { $0 != currentWindowID }
        previewKeys = Dictionary(uniqueKeysWithValues: candidateWindows.map { ($0.id, $0.previewKey.on(screen)) })
        let items = orderedIDs.compactMap { id -> LayoutHelperPanel.Item? in
            guard let snapshot = candidates[id] else { return nil }
            if icons[snapshot.pid] == nil { icons[snapshot.pid] = NSRunningApplication(processIdentifier: snapshot.pid)?.icon }
            return LayoutHelperPanel.Item(id: id, title: snapshot.title,
                icon: icons[snapshot.pid],
                unavailableReason: nil, sourceSize: snapshot.frame.size,
                isCurrentWindow: id == currentWindowID, previewKey: snapshot.previewKey.on(screen), isMinimized: snapshot.isMinimized)
        }
        var offerPermission = false
        if #available(macOS 14, *) { offerPermission = !LayoutHelperPermission.previewsAllowed }
        let remaining = layout.remaining(excluding: occupied).filter { $0 != next }
            .map { layout.target(for: layout.cells[$0]).screenFlipped }
        displayedIDs = items.map(\.id)
        let images: [CGWindowID: NSImage] = offerPermission ? [:] : Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let key = previewKeys[item.id], let image = previews.cached(key) else { return nil }
            return (item.id, image)
        })
        let usesKeyboard = panel.hasActiveSession ? panel.keyboardSelection : keyboardTriggered
        panel.show(in: target.screenFlipped, items: items, offerPermission: offerPermission, message: statusMessage,
                   remainingRegions: remaining, keyboardTriggered: usesKeyboard, images: images,
                   waitForPreviews: LayoutHelperPermission.previewsSupported && !offerPermission)
        refreshPreviews()
    }

    private func select(_ id: CGWindowID) {
        guard Self.enabled else { cancel(); return }
        guard !selecting, let layout, let currentCell, candidates[id] != nil else { return }
        selecting = true
        statusMessage = nil
        panel.showSelection(inProgress: id)
        let selectionToken = token
        let target = layout.target(for: layout.cells[currentCell])
        catalog.resolve(id) { [weak self] snapshot in
            guard let self, self.token == selectionToken else { return }
            guard let snapshot, WindowProcessIdentity.launchTime(for: snapshot.pid) == snapshot.launch,
                  let window = snapshot.accessibilityElement(),
                  self.retainedIsValid() else {
                self.selecting = false
                self.showNext(message: snapshot == nil ? "That window is not responding. Try again." : "That window could not be placed. Try again.")
                return
            }
            self.restorationFrames.prune(live: Set(WindowUtil.getWindowList(all: true, forceRefresh: true, cacheResult: false).map(\.id)))
            let original = self.restorationFrames.original(id: snapshot.id, pid: snapshot.pid,
                launch: snapshot.launch, frame: snapshot.frame, remember: snapshot.isMinimized)
            guard snapshot.isMinimized else {
                self.place(window, snapshot: snapshot, target: target, selectionToken: selectionToken, restoreFrame: original)
                return
            }
            // Retain restore history before any preparation write, even if the
            // helper is dismissed while the window is still being restored.
            if AppDelegate.windowHistory.restoreRects[snapshot.id] == nil
                || AppDelegate.windowHistory.lastRectangleActions[snapshot.id]?.rect != original {
                AppDelegate.windowHistory.restoreRects[snapshot.id] = original
            }
            self.catalog.suspendForPlacement()
            self.panel.beginPlacement()
            self.previews.stop()
            self.placingWindow = window
            let isCurrent = { [weak self] in
                guard let self else { return false }
                return Self.enabled && self.token == selectionToken && self.retainedIsValid()
            }
            self.pendingRestore = LayoutHelperWindowRestoration.restore(window, target: target, original: original, isCurrent: isCurrent) { [weak self] outcome in
                guard let self, self.token == selectionToken else { return }
                self.pendingRestore = nil
                switch outcome {
                case .placed(let frame):
                    // Preparation may have changed the frame before restoration completed.
                    let restored = LayoutHelperWindowSnapshot(id: snapshot.id, pid: snapshot.pid, launch: snapshot.launch,
                        bundleID: snapshot.bundleID, title: snapshot.title, frame: frame,
                        reportedMinimum: snapshot.reportedMinimum, resizable: snapshot.resizable,
                        element: snapshot.element, observedAt: ProcessInfo.processInfo.systemUptime)
                    self.place(window, snapshot: restored, target: target, selectionToken: selectionToken,
                               restoredFromMinimized: true, restoreFrame: original)
                case .cancelled: self.cancel()
                case .unresponsive, .failed:
                    self.placingWindow = nil; self.selecting = false
                    self.catalog.resumeAfterPlacement()
                    self.showNext(message: "That window could not be restored. Try again.")
                }
            }
        }
    }

    private func place(_ window: AccessibilityElement, snapshot: LayoutHelperWindowSnapshot,
                       target: CGRect, selectionToken: UUID, restoredFromMinimized: Bool = false,
                       restoreFrame: CGRect? = nil) {
        guard let layout, let screen, let selectedCell = currentCell else { selecting = false; return }
        let original = snapshot.frame
        let historyOriginal = restoreFrame ?? original
        placingWindow = window
        panel.beginPlacement()
        previews.stop()
        cancelImageDelivery()
        catalog.suspendForPlacement()
        WindowAnimationDiagnostics.event("helper-placement-start", fields: ["windowID": snapshot.id])
        let bounds = layout.screen
        let initial = layout.cells[selectedCell]
        var calculation = WindowCalculationResult(rect: target.screenFlipped, screen: screen, resultingAction: .specified)
        calculation.initialRect = initial.screenFlipped
        let result = ResultParameters(windowId: snapshot.id, action: .specified, windowElement: window,
            calcResult: calculation,
            usableScreens: screenDetection.detectScreens(using: window)
                ?? UsableScreens(currentScreen: screen, numScreens: NSScreen.screens.count),
            visibleFrameOfScreen: bounds.screenFlipped, source: .menuItem,
            isFixedSize: !window.isResizable() || window.isSystemDialog == true)
        let placement = WindowAnimationPlacement(screenFrame: bounds,
            sharedEdges: Defaults.moveFixedSizeToEdge.value.alignmentEdges(for: initial, in: bounds),
            constrainToScreen: true, gap: CGFloat(Defaults.gapSize.value))
        // After a failed restore, the live frame may differ from the rollback frame.
        // Do not start an animation at the older position.
        let animated = !restoredFromMinimized && LayoutHelperLayout.matches(historyOriginal, original)
            && WindowAnimator.enabled && !result.isFixedSize
        let focused = AccessibilityElement.getFocusedWindowElement()
        let deferActivation = !animated && (focused?.pid != snapshot.pid || focused?.windowId != snapshot.id)
        var expectedFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var activating = false
        let isCurrent: () -> Bool = { [weak self] in
            guard let self, Self.enabled, self.token == selectionToken, self.placingWindow == window,
                  WindowProcessIdentity.launchTime(for: snapshot.pid) == snapshot.launch,
                  NSScreen.screens.contains(screen),
                  LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, bounds) else { return false }
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if deferActivation, frontPID != expectedFrontPID && !(activating && frontPID == snapshot.pid) { return false }
            return self.retainedIsValid()
        }
        if deferActivation {
            placementActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                    guard let self, self.token == selectionToken,
                          let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    if activating && app.processIdentifier == snapshot.pid { expectedFrontPID = snapshot.pid }
                    else if app.processIdentifier != expectedFrontPID { self.cancel() }
                }
        }
        let finish: (WindowPlacementCoordinator.Outcome) -> Void = { [weak self] outcome in
            guard let self, self.token == selectionToken else { return }
            guard isCurrent() else { self.cancel(); return }
            WindowAnimationDiagnostics.event("helper-placement-complete", fields: ["windowID": snapshot.id,
                "outcome": String(describing: outcome)])
            self.stopPlacementActivationObservation()
            self.placingWindow = nil; self.selecting = false
            switch outcome {
            case .placed(let frame):
                self.restorationFrames.remove(id: snapshot.id, pid: snapshot.pid, launch: snapshot.launch)
                if AppDelegate.windowHistory.restoreRects[snapshot.id] == nil
                    || AppDelegate.windowHistory.lastRectangleActions[snapshot.id]?.rect != historyOriginal {
                    AppDelegate.windowHistory.restoreRects[snapshot.id] = historyOriginal
                }
                AppDelegate.windowHistory.lastRectangleActions[snapshot.id] = RectangleAction(action: .specified, subAction: nil, rect: frame, count: 1)
                self.completedCells.insert(selectedCell)
                self.retained[window] = frame
                self.retainedLaunches[snapshot.id] = snapshot.launch
                WindowDividerManager.shared.record(window, id: snapshot.id, frame: frame,
                    screen: screen, eligibilityConfirmed: !result.isFixedSize)
                if WindowSizeConstraint.isExceeded(requested: target, actual: frame, action: .specified) {
                    WindowSizeWarning.shared.show(on: screen)
                }
                self.catalog.resumeAfterPlacement()
                self.showNext()
            case .unresponsive:
                self.catalog.resumeAfterPlacement()
                self.showNext(message: "That window is not responding. Try again.")
            case .failed:
                self.catalog.resumeAfterPlacement()
                self.showNext(message: "That window could not be placed. Try again.")
            case .cancelled: self.cancel()
            }
        }
        func performPlacement(limited: Bool, completion: @escaping (WindowPlacementCoordinator.Outcome) -> Void) {
            guard isCurrent() else { finish(.cancelled); return }
            WindowPlacementCoordinator.shared.place(result, from: historyOriginal, placement: placement,
                animated: animated, profile: .standard,
                acknowledgementTimeout: limited ? 1.2 : 3.4, restoreOnFailure: !limited,
                isCurrent: isCurrent, completion: completion)
        }
        func raiseSelected(_ completion: @escaping () -> Void) {
            guard isCurrent() else { finish(.cancelled); return }
            activating = true
            window.activateAndRaiseWindow(isCurrent: isCurrent) { activation, main, raise in
                guard isCurrent() else { finish(.cancelled); return }
                expectedFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                activating = false
                WindowAnimationDiagnostics.event("helper-window-raise", fields: ["windowID": snapshot.id,
                    "activation": activation.rawValue, "main": main.rawValue, "raise": raise.rawValue])
                guard expectedFrontPID == snapshot.pid else { finish(.unresponsive); return }
                completion()
            }
        }
        guard deferActivation else {
            raiseSelected { performPlacement(limited: false, completion: finish) }
            return
        }
        WindowAnimationDiagnostics.event("helper-background-placement", fields: ["windowID": snapshot.id])
        performPlacement(limited: true) { outcome in
            guard isCurrent() else { finish(.cancelled); return }
            switch outcome {
            case .placed(let frame):
                WindowAnimationDiagnostics.event("helper-background-placed", fields: ["windowID": snapshot.id])
                raiseSelected {
                    // Activation can cause an application to relayout its window.
                    // Read the visible geometry before committing the layout.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                        guard isCurrent() else { finish(.cancelled); return }
                        if let actual = WindowUtil.getWindowFrame(id: snapshot.id),
                           LayoutHelperLayout.matches(actual, frame) { finish(.placed(actual)) }
                        else { performPlacement(limited: true, completion: finish) }
                    }
                }
            case .unresponsive, .failed:
                WindowAnimationDiagnostics.event("helper-background-fallback", fields: ["windowID": snapshot.id])
                raiseSelected { performPlacement(limited: false, completion: finish) }
            case .cancelled: finish(.cancelled)
            }
        }
    }

    private func stopPlacementActivationObservation() {
        if let placementActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(placementActivationObserver)
        }
        placementActivationObserver = nil
    }

    private func validateSession() {
        guard Self.enabled else { cancel(); return }
        guard !selecting else { return }
        guard let layout, let screen,
              NSScreen.screens.contains(screen),
              LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, layout.screen),
              retainedIsValid() else { cancel(); return }
        if !LayoutHelperPermission.previewsAllowed { previews.clear() }
        previews.removeClosedWindows(live: Set(WindowUtil.getWindowList(all: true, forceRefresh: true, cacheResult: false).map(\.id)))
        catalog.refresh()
    }

    private func refreshPreviews() {
        guard Self.enabled else { cancel(); return }
        guard panel.isVisible else { return }
        let visible = panel.visiblePreviewIDs
        let ids = visible + displayedIDs.filter { !visible.contains($0) }
        let captureToken = token
        let cell = currentCell
        previews.request(ids.compactMap { previewKeys[$0] }, onFailure: { [weak self] key in
            guard let self, self.token == captureToken, self.currentCell == cell,
                  self.panel.isVisible, self.previewKeys[key.id] == key else { return }
            self.panel.previewFailed(for: key.id)
        }) { [weak self] key, image in
            guard let self, self.token == captureToken, self.currentCell == cell,
                  self.previewKeys[key.id] == key else { return }
            self.pendingImages[key] = image
            guard self.imageDelivery == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.imageDelivery = nil
                let images = self.pendingImages
                self.pendingImages.removeAll()
                guard self.token == captureToken, self.currentCell == cell, self.panel.isVisible else { return }
                self.panel.updateImages(Dictionary(uniqueKeysWithValues: images.compactMap { key, image in
                    self.previewKeys[key.id] == key ? (key.id, image) : nil
                }))
            }
            self.imageDelivery = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
        }
    }

    private func cancelImageDelivery() {
        imageDelivery?.cancel(); imageDelivery = nil
        pendingImages.removeAll()
    }

    /// Start preparation with an accepted action, while the real window moves.
    func prefetchForSnap(result: ResultParameters) {
        guard Self.allows(result.source),
              result.layoutHelperToken == token, !result.isFixedSize else { return }
        prefetch(on: result.calcResult.screen, action: result.calcResult.resultingAction,
                 anchor: result.calcResult.initialRect, excluding: result.windowId, delay: 0)
    }

    func cancelPrefetch() {
        prefetchGeneration += 1
        permissionPrefetch = nil
        prefetchScreen = nil; prefetchWindow = nil
        prefetchTask?.cancel(); prefetchTask = nil
        if !panel.isVisible { previews.stop(); if layout == nil { catalog.stop() } }
    }

    /// One immediate batch per screen and anchor. Changing zones reuses the same work.
    func prefetch(on screen: NSScreen, action: WindowAction, anchor: CGRect, excluding id: CGWindowID?,
                  delay: TimeInterval = 0) {
        guard Self.enabled, LayoutHelperPermission.previewsSupported,
              LayoutHelperLayout.make(action: action, screen: screen.adjustedVisibleFrame().screenFlipped,
                                    anchor: anchor.screenFlipped, includeDenseGrids: Defaults.layoutHelperDenseGrids.enabled) != nil else { cancelPrefetch(); return }
        if prefetchScreen == screen, prefetchWindow == id { return }
        cancelPrefetch()
        prefetchScreen = screen; prefetchWindow = id
        let requestToken = token
        let prefetchGeneration = prefetchGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == requestToken, self.prefetchGeneration == prefetchGeneration, !self.panel.isVisible, self.layout == nil else { return }
            guard Self.enabled else { self.cancelPrefetch(); return }
            guard LayoutHelperPermission.previewsAllowed else {
                // A cold permission cache is unknown until its asynchronous check returns.
                self.permissionPrefetch = { [weak self] in
                    guard let self, self.token == requestToken, self.prefetchGeneration == prefetchGeneration else { return }
                    self.prefetchScreen = nil; self.prefetchWindow = nil
                    self.prefetch(on: screen, action: action, anchor: anchor, excluding: id, delay: 0)
                }
                return
            }
            WindowAnimationDiagnostics.event("helper-preview-prefetch", fields: ["delayMilliseconds": delay * 1000])
            self.catalog.didUpdate = { [weak self] in
                guard let self, self.token == requestToken, self.prefetchGeneration == prefetchGeneration,
                      !self.panel.isVisible, self.layout == nil else { return }
                guard Self.enabled else { self.cancelPrefetch(); return }
                let windows = self.availableWindows(on: screen).filter { $0.id != id }
                self.previews.request(windows.map { $0.previewKey.on(screen) })
            }
            self.catalog.refresh()
            let windows = self.availableWindows(on: screen).filter { $0.id != id }
            self.previews.request(windows.map { $0.previewKey.on(screen) })
        }
        prefetchTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}


/// Try the target geometry before restoring, then acknowledge the restored
/// state and fresh geometry before the ordinary snap's final verification.
enum LayoutHelperWindowRestoration {
    static func restore(_ window: AccessibilityElement, target: CGRect? = nil, original: CGRect? = nil, isCurrent: @escaping () -> Bool,
                        completion: @escaping (WindowPlacementCoordinator.Outcome) -> Void) -> WindowPlacementCoordinator.Cancellation {
        let cancellation = WindowPlacementCoordinator.Cancellation()
        let timer = Timer(timeInterval: 0.025, repeats: true) { _ in
            if !isCurrent() { cancellation.cancel() }
        }
        cancellation.timer = timer
        cancellation.onCancel = { completion(.cancelled) }
        RunLoop.main.add(timer, forMode: .common)
        guard let pid = window.pid, let id = window.windowId,
              let launch = WindowProcessIdentity.launchTime(for: pid) else {
            timer.invalidate(); cancellation.onCancel = nil
            completion(.failed(restored: false)); return cancellation
        }
        let preferred = window.animationObservationElement
        WindowAnimator.shared.performPlacementWork {
            let valid = { !cancellation.isCancelled && WindowProcessIdentity.launchTime(for: pid) == launch }
            let outcome: WindowPlacementCoordinator.Outcome
            if let element = WindowAccessibilityLookup.resolve(pid: pid, id: id, launch: launch,
                preferred: preferred, isCurrent: valid) {
                let worker = AccessibilityElement(element, messagingTimeout: 0.05, windowID: id)
                if let target, worker.isResizable(), worker.isSystemDialog != true {
                    _ = prepare(target: target, isCurrent: valid, minimized: { worker.isMinimized },
                        size: { requested in cancellation.write { worker.writeAnimationSize(requested) } ?? .failure },
                        position: { requested in cancellation.write { worker.writeAnimationPosition(requested) } ?? .failure },
                        frame: { worker.frame })
                }
                let acknowledged = acknowledge(isCurrent: valid, minimized: { worker.isMinimized }, restore: {
                    cancellation.write { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) } ?? .failure
                }, frame: {
                    let frame = worker.frame
                    guard WindowAnimationGeometry.valid(frame), let server = WindowUtil.getWindowFrame(id: id),
                          WindowAnimationGeometry.near(frame, server, tolerance: 1) else { return nil }
                    return frame
                })
                switch acknowledged {
                case .failed, .unresponsive:
                    if let original {
                        _ = rollback(original: original, isCurrent: valid,
                            size: { requested in cancellation.write { worker.writeAnimationSize(requested) } ?? .failure },
                            position: { requested in cancellation.write { worker.writeAnimationPosition(requested) } ?? .failure })
                    }
                case .placed, .cancelled: break
                }
                outcome = acknowledged
            } else { outcome = valid() ? .unresponsive : .cancelled }
            DispatchQueue.main.async {
                timer.invalidate(); cancellation.timer = nil; cancellation.onCancel = nil
                guard !cancellation.isCancelled else { return }
                completion(isCurrent() ? outcome : .cancelled)
            }
        }
        return cancellation
    }

    /// Place the window while it is still in the Dock, so the native restore
    /// animation can end at the target. Refusal or a slow reply falls back to
    /// restoring first; the ordinary placement still verifies the final frame.
    static func prepare(target: CGRect, isCurrent: () -> Bool, minimized: () -> Bool?,
                        size: (CGSize) -> AXError, position: (CGPoint) -> AXError,
                        frame: () -> CGRect?, now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                        pause: () -> Void = { Thread.sleep(forTimeInterval: 0.025) }) -> Bool {
        guard WindowAnimationGeometry.valid(target), isCurrent(), minimized() == true else { return false }
        guard size(target.size) == .success, isCurrent(), minimized() == true else { return false }
        guard position(target.origin) == .success, isCurrent(), minimized() == true else { return false }
        guard size(target.size) == .success else { return false }
        let deadline = now() + 0.3
        while isCurrent(), minimized() == true {
            if let actual = frame(), WindowAnimationGeometry.near(actual, target, tolerance: 1) { return true }
            if now() >= deadline { return false }
            pause()
        }
        return false
    }

    /// Only the current operation may undo preparation. Cancellation retains
    /// the remembered original without issuing writes against a newer action.
    static func rollback(original: CGRect, isCurrent: () -> Bool,
                         size: (CGSize) -> AXError, position: (CGPoint) -> AXError) -> Bool {
        guard WindowAnimationGeometry.valid(original), isCurrent() else { return false }
        guard size(original.size) == .success, isCurrent() else { return false }
        guard position(original.origin) == .success, isCurrent() else { return false }
        return size(original.size) == .success
    }

    static func acknowledge(isCurrent: () -> Bool, minimized: () -> Bool?, restore: () -> AXError,
                            frame: () -> CGRect?, now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                            pause: () -> Void = { Thread.sleep(forTimeInterval: 0.025) }) -> WindowPlacementCoordinator.Outcome {
        guard isCurrent() else { return .cancelled }
        guard let initial = minimized() else { return .unresponsive }
        if initial {
            guard isCurrent() else { return .cancelled }
            let error = restore()
            guard error == .success else { return error == .cannotComplete ? .unresponsive : .failed(restored: false) }
        }
        let deadline = now() + 1.5
        while isCurrent() {
            if minimized() == false, let actual = frame() { return .placed(actual) }
            if now() >= deadline { return .unresponsive }
            pause()
        }
        return .cancelled
    }
}

/// Original geometry survives a failed or cancelled restoration until placement
/// succeeds. Process identity keeps retries from inheriting another app's frame.
struct LayoutHelperRestorationFrames {
    private struct Identity: Hashable {
        let id: CGWindowID
        let pid: pid_t
        let launch: TimeInterval
    }
    private var frames: [Identity: CGRect] = [:]
    mutating func original(id: CGWindowID, pid: pid_t, launch: TimeInterval, frame: CGRect, remember: Bool) -> CGRect {
        let key = Identity(id: id, pid: pid, launch: launch)
        if let original = frames[key] { return original }
        if remember { frames[key] = frame }
        return frame
    }
    mutating func remove(id: CGWindowID, pid: pid_t, launch: TimeInterval) {
        frames.removeValue(forKey: Identity(id: id, pid: pid, launch: launch))
    }
    mutating func prune(live: Set<CGWindowID>) {
        frames = frames.filter { live.contains($0.key.id) && WindowProcessIdentity.launchTime(for: $0.key.pid) == $0.key.launch }
    }
}
