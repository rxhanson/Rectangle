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
    private var anchorWindowID: CGWindowID?
    private var transitioning = false
    private var transitionTimeout: DispatchWorkItem?
    private var continuingPresentation = false
    private var keyboardTriggered = false
    private var layout: LayoutHelperLayout?
    private var screen: NSScreen?
    private var retained: [AccessibilityElement: CGRect] = [:]
    private var retainedLaunches: [CGWindowID: TimeInterval] = [:]
    private var existingOccupants: [WindowInfo] = []
    private var occupancyInfos: [WindowInfo]?
    private var selectionCover: WindowInfo?
    private var placementActivationValidation: Timer?
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
        WindowFeatureInteraction.helperIsPresenting = { [weak self] in self?.isPresenting == true }
        WindowFeatureInteraction.cancelHelper = { [weak self] in self?.cancel() }

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
            WindowCapturePermission.guideIfNeeded()
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
        observers.append(NotificationCenter.default.addObserver(forName: WindowCapturePermission.changed,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if WindowCapturePermission.previewsAllowed {
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

    func beginSnap(source: ExecutionSource, windowID: CGWindowID?, screen: NSScreen?, canPresent: Bool = true) -> UUID {
        guard Self.enabled, canPresent else { return cancel() }
        if Self.allows(source), source != .dragToSnap, !selecting,
           panel.hasActiveSession, let windowID, windowID == anchorWindowID,
           let screen, (screen === self.screen || screen.frame == self.screen?.frame), layout != nil {
            token = UUID()
            pending?.cancel(); pending = nil
            transitionTimeout?.cancel()
            refreshTimer?.invalidate(); refreshTimer = nil
            catalog.didUpdate = nil
            cancelImageDelivery()
            transitioning = true
            panel.interactionSuspended = true
            let requestToken = token
            // A cancelled placement may never deliver didSnap. Keep the old picker only
            // if its retained windows still match; never leave stale targets clickable.
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.token == requestToken, self.transitioning else { return }
                guard self.retainedIsValid() else { self.cancel(); return }
                self.transitioning = false
                self.panel.interactionSuspended = false
                self.resumeCatalog(for: requestToken)
                self.showNext()
            }
            transitionTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
            return token
        }
        if source == .dragToSnap, let windowID, windowID == prefetchWindow,
           let screen, screen == prefetchScreen, !panel.isVisible, layout == nil {
            return token
        }
        return cancel()
    }

    @discardableResult func cancel() -> UUID {
        WindowAnimationDiagnostics.event("helper-cancel", fields: ["visible": panel.isVisible, "selecting": selecting])
        token = UUID()
        transitionTimeout?.cancel(); transitionTimeout = nil
        transitioning = false; continuingPresentation = false; anchorWindowID = nil
        panel.interactionSuspended = false
        stopPlacementActivationObservation()
        pendingRestore?.cancel(); pendingRestore = nil
        if let placingWindow { LayoutHelperPlacement.shared.cancel(placingWindow) }
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
        selecting = false; selectionCover = nil
        statusMessage = nil
        retained.removeAll(); retainedLaunches.removeAll(); candidates.removeAll()
        existingOccupants.removeAll(); occupancyInfos = nil
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
            WindowFeatureInteraction.recordPlacement(result.windowElement, result.windowId, frame, result.calcResult.screen, true)
        }
        guard let requestToken = result.layoutHelperToken, requestToken == token else { return }
        guard Self.enabled,
              Self.allows(result.source),
              !result.isFixedSize else { cancel(); return }
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
              LayoutHelperLayout.matches(plan.target(for: plan.cells[plan.anchorIndex]), frame) else { cancel(); return }
        pending?.cancel()
        installInputMonitors()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == requestToken else { return }
            guard Self.enabled else { self.cancel(); return }
            // A minimized window may retain its old bounds. Check visibility
            // in the existing WindowServer read instead of asking AX on main.
            guard let id = result.windowId,
                  let actual = WindowUtil.getWindowList(ids: [id], forceRefresh: true, cacheResult: false)
                    .first(where: { $0.id == id }), actual.isOnScreen,
                  LayoutHelperLayout.matches(actual.frame, frame) else { self.cancel(); return }
            self.continuingPresentation = self.transitioning
            self.transitioning = false
            self.transitionTimeout?.cancel(); self.transitionTimeout = nil
            self.panel.interactionSuspended = false
            self.anchorWindowID = id
            self.completedCells.removeAll()
            self.retainedLaunches.removeAll()
            self.keyboardTriggered = result.source == .keyboardShortcut
            self.layout = plan
            self.screen = result.calcResult.screen
            self.retained = [result.windowElement: frame]
            self.retainedLaunches[id] = result.windowElement.pid.flatMap { WindowProcessIdentity.launchTime(for: $0) }
            self.resumeCatalog(for: requestToken)
            WindowAnimationDiagnostics.event("helper-open", fields: ["candidates": self.catalog.snapshots.count])
            self.showNext()

        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (result.source == .dragToSnap ? 0.05 : 0.08), execute: work)
    }

    private func resumeCatalog(for requestToken: UUID) {
        catalog.didUpdate = { [weak self] in
            guard let self, self.token == requestToken, !self.selecting, !self.transitioning else { return }
            self.showNext()
        }
        catalog.refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.validateSession()
        }
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

    /// AX qualification comes from the existing background catalog. Never query
    /// every application's window roles synchronously on the presentation thread.
    private func visibleOccupants(in plan: LayoutHelperLayout, on screen: NSScreen,
                                  excluding ids: Set<CGWindowID>, requireQualification: Bool = false,
                                  excludingOccupants: Set<CGWindowID> = []) -> [WindowInfo]? {
        // Activation and placement can check several guards in one main-loop turn.
        // Share that immutable scene only until the next turn; never reuse it as
        // a long-lived occupancy or minimized-window cache.
        if occupancyInfos == nil {
            occupancyInfos = WindowUtil.getWindowList(forceRefresh: true, cacheResult: false)
            DispatchQueue.main.async { [weak self] in self?.occupancyInfos = nil }
        }
        let infos = (occupancyInfos ?? []).map { info in
            // Keep the chosen window's initial cover through its own resize/raise.
            // Those writes must not resurrect a tile that was hidden at selection.
            if let cover = selectionCover, cover.id == info.id, cover.pid == info.pid,
               excludingOccupants.contains(info.id), info.isOnScreen { return cover }
            return info
        }
        let snapshots = catalog.snapshots
        var applications: [pid_t: (active: Bool, launch: TimeInterval?)] = [:]
        func application(_ pid: pid_t) -> (active: Bool, launch: TimeInterval?) {
            if let cached = applications[pid] { return cached }
            let app = NSRunningApplication(processIdentifier: pid)
            let active = app.map { !$0.isHidden && !$0.isTerminated && $0.activationPolicy == .regular } ?? false
            let value = (active, active ? WindowProcessIdentity.launchTime(for: pid) : nil)
            applications[pid] = value
            return value
        }
        let relevant = LayoutHelperOccupancy.relevantWindowIDs(in: plan, windows: infos, ignoring: ids, excludingOccupants: excludingOccupants)
        // Only unresolved occupants or windows above them can delay presentation.
        // Selection must fail closed even when a scan has timed out or is suspended.
        if requireQualification || catalog.isRefreshing, infos.contains(where: { info in
            relevant.contains(info.id) && info.pid != getpid() && application(info.pid).active
                && catalog.layoutWindowQualification(for: info.id) == nil
        }) { return nil }
        let normalIDs = Set(infos.compactMap { info -> CGWindowID? in
            guard let snapshot = snapshots[info.id], snapshot.pid == info.pid,
                  snapshot.isLayoutWindow == true else { return nil }
            let app = application(info.pid)
            return app.active && app.launch == snapshot.launch ? info.id : nil
        })
        let occupants = LayoutHelperOccupancy.occupants(in: plan, windows: infos,
            normalWindowIDs: normalIDs, ignoring: ids.union([CGWindowID(panel.windowNumber)]),
            excludingOccupants: excludingOccupants)
        let detection = ScreenDetection()
        return occupants.filter {
            LayoutHelperWindowCatalog.matchesScreen(detection.screenContaining($0.frame, screens: NSScreen.screens), requested: screen)
        }
    }

    private func selectionTargetIsAvailable(_ cell: Int, excluding id: CGWindowID) -> Bool {
        guard let layout, let screen, currentCell == cell,
              let occupants = visibleOccupants(in: layout, on: screen,
                excluding: Set([anchorWindowID].compactMap { $0 }), requireQualification: true,
                excludingOccupants: Set(retained.keys.compactMap(\.windowId)).union([id])) else { return false }
        return !occupants.contains { layout.occupiedCells(by: $0.frame).contains(cell) }
    }

    private func retainedIsValid() -> Bool {
        let ids = retained.keys.compactMap(\.windowId)
        let live = WindowUtil.getWindowList(ids: ids, forceRefresh: true)
        return retained.allSatisfy { window, frame in
            guard let id = window.windowId, let pid = window.pid,
                  let launch = retainedLaunches[id], WindowProcessIdentity.launchTime(for: pid) == launch,
                  let info = live.first(where: { $0.id == id && $0.pid == pid }), info.isOnScreen else { return false }
            return LayoutHelperLayout.matches(info.frame, frame)
        }
    }

    private func showNext(message: String? = nil) {
        guard !transitioning else { return }
        guard Self.enabled else { cancel(); return }
        guard let layout, let screen else { return }
        if let message { statusMessage = message }
        let windows = availableWindows()
        WindowAnimationDiagnostics.event("helper-render", fields: ["candidates": windows.count])
        var occupied = completedCells.union([layout.anchorIndex])
        for frame in retained.values {
            occupied.formUnion(layout.occupiedCells(by: frame))
        }
        guard let occupants = visibleOccupants(in: layout, on: screen,
            excluding: Set([anchorWindowID].compactMap { $0 }),
            excludingOccupants: Set(retained.keys.compactMap(\.windowId))) else { return }
        existingOccupants = occupants
        for window in occupants { occupied.formUnion(layout.occupiedCells(by: window.frame)) }
        guard let next = layout.remaining(excluding: occupied).first else {
            cancel()
            return
        }
        let occupiedIDs = Set(retained.keys.compactMap(\.windowId) + existingOccupants.map(\.id))
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
        if #available(macOS 14, *) { offerPermission = !WindowCapturePermission.previewsAllowed }
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
                   waitForPreviews: WindowCapturePermission.previewsSupported && !offerPermission,
                   continuing: continuingPresentation)
        continuingPresentation = false
        refreshPreviews()
    }

    private func select(_ id: CGWindowID) {
        guard Self.enabled else { cancel(); return }
        guard !selecting, !transitioning, !panel.isTransitioning, let layout, let currentCell, candidates[id] != nil else { return }
        guard selectionTargetIsAvailable(currentCell, excluding: id) else { catalog.refresh(); showNext(); return }
        selecting = true
        statusMessage = nil
        panel.showSelection(inProgress: id)
        let selectionToken = token
        let target = layout.target(for: layout.cells[currentCell])
        catalog.resolve(id) { [weak self] snapshot in
            guard let self, self.token == selectionToken else { return }
            guard let snapshot, WindowProcessIdentity.launchTime(for: snapshot.pid) == snapshot.launch,
                  let window = snapshot.accessibilityElement(),
                  self.retainedIsValid(), self.selectionTargetIsAvailable(currentCell, excluding: id) else {
                self.selecting = false; self.selectionCover = nil
                self.catalog.refresh()
                self.showNext(message: snapshot == nil ? "That window is not responding. Try again." : "That window could not be placed. Try again.")
                return
            }
            // Resolve can take long enough for an external move. Freeze coverage
            // only after its fresh validation, immediately before our own writes.
            self.selectionCover = self.occupancyInfos?.first {
                $0.id == id && $0.pid == snapshot.pid && $0.isOnScreen
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
                    && self.selectionTargetIsAvailable(currentCell, excluding: id)
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
                        element: snapshot.element, observedAt: ProcessInfo.processInfo.systemUptime,
                        isMainWindow: snapshot.isMainWindow)
                    self.place(window, snapshot: restored, target: target, selectionToken: selectionToken,
                               restoredFromMinimized: true, restoreFrame: original)
                case .cancelled: self.cancel()
                case .unresponsive, .failed:
                    self.placingWindow = nil; self.selecting = false; self.selectionCover = nil
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
            usableScreens: ScreenDetection(logicalFrame: { _ in original }).detectScreens(using: window)
                ?? UsableScreens(currentScreen: screen, numScreens: NSScreen.screens.count),
            visibleFrameOfScreen: bounds.screenFlipped, source: .menuItem,
            isFixedSize: snapshot.resizable == false)
        let placement = ImmediateWindowPlacement(screenFrame: bounds,
            sharedEdges: Defaults.moveFixedSizeToEdge.value.alignmentEdges(for: initial, in: bounds),
            constrainToScreen: true, gap: CGFloat(Defaults.gapSize.value))
        // After a failed restore, the live frame may differ from the rollback frame.
        // Do not start an animation at the older position.
        let animated = !restoredFromMinimized && LayoutHelperLayout.matches(historyOriginal, original)
            && WindowAnimator.enabled && !result.isFixedSize
        // resolve() has just validated this window off-main, including its role,
        // resize support and main-window state. Do not ask the app again here.
        let deferActivation = !animated && (NSWorkspace.shared.frontmostApplication?.processIdentifier != snapshot.pid
            || snapshot.isMainWindow != true)
        var expectedFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var activating = false
        let isCurrent: () -> Bool = { [weak self] in
            guard let self, Self.enabled, self.token == selectionToken, self.placingWindow == window,
                  WindowProcessIdentity.launchTime(for: snapshot.pid) == snapshot.launch,
                  NSScreen.screens.contains(screen),
                  LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, bounds) else { return false }
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if deferActivation, frontPID != expectedFrontPID && !(activating && frontPID == snapshot.pid) { return false }
            return self.retainedIsValid() && self.selectionTargetIsAvailable(selectedCell, excluding: snapshot.id)
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
            self.placingWindow = nil; self.selecting = false; self.selectionCover = nil
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
                WindowFeatureInteraction.recordPlacement(window, snapshot.id, frame, screen, !result.isFixedSize)
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
            LayoutHelperPlacement.shared.place(result, from: historyOriginal, placement: placement,
                animated: animated, profile: .standard,
                acknowledgementTimeout: limited ? 1.2 : 3.4, restoreOnFailure: !limited,
                isCurrent: isCurrent, completion: completion)
        }
        func raiseSelected(_ completion: @escaping () -> Void) {
            guard isCurrent() else { finish(.cancelled); return }
            activating = true
            self.placementActivationValidation?.invalidate()
            self.placementActivationValidation = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self, self.token == selectionToken else { timer.invalidate(); return }
                // Activation can abandon its callback after invalidation, before
                // the placement coordinator has installed its cancellation timer.
                if !isCurrent() { timer.invalidate(); self.cancel() }
            }
            window.activateAndRaiseWindow(isCurrent: isCurrent) { activation, main, raise in
                guard self.token == selectionToken else { return }
                self.placementActivationValidation?.invalidate(); self.placementActivationValidation = nil
                guard isCurrent() else { self.cancel(); return }
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
        placementActivationValidation?.invalidate(); placementActivationValidation = nil
        if let placementActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(placementActivationObserver)
        }
        placementActivationObserver = nil
    }

    private func validateSession() {
        guard Self.enabled else { cancel(); return }
        guard !selecting, !transitioning else { return }
        guard let layout, let screen,
              NSScreen.screens.contains(screen),
              LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, layout.screen),
              retainedIsValid() else { cancel(); return }
        if !WindowCapturePermission.previewsAllowed { previews.clear() }
        previews.removeClosedWindows(live: Set(WindowUtil.getWindowList(all: true, forceRefresh: true, cacheResult: false).map(\.id)))
        catalog.refresh()
    }

    private func refreshPreviews() {
        guard Self.enabled else { cancel(); return }
        guard panel.isVisible else { return }
        let ids = panel.previewRequestIDs
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
        guard Self.enabled, WindowCapturePermission.previewsSupported,
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
            guard WindowCapturePermission.previewsAllowed else {
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
