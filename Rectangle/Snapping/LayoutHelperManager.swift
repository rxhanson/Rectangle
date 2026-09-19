import Cocoa
import ScreenCaptureKit

/// Use the same preference and accessibility gates as other window moves, then
/// perform the normal final AX write before checking the achieved placement.
enum LayoutHelperPlacement {
    static func move(_ window: AccessibilityElement, to target: CGRect, completion: @escaping () -> Void) {
        WindowAnimator.shared.animate(window, to: target) { frame in
            if frame.isNull { window.setFrame(target) }
            completion()
        }
    }
}

/// Owns one assist sequence. Tokens prevent late animation/capture callbacks from
/// reviving a dismissed picker or placing a window into a newer layout.
final class LayoutHelperManager {
    static let shared = LayoutHelperManager()
    private(set) var token = UUID()
    private var pending: DispatchWorkItem?
    private let previews = LayoutHelperPreviewStore()
    private var prefetchTask: DispatchWorkItem?
    private var previewKeys: [CGWindowID: LayoutHelperPreviewKey] = [:]
    private var displayedIDs: [CGWindowID] = []
    private var appOrder = LayoutHelperWindowOrder()
    private var keyboardTriggered = false
    private var layout: LayoutHelperLayout?
    private var screen: NSScreen?
    private var retained: [AccessibilityElement: CGRect] = [:]
    private var candidates: [CGWindowID: AccessibilityElement] = [:]
    private var currentCell: Int?
    private var selecting = false
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
    }

    @discardableResult func cancel() -> UUID {
        token = UUID()
        // Settle only this sequence's accepted move. Invalidate the token first
        // so finishing it cannot reopen the picker after Escape or a new drag.
        if let placingWindow, WindowAnimator.shared.destination(for: placingWindow) != nil {
            WindowAnimator.shared.finish()
        }
        placingWindow = nil
        pending?.cancel(); pending = nil
        cancelPrefetch()
        previews.stop()
        if !Defaults.layoutHelper.userEnabled { previews.clear() }
        previewKeys.removeAll(); displayedIDs.removeAll()
        appOrder = LayoutHelperWindowOrder()
        refreshTimer?.invalidate(); refreshTimer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        panel.dismiss()
        layout = nil; screen = nil; currentCell = nil
        selecting = false
        retained.removeAll(); candidates.removeAll()
        return token
    }

    func didSnap(result: ResultParameters, frame: CGRect) {
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
            guard LayoutHelperLayout.matches(result.windowElement.frame, frame) else { self.cancel(); return }
            self.keyboardTriggered = result.source == .keyboardShortcut
            self.layout = plan
            self.screen = result.calcResult.screen
            self.retained = [result.windowElement: frame]
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

    private func availableWindows(on requestedScreen: NSScreen? = nil) -> [(CGWindowID, AccessibilityElement)] {
        guard let screen = requestedScreen ?? screen else { return [] }
        // Joining to the on-screen WindowServer inventory filters other Spaces and
        // avoids using Rectangle's synthetic bookkeeping IDs for image capture.
        let infos = WindowUtil.getWindowList().filter { $0.level == 0 && $0.pid != getpid() }
        var result: [(CGWindowID, AccessibilityElement)] = []
        var seen = Set<CGWindowID>()
        for pid in Set(infos.map(\.pid)) {
            let app = AccessibilityElement(pid)
            app.setMessagingTimeout(0.15)
            let bundle = app.bundleIdentifier ?? ""
            if Defaults.disabledApps.typedValue?.contains(bundle) == true
                || Defaults.fullIgnoreBundleIds.typedValue?.contains(bundle) == true { continue }
            for window in app.windowElements ?? [] {
                window.setMessagingTimeout(0.15)
                guard window.isWindow == true, window.isSheet != true, window.isMinimized != true,
                      window.isHidden != true, window.isSystemDialog != true, window.isFullScreen != true,
                      !window.frame.isNull,
                      ScreenDetection().detectScreens(using: window)?.currentScreen == screen,
                      !(Defaults.todo.userEnabled && TodoManager.isTodoWindow(window)) else { continue }
                let matches = infos.filter { $0.pid == pid && ($0.id == window.windowId || LayoutHelperLayout.matches($0.frame, window.frame, tolerance: 1)) }
                let info = matches.first { $0.id == window.windowId } ?? (matches.count == 1 ? matches.first : nil)
                guard let info, seen.insert(info.id).inserted else { continue }
                result.append((info.id, window))
            }
        }
        let order = Dictionary(uniqueKeysWithValues: infos.enumerated().map { ($0.element.id, $0.offset) })
        return result.sorted { (order[$0.0] ?? 0) < (order[$1.0] ?? 0) }
    }

    private func showNext(message: String? = nil) {
        guard let layout else { return }
        let windows = availableWindows()
        var occupied = Set([layout.anchorIndex])
        for (window, frame) in retained {
            guard LayoutHelperLayout.matches(window.frame, frame) else { cancel(); return }
            occupied.formUnion(layout.occupiedCells(by: frame))
        }
        for (_, window) in windows where retained[window] == nil {
            let cells = layout.prefilledCells(by: window.frame)
            if !cells.isEmpty && occupied.isDisjoint(with: cells) {
                occupied.formUnion(cells)
                retained[window] = window.frame
            }
        }
        // Both left/right and top/bottom picker completions can form a pair.
        if layout.cells.count == 2, let screen {
            for (window, frame) in retained {
                WindowDividerManager.shared.record(window, id: window.windowId, frame: frame, screen: screen)
            }
        }
        guard let next = layout.remaining(excluding: occupied).first else { cancel(); return }
        candidates = Dictionary(uniqueKeysWithValues: windows.filter { retained[$0.1] == nil })
        guard !candidates.isEmpty else { cancel(); return }
        currentCell = next
        let target = layout.target(for: layout.cells[next])
        let candidateWindows = windows.filter { candidates[$0.0] != nil }
        let currentWindowID = candidateWindows.first { LayoutHelperLayout.matches($0.1.frame, target) }?.0
        let appOrderedIDs = appOrder.ordered(candidateWindows.map { id, window in
            (id, window.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "pid:\(window.pid ?? 0)")
        })
        let orderedIDs = appOrderedIDs.filter { $0 == currentWindowID } + appOrderedIDs.filter { $0 != currentWindowID }
        previewKeys = Dictionary(uniqueKeysWithValues: candidateWindows.compactMap { id, window in
            LayoutHelperPreviewStore.key(id: id, window: window).map { (id, $0) }
        })
        let items = orderedIDs.compactMap { id -> LayoutHelperPanel.Item? in
            guard let window = candidates[id] else { return nil }
            let app = window.pid.flatMap { NSRunningApplication(processIdentifier: $0) }
            let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? app?.localizedName ?? "Window"
            return LayoutHelperPanel.Item(id: id, title: title, icon: app?.icon,
                unavailableReason: unavailableReason(window, target: target), sourceSize: window.frame.size,
                isCurrentWindow: id == currentWindowID)
        }
        var offerPermission = false
        if #available(macOS 14, *) { offerPermission = !CGPreflightScreenCaptureAccess() }
        let remaining = layout.remaining(excluding: occupied).filter { $0 != next }
            .map { layout.target(for: layout.cells[$0]).screenFlipped }
        displayedIDs = items.map(\.id)
        let images: [CGWindowID: NSImage] = offerPermission ? [:] : Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let key = previewKeys[item.id], let image = previews.cached(key) else { return nil }
            return (item.id, image)
        })
        let usesKeyboard = panel.isVisible ? panel.keyboardSelection : keyboardTriggered
        panel.show(in: target.screenFlipped, items: items, offerPermission: offerPermission, message: message,
                   remainingRegions: remaining, keyboardTriggered: usesKeyboard, images: images)
        refreshPreviews()
    }

    private func unavailableReason(_ window: AccessibilityElement, target: CGRect) -> String? {
        if LayoutHelperLayout.matches(window.frame, target) { return nil }
        if !window.isResizable() { return "This window cannot be resized" }
        if let minimum = window.minimumSize, minimum.width > target.width + 3 || minimum.height > target.height + 3 {
            return "Too large for this space"
        }
        return nil
    }

    private func select(_ id: CGWindowID) {
        guard !selecting, let layout, let currentCell, let window = candidates[id] else { return }
        guard availableWindows().contains(where: { $0.0 == id && $0.1 == window }) else { showNext(); return }
        let target = layout.target(for: layout.cells[currentCell])
        guard unavailableReason(window, target: target) == nil else { showNext(); return }
        if LayoutHelperLayout.matches(window.frame, target) {
            retained[window] = window.frame
            window.bringToFront(force: true)
            showNext()
            return
        }
        WindowSizeConstraints.shared.cancelPendingObservations()
        let sizeObservationGeneration = WindowSizeConstraints.shared.observationGeneration
        let original = window.frame
        let previousRestore = AppDelegate.windowHistory.restoreRects[id]
        selecting = true
        if previousRestore == nil || AppDelegate.windowHistory.lastRectangleActions[id]?.rect != original {
            AppDelegate.windowHistory.restoreRects[id] = original
        }
        let selectionToken = token
        placingWindow = window
        // Reveal the actual window throughout its movement into the empty area.
        panel.dismiss()
        previews.stop()
        window.bringToFront(force: true)
        LayoutHelperPlacement.move(window, to: target) { [weak self] in
            guard let self, self.token == selectionToken else { return }
            self.placingWindow = nil
            // Allow delayed AX acknowledgements after the animation's final write,
            // never while the window is still passing through intermediate frames.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.token == selectionToken else { return }
                let first = window.frame
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    guard let self, self.token == selectionToken else { return }
                    let settled = window.frame
                    WindowSizeConstraints.shared.recordSettledResize(window, before: original, requested: target,
                        first: first, settled: settled, generation: sizeObservationGeneration)
                    self.selecting = false
                    guard LayoutHelperLayout.matches(settled, target) else {
                        window.setFrame(original)
                        AppDelegate.windowHistory.restoreRects[id] = previousRestore
                        self.showNext(message: "That window could not fit. Choose another.")
                        return
                    }
                    AppDelegate.windowHistory.lastRectangleActions[id] = RectangleAction(action: .specified, subAction: nil, rect: target, count: 1)
                    self.retained[window] = target
                    window.bringToFront(force: true)
                    self.showNext()
                }
            }
        }
    }

    private func validateSession() {
        guard !selecting else { return }
        guard let layout, let screen, Defaults.layoutHelper.userEnabled,
              NSScreen.screens.contains(screen),
              LayoutHelperLayout.matches(screen.adjustedVisibleFrame().screenFlipped, layout.screen),
              retained.allSatisfy({ $0.key.isMinimized != true && $0.key.isHidden != true && LayoutHelperLayout.matches($0.key.frame, $0.value) })
        else { cancel(); return }
        let windows = availableWindows()
        if !LayoutHelperPermission.previewsAllowed { previews.clear() }
        previews.removeClosedWindows(live: Set(WindowUtil.getWindowList().map(\.id)))
        let available = Set(windows.map(\.0))
        let expected = Set(windows.filter { retained[$0.1] == nil }.map(\.0))
        if !Set(candidates.keys).isSubset(of: available) || expected != Set(candidates.keys) { showNext() }
    }

    private func refreshPreviews() {
        guard panel.isVisible else { return }
        let visible = panel.visiblePreviewIDs
        let ids = visible + displayedIDs.filter { !visible.contains($0) }
        let captureToken = token
        let cell = currentCell
        previews.request(ids.compactMap { previewKeys[$0] }) { [weak self] key, image in
            guard let self, self.token == captureToken, self.currentCell == cell,
                  self.previewKeys[key.id] == key else { return }
            self.panel.updateImage(image, for: key.id)
        }
    }

    func cancelPrefetch() {
        prefetchTask?.cancel(); prefetchTask = nil
        if !panel.isVisible { previews.stop() }
    }

    /// One debounced batch as a drag enters an eligible snap area. No idle polling.
    func prefetch(on screen: NSScreen, action: WindowAction, anchor: CGRect, excluding id: CGWindowID?) {
        cancelPrefetch()
        guard Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsAllowed,
              LayoutHelperLayout.make(action: action, screen: screen.adjustedVisibleFrame().screenFlipped,
                                    anchor: anchor.screenFlipped, includeDenseGrids: Defaults.layoutHelperDenseGrids.enabled) != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panel.isVisible else { return }
            let windows = self.availableWindows(on: screen).filter { $0.0 != id }
            self.previews.removeClosedWindows(live: Set(WindowUtil.getWindowList().map(\.id)))
            self.previews.request(windows.compactMap { LayoutHelperPreviewStore.key(id: $0.0, window: $0.1) })
        }
        prefetchTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}
