import Cocoa
import ScreenCaptureKit

/// Owns one assist sequence. Tokens prevent late animation/capture callbacks from
/// reviving a dismissed picker or placing a window into a newer layout.
final class LayoutHelperManager {
    static let shared = LayoutHelperManager()
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
    private var keyboardTriggered = false
    private var layout: LayoutHelperLayout?
    private var screen: NSScreen?
    private var retained: [AccessibilityElement: CGRect] = [:]
    private var retainedLaunches: [CGWindowID: TimeInterval] = [:]
    private var candidates: [CGWindowID: LayoutHelperWindowSnapshot] = [:]
    private var completedCells: Set<Int> = []
    private var currentCell: Int?
    private var selecting = false
    private var statusMessage: String?
    private var placingWindow: AccessibilityElement?
    private var refreshTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let panel = LayoutHelperPanel()
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []

    func containsPointerEvent(_ event: NSEvent) -> Bool {
        panel.containsPointerEvent(event)
    }

    var isPresenting: Bool { panel.isVisible || selecting }

    private init() {
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
            self?.previews.removeClosedWindows(live: Set(WindowUtil.getWindowList().map(\.id)))
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
                } else { self.previews.clear() }
                guard self.layout != nil, !self.selecting else { return }
                self.showNext()
            })
    }

    func beginSnap(source: ExecutionSource, windowID: CGWindowID?, screen: NSScreen?) -> UUID {
        if source == .dragToSnap, let windowID, windowID == prefetchWindow,
           let screen, screen == prefetchScreen, !panel.isVisible, layout == nil {
            return token
        }
        return cancel()
    }

    @discardableResult func cancel() -> UUID {
        WindowAnimationDiagnostics.event("helper-cancel", fields: ["visible": panel.isVisible, "selecting": selecting])
        token = UUID()
        if let placingWindow { WindowPlacementCoordinator.shared.cancel(placingWindow) }
        catalog.stop()
        placingWindow = nil
        pending?.cancel(); pending = nil
        cancelPrefetch()
        previews.stop()
        cancelImageDelivery()
        if !Defaults.layoutHelper.userEnabled { previews.clear() }
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
        completedCells.removeAll()
        return token
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
              Defaults.layoutHelper.userEnabled,
              result.source == .dragToSnap || (Defaults.layoutHelperKeyboard.enabled &&
                  (result.source == .keyboardShortcut || result.source == .menuItem)),
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
            guard let id = result.windowId, let actual = WindowUtil.getWindowFrame(id: id),
                  LayoutHelperLayout.matches(actual, frame) else { self.cancel(); return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (result.source == .dragToSnap ? 0.1 : 0.3), execute: work)
    }

    private func installInputMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return }
            if event.type != .keyDown || event.keyCode == 53 { self.cancel() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.cancel()
                return nil
            }
            if event.type != .keyDown, !self.panel.owns(event.window) { self.cancel() }
            return event
        }
    }

    private func availableWindows(on requestedScreen: NSScreen? = nil) -> [LayoutHelperWindowSnapshot] {
        guard let screen = requestedScreen ?? screen else { return [] }
        return catalog.windows(on: screen)
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
        guard let layout, let screen else { return }
        if let message { statusMessage = message }
        let windows = availableWindows()
        WindowAnimationDiagnostics.event("helper-render", fields: ["candidates": windows.count])
        var occupied = completedCells.union([layout.anchorIndex])
        for frame in retained.values {
            occupied.formUnion(layout.occupiedCells(by: frame))
        }
        let retainedIDs = Set(retained.keys.compactMap(\.windowId))
        for snapshot in windows where !retainedIDs.contains(snapshot.id) {
            let cells = layout.prefilledCells(by: snapshot.frame)
            if !cells.isEmpty && occupied.isDisjoint(with: cells), let window = snapshot.accessibilityElement() {
                occupied.formUnion(cells)
                retained[window] = snapshot.frame
                retainedLaunches[snapshot.id] = snapshot.launch
                if snapshot.resizable == true {
                    WindowDividerManager.shared.record(window, id: snapshot.id, frame: snapshot.frame,
                        screen: screen, eligibilityConfirmed: true)
                }
            }
        }
        guard let next = layout.remaining(excluding: occupied).first else {
            cancel()
            return
        }
        let occupiedIDs = Set(retained.keys.compactMap(\.windowId))
        candidates = Dictionary(uniqueKeysWithValues: windows.filter { !occupiedIDs.contains($0.id) }.map { ($0.id, $0) })
        guard !candidates.isEmpty else {
            if !catalog.isRefreshing { cancel() }
            return
        }
        if currentCell != next { cancelImageDelivery() }
        currentCell = next
        let target = layout.target(for: layout.cells[next])
        let candidateWindows = windows.filter { candidates[$0.id] != nil }
        let currentWindowID = candidateWindows.first { LayoutHelperLayout.matches($0.frame, target) }?.id
        let appOrderedIDs = appOrder.ordered(candidateWindows.map { ($0.id, $0.bundleID.isEmpty ? "pid:\($0.pid)" : $0.bundleID) })
        let orderedIDs = appOrderedIDs.filter { $0 == currentWindowID } + appOrderedIDs.filter { $0 != currentWindowID }
        previewKeys = Dictionary(uniqueKeysWithValues: candidateWindows.map { ($0.id, $0.previewKey.on(screen)) })
        let items = orderedIDs.compactMap { id -> LayoutHelperPanel.Item? in
            guard let snapshot = candidates[id] else { return nil }
            if icons[snapshot.pid] == nil { icons[snapshot.pid] = NSRunningApplication(processIdentifier: snapshot.pid)?.icon }
            return LayoutHelperPanel.Item(id: id, title: snapshot.title,
                icon: icons[snapshot.pid],
                unavailableReason: unavailableReason(snapshot, target: target), sourceSize: snapshot.frame.size,
                isCurrentWindow: id == currentWindowID, previewKey: snapshot.previewKey.on(screen))
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
        let usesKeyboard = panel.isVisible ? panel.keyboardSelection : keyboardTriggered
        panel.show(in: target.screenFlipped, items: items, offerPermission: offerPermission, message: statusMessage,
                   remainingRegions: remaining, keyboardTriggered: usesKeyboard, images: images,
                   waitForPreviews: LayoutHelperPermission.previewsSupported && !offerPermission)
        refreshPreviews()
    }

    private func unavailableReason(_ snapshot: LayoutHelperWindowSnapshot, target: CGRect) -> String? {
        if LayoutHelperLayout.matches(snapshot.frame, target) { return nil }
        // An expired observation is unknown, not a reason to block a retry.
        guard ProcessInfo.processInfo.systemUptime - snapshot.observedAt < 1.5 else { return nil }
        if snapshot.resizable == false { return "This window cannot be resized" }
        return nil
    }

    private func select(_ id: CGWindowID) {
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
                  self.retainedIsValid(), self.unavailableReason(snapshot, target: target) == nil else {
                self.selecting = false
                self.showNext(message: snapshot == nil ? "That window is not responding. Try again." : "That window could not be placed. Try again.")
                return
            }
            self.place(window, snapshot: snapshot, target: target, selectionToken: selectionToken)
        }
    }

    private func place(_ window: AccessibilityElement, snapshot: LayoutHelperWindowSnapshot,
                       target: CGRect, selectionToken: UUID) {
        guard let layout, let screen, let selectedCell = currentCell else { selecting = false; return }
        WindowSizeConstraints.shared.cancelPendingObservations()
        let generation = WindowSizeConstraints.shared.observationGeneration
        let original = snapshot.frame
        placingWindow = window
        panel.dismiss()
        previews.stop()
        cancelImageDelivery()
        catalog.suspendForPlacement()
        WindowAnimationDiagnostics.event("helper-placement-start", fields: ["windowID": snapshot.id])
        let bounds = layout.screen
        let placement = WindowAnimationPlacement(screenFrame: bounds,
            sharedEdges: Defaults.moveFixedSizeToEdge.value.alignmentEdges(for: target, in: bounds),
            constrainToScreen: true, gap: CGFloat(Defaults.gapSize.value))
        window.activateAndRaiseWindow(isCurrent: { [weak self] in
            self?.token == selectionToken && self?.placingWindow == window
        }) { [weak self] activation, main, raise in
            guard let self, self.token == selectionToken, self.placingWindow == window else { return }
            WindowAnimationDiagnostics.event("helper-window-raise", fields: ["windowID": snapshot.id,
                "activation": activation.rawValue, "main": main.rawValue, "raise": raise.rawValue])
            WindowPlacementCoordinator.shared.place(window, from: original, to: target, placement: placement,
                animated: WindowAnimator.enabled, profile: .layoutHelper,
                isCurrent: { [weak self] in
                    guard let self, self.token == selectionToken,
                          WindowSizeConstraints.shared.observationGeneration == generation,
                          NSScreen.screens.contains(screen),
                          LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, bounds) else { return false }
                    return self.retainedIsValid()
                }) { [weak self] outcome in
                    guard let self, self.token == selectionToken else { return }
                    WindowAnimationDiagnostics.event("helper-placement-complete", fields: ["windowID": snapshot.id,
                        "outcome": String(describing: outcome)])
                    self.placingWindow = nil; self.selecting = false
                    switch outcome {
                    case .placed(let frame):
                        WindowSizeConstraints.shared.recordSuccessfulPlacement(window, frame: frame)
                        if AppDelegate.windowHistory.restoreRects[snapshot.id] == nil
                            || AppDelegate.windowHistory.lastRectangleActions[snapshot.id]?.rect != original {
                            AppDelegate.windowHistory.restoreRects[snapshot.id] = original
                        }
                        AppDelegate.windowHistory.lastRectangleActions[snapshot.id] = RectangleAction(action: .specified, subAction: nil, rect: frame, count: 1)
                        self.completedCells.insert(selectedCell)
                        self.retained[window] = frame
                        self.retainedLaunches[snapshot.id] = snapshot.launch
                        WindowDividerManager.shared.record(window, id: snapshot.id, frame: frame,
                            screen: screen, eligibilityConfirmed: true)
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
        }
    }

    private func validateSession() {
        guard !selecting else { return }
        guard let layout, let screen, Defaults.layoutHelper.userEnabled,
              NSScreen.screens.contains(screen),
              LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, layout.screen),
              retainedIsValid() else { cancel(); return }
        if !LayoutHelperPermission.previewsAllowed { previews.clear() }
        previews.removeClosedWindows(live: Set(WindowUtil.getWindowList().map(\.id)))
        catalog.refresh()
    }

    private func refreshPreviews() {
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
        guard (result.source == .dragToSnap || ((result.source == .keyboardShortcut || result.source == .menuItem) && Defaults.layoutHelperKeyboard.enabled)),
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
        guard Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsSupported,
              LayoutHelperLayout.make(action: action, screen: screen.adjustedVisibleFrame().screenFlipped,
                                    anchor: anchor.screenFlipped, includeDenseGrids: Defaults.layoutHelperDenseGrids.enabled) != nil else { cancelPrefetch(); return }
        if prefetchScreen == screen, prefetchWindow == id { return }
        cancelPrefetch()
        prefetchScreen = screen; prefetchWindow = id
        let requestToken = token
        let prefetchGeneration = prefetchGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == requestToken, self.prefetchGeneration == prefetchGeneration, !self.panel.isVisible, self.layout == nil else { return }
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
