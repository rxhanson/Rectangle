import Cocoa

/// Tracks one confirmed horizontal or vertical pair per display.
final class WindowDividerManager {
    static let shared = WindowDividerManager()

    private struct Entry {
        let id: CGWindowID
        let element: AccessibilityElement
        let identity: WindowDividerPreparedPair.Input
        let app: NSRunningApplication
        let screen: NSScreen
        let workArea: CGRect
        let displayWorkArea: CGRect
        let requestID: UUID
        var frame: CGRect
        let recordedAt = ProcessInfo.processInfo.systemUptime
    }
    private final class Pair {
        var left: Entry
        var right: Entry
        let axis: WindowSplitAxis
        var settleUntil: TimeInterval = 0
        var observedAt: TimeInterval = 0
        var prepared: WindowDividerPreparedPair?
        var divider: CGFloat { (axis.rect(left.frame).maxX + axis.rect(right.frame).minX) / 2 }
        var center: CGPoint { point(at: divider) }
        func point(at value: CGFloat) -> CGPoint { axis.point(value, cross: axis.rect(left.frame).midY) }
        var hoverFrame: CGRect {
            axis.rect(CGRect(x: divider - 24, y: axis.rect(left.frame).midY - 54, width: 48, height: 108))
        }
        init(left: Entry, right: Entry, axis: WindowSplitAxis) {
            self.left = left; self.right = right; self.axis = axis
        }
    }

    private var entries: [CGWindowID: Entry] = [:]
    private var pairs: [UInt32: Pair] = [:]
    private var shown: Pair?
    private var active: Pair?
    private var resize: WindowDividerResize?
    private var operation: WindowDividerOperation?
    private var observationRunning = false
    private var observationGeneration = 0
    private var recordGeneration = 0
    private var recordRequests: [CGWindowID: UUID] = [:]
    private var recordRunning = false
    private var pendingRecords: [CGWindowID: () -> Void] = [:]
    private var hoverTimer: Timer?
    private var pointerOffset: CGFloat = 0
    private var snapshotTask: Task<Void, Never>?
    private var snapshotRequest: UUID?
    private let snapshot = WindowDividerSnapshot()
    private var sizeWarning: WindowSizeWarning?
    private var dragging = false
    private lazy var panel = WindowDividerPanel()
    private lazy var overlay = WindowDividerOverlay()
    private var observations: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var localMonitor: Any?

    private var started = false
    private(set) var monitoring = false

    /// Called once Accessibility has initialized window management.
    func start() {
        guard !started else { return }
        started = true
        refreshMonitoring()
    }

    func refreshMonitoring() {
        guard started else { return }
        if monitoring { clear() }
        if Defaults.windowDivider.enabled {
            if !monitoring { startMonitoring() }
        } else if monitoring {
            monitoring = false
            for token in observations {
                NotificationCenter.default.removeObserver(token)
                NSWorkspace.shared.notificationCenter.removeObserver(token)
            }
            observations.removeAll()
            if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        }
    }

    private func startMonitoring() {
        monitoring = true
        if Defaults.windowDividerEnhanced.enabled { _ = WindowCapturePermission.previewsAllowed }

        observations.append(Notification.Name.windowActionCompleted.onPost(queue: .main) { [weak self] note in
            guard let placement = note.object as? WindowActionCompletion else { return }
            self?.record(placement)
        })
        // Intents can be rejected or concern an unrelated window. The write
        // fence transfers a released pair only when an operation claims a member.
        observations.append(Notification.Name.windowActionWillExecute.onPost(queue: .main) { [weak self] _ in
            if self?.dragging == true { self?.interrupt() }
        })
        panel.onBegin = { [weak self] x in self?.begin(pointerX: x) ?? false }
        panel.onDrag = { [weak self] x in
            guard let self, self.dragging, let pair = self.active,
                  let preview = self.resize?.preview(to: x - self.pointerOffset) else { return }
            self.panel.show(at: pair.point(at: preview).screenFlipped, axis: pair.axis)
            self.overlay.show(in: pair.left.frame.union(pair.right.frame).screenFlipped, divider: preview,
                              gap: self.resize?.geometry.gap ?? 0, axis: pair.axis, below: self.panel)
        }
        panel.onEnd = { [weak self] in self?.endDrag() }
        panel.onReset = { [weak self] in self?.reset() }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.handleInterruption(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown || self?.panel.containsPointerEvent(event) != true { self?.handleInterruption(event) }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.willTerminateNotification] {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.clear() })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.interrupt(animated: false) })
        }
        observations.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.recordGeneration += 1
                self?.pendingRecords.removeAll()
                self?.recordRequests.removeAll()
                self?.interrupt(animated: false)
            })
    }

    private func screenID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func containsPointerEvent(_ event: NSEvent) -> Bool {
        // AX validation can lag behind the next pointer update. Classify the
        // original event, otherwise a quick drag can cancel its own mouse-down.
        return monitoring && (dragging || panel.containsPointerEvent(event))
    }

    private func record(_ placement: WindowActionCompletion) {
        let result = placement.result
        guard Defaults.windowDivider.enabled, let id = result.windowId else { return }
        let window = result.windowElement
        let frame = placement.achievedFrame
        let screen = result.calcResult.screen
        func reject(_ reason: String) {
            DiagnosticTrace.event("divider-record-rejected", fields: ["windowID": id, "reason": reason])
        }
        // A settlement supersedes the previous observation even when its frame is ineligible.
        recordRequests.removeValue(forKey: id)
        pendingRecords.removeValue(forKey: id)
        // A newly confirmed frame replaces any former membership, including a
        // move away from the shared edge or a newly fixed-size window.
        if let old = entries[id],
           !WindowGeometry.matches(old.frame, frame, tolerance: 1)
               || old.screen != screen || old.workArea != result.visibleFrameOfScreen
               || result.isFixedSize || old.element != window {
            retire(id: id)
        }
        guard !result.isFixedSize, let pid = window.pid,
              let app = NSRunningApplication(processIdentifier: pid), !app.isHidden, !app.isTerminated,
              let identity = WindowDividerPreparedPair.Input(id: id, pid: pid) else {
            reject("ineligible-window")
            return
        }
        let area = result.visibleFrameOfScreen
        let gap = max(0, CGFloat(Defaults.gapSize.value))
        let bounds = GapCalculation.applyGaps(area, gapSize: Float(gap),
            skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
        guard let axis = WindowDividerGeometry.axis(for: frame, in: bounds) else {
            DiagnosticTrace.event("divider-record-rejected", fields: ["windowID": id, "reason": "work-area",
                "frame": [frame.minX, frame.minY, frame.width, frame.height],
                "bounds": [bounds.minX, bounds.minY, bounds.width, bounds.height]])
            return
        }
        let normalized = axis.rect(frame), extent = axis.rect(bounds)
        // Validate identity asynchronously before this placement can form a pair.
        let entry = Entry(id: id, element: window, identity: identity, app: app, screen: screen, workArea: area,
                          displayWorkArea: screen.adjustedVisibleFrame(TodoManager.isTodoWindow(id)),
                          requestID: UUID(), frame: frame)
        recordRequests[id] = entry.requestID
        entries = entries.filter { !$0.value.app.isTerminated }
        let generation = recordGeneration
        pendingRecords[id] = { [weak self] in
            guard let self else { return }
            self.recordRunning = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var eligibilityConfirmed = false
                let visibleOrder = Self.settledInventory(id: id, pid: pid, frame: frame, isCurrent: { identity.isCurrent },
                    eligible: {
                        if !eligibilityConfirmed, let resolved = WindowDividerPreparedPair.read(identity) {
                            // Some apps vend different AX wrappers when enumerating their windows.
                            eligibilityConfirmed = CFEqual(resolved.element, window.axElement) || window.windowId == id
                        }
                        return eligibilityConfirmed
                    }, inventory: { WindowUtil.getWindowList(forceRefresh: true, cacheResult: false) })
                let existing = visibleOrder == nil ? [] : WindowUtil.getWindowList(all: true, forceRefresh: true, cacheResult: false)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer { self.recordRunning = false; self.pumpRecord() }
                    guard self.recordGeneration == generation, self.recordRequests[id] == entry.requestID else { return }
                    self.recordRequests.removeValue(forKey: id)
                    guard Defaults.windowDivider.enabled, let visibleOrder else {
                        reject(eligibilityConfirmed ? "window-server-frame" : "accessibility")
                        return
                    }
                    self.entries[id] = entry
                    self.recordPair(entry, candidates: Array(self.entries.values), visibleOrder: visibleOrder, existing: existing,
                        screen: screen, axis: axis, normalized: normalized, extent: extent, area: area, gap: gap)
                }
            }
        }
        pumpRecord()
    }

    /// AX can acknowledge the snap one compositor update before the on-screen list reflects it.
    /// Return the matching inventory itself so pairing sees both members in the same observation.
    static func settledInventory(id: CGWindowID, pid: pid_t, frame: CGRect, isCurrent: () -> Bool,
                                 eligible: () -> Bool, inventory: () -> [WindowInfo],
                                 now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                                 pause: () -> Void = { Thread.sleep(forTimeInterval: 0.025) }) -> [WindowInfo]? {
        let deadline = now() + 0.25
        var firstRead = true
        repeat {
            guard isCurrent() else { return nil }
            if eligible() {
                let visible = inventory()
                if let member = visible.first(where: { $0.id == id }) {
                    guard member.pid == pid else { return nil }
                    if member.isOnScreen && WindowGeometry.matches(member.frame, frame), isCurrent() { return visible }
                    if firstRead {
                        DiagnosticTrace.event("divider-record-waiting", fields: ["windowID": id, "reason": "window-server-frame",
                            "observed": [member.frame.minX, member.frame.minY, member.frame.width, member.frame.height]])
                    }
                } else if firstRead {
                    DiagnosticTrace.event("divider-record-waiting", fields: ["windowID": id, "reason": "not-visible"])
                }
            } else if firstRead {
                DiagnosticTrace.event("divider-record-waiting", fields: ["windowID": id, "reason": "accessibility"])
            }
            firstRead = false
            guard now() < deadline else { return nil }
            pause()
        } while now() <= deadline
        return nil
    }

    private func pumpRecord() {
        guard !recordRunning, let next = pendingRecords.first else { return }
        pendingRecords.removeValue(forKey: next.key)
        next.value()
    }

    private func retire(id: CGWindowID) {
        entries.removeValue(forKey: id)
        pendingRecords.removeValue(forKey: id)
        recordRequests.removeValue(forKey: id)
        if let active, active.left.id == id || active.right.id == id { interrupt() }
        for (display, pair) in pairs where pair.left.id == id || pair.right.id == id {
            if shown === pair { interrupt() }
            pairs.removeValue(forKey: display)
        }
    }

    private func workAreaIsCurrent(_ pair: Pair) -> Bool {
        guard let screen = NSScreen.screens.first(where: { screenID($0) == screenID(pair.left.screen) }) else { return false }
        return [pair.left, pair.right].allSatisfy {
            screen.adjustedVisibleFrame(TodoManager.isTodoWindow($0.id)) == $0.displayWorkArea
        }
    }

    private func recordPair(_ entry: Entry, candidates: [Entry], visibleOrder: [WindowInfo], existing: [WindowInfo],
                            screen: NSScreen, axis: WindowSplitAxis, normalized: CGRect,
                            extent: CGRect, area: CGRect, gap: CGFloat) {
        let id = entry.id
        let liveIDs = Self.retainedWindowIDs(recorded: Set(entries.keys), existing: existing, recording: id)
        entries = entries.filter { liveIDs.contains($0.key) }
        // Prune closed windows before applying the cap, so they cannot evict
        // a still-visible partner from a long-running application.
        if entries.count > 32, let oldest = entries.values.filter({ $0.id != id }).min(by: { $0.recordedAt < $1.recordedAt }) { entries.removeValue(forKey: oldest.id) }
        let orderedEntries = candidates.filter { entries[$0.id]?.requestID == $0.requestID }.sorted { a, b in
            (visibleOrder.firstIndex(where: { $0.id == a.id }) ?? Int.max)
                < (visibleOrder.firstIndex(where: { $0.id == b.id }) ?? Int.max)
        }
        for other in orderedEntries where other.id != id && screenID(other.screen) == screenID(screen) && other.workArea == area {
            guard !other.app.isTerminated, visibleOrder.contains(where: {
                $0.id == other.id && $0.pid == other.app.processIdentifier
                    && WindowGeometry.matches($0.frame, other.frame)
            }) else { continue }
            let left = normalized.minX < axis.rect(other.frame).minX ? entry : other
            let right = left.id == id ? other : entry
            guard abs(axis.rect(left.frame).minX - extent.minX) <= 3,
                  abs(axis.rect(right.frame).maxX - extent.maxX) <= 3,
                  let geometry = WindowDividerGeometry(left: left.frame, right: right.frame, axis: axis),
                  abs(geometry.gap - gap) <= 3 else { continue }
            let key = screenID(screen)
            if let current = pairs[key], current.left.id == left.id, current.right.id == right.id,
               WindowGeometry.matches(current.left.frame, left.frame), WindowGeometry.matches(current.right.frame, right.frame) { return }
            if let previous = pairs[key], active == nil, shown === previous { interrupt() }
            pairs[key] = Pair(left: left, right: right, axis: axis)
            DiagnosticTrace.event("divider-pair-recorded", fields: ["left": left.id, "right": right.id, "display": key])
            startHoverTimer()
            return
        }
        DiagnosticTrace.event("divider-record-unpaired", fields: ["windowID": id, "known": Array(entries.keys)])
    }

    private func startHoverTimer() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.poll() }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func poll() {
        guard Defaults.windowDivider.enabled else { clear(); return }
        pairs = pairs.filter { !$0.value.left.app.isTerminated && !$0.value.right.app.isTerminated }
        guard !pairs.isEmpty else { interrupt(); hoverTimer?.invalidate(); hoverTimer = nil; return }
        let point = NSEvent.mouseLocation.screenFlipped
        guard let pair = active ?? pairs.values.first(where: { $0.hoverFrame.contains(point) }) else { panel.hide(); shown = nil; return }
        // Release owns all AX I/O until placement finishes. Pointer tracking
        // uses the proposed geometry and never waits for an app or WindowServer.
        guard workAreaIsCurrent(pair) else {
            retire(id: pair.left.id)
            retire(id: pair.right.id)
            return
        }
        guard active == nil else { return }
        guard !observationRunning else { return }
        let left = pair.left.identity, right = pair.right.identity
        observationRunning = true
        let generation = observationGeneration
        let ownedPIDs: Set<pid_t> = [pair.left.app.processIdentifier, pair.right.app.processIdentifier, getpid()]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let infos = WindowUtil.getWindowList(forceRefresh: true, cacheResult: false)
            // Refresh reported constraints for the next drag; a previous preparation
            // must not keep an app's old minimum after the app changes it.
            let preparation = WindowDividerPreparedPair(left: left, right: right)
            let passive = WindowDividerPreparedPair.passiveCaptureOverlayIDs(in: infos, at: point, ownedPIDs: ownedPIDs)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.observationRunning = false
                guard self.observationGeneration == generation, self.active == nil,
                      self.pairs[self.screenID(pair.left.screen)] === pair,
                      pair.hoverFrame.contains(NSEvent.mouseLocation.screenFlipped) else { return }
                // Occlusion and an AX timeout are temporary. Hide the handle
                // and retry without forgetting the accepted pair.
                // Preparation re-resolves both accepted CG window IDs in their original process launches.
                guard let preparation, self.visible(pair, in: infos, ignoring: passive) else {
                    pair.prepared = nil
                    self.panel.hide(); self.shown = nil
                    return
                }
                guard let l = infos.first(where: { $0.id == pair.left.id })?.frame,
                      let r = infos.first(where: { $0.id == pair.right.id })?.frame,
                      let original = WindowDividerGeometry(left: pair.left.frame, right: pair.right.frame, axis: pair.axis),
                      original.containsPair(left: l, right: r) else {
                    if ProcessInfo.processInfo.systemUptime < pair.settleUntil { return }
                    self.pairs.removeValue(forKey: self.screenID(pair.left.screen))
                    self.interrupt(); return
                }
                pair.left.frame = l; pair.right.frame = r
                pair.prepared = preparation
                pair.observedAt = ProcessInfo.processInfo.systemUptime
                self.shown = pair
                self.showHandle(pair)
            }
        }
    }

    private func visible(_ pair: Pair, in infos: [WindowInfo], ignoring: Set<CGWindowID> = []) -> Bool {
        guard !pair.left.app.isTerminated, !pair.right.app.isTerminated,
              infos.contains(where: { $0.id == pair.left.id && $0.pid == pair.left.app.processIdentifier }),
              infos.contains(where: { $0.id == pair.right.id && $0.pid == pair.right.app.processIdentifier }) else { return false }
        return WindowDividerGeometry.unobscured(left: pair.left.id, right: pair.right.id,
                                                    in: infos, near: pair.hoverFrame,
                                                    ignoring: ignoring.union(Set([panel, overlay].compactMap { CGWindowID(exactly: $0.windowNumber) })))
    }

    private func begin(pointerX: CGFloat? = nil, resetting: Bool = false) -> Bool {
        sizeWarning?.hide()
        finishMovement()
        guard let pair = shown, pairs[screenID(pair.left.screen)] === pair,
              let prepared = pair.prepared, workAreaIsCurrent(pair),
              (resetting || ProcessInfo.processInfo.systemUptime - pair.observedAt < 0.3) else { panel.hide(); poll(); return false }
        let l = pair.left.element, r = pair.right.element
        guard WindowAnimator.shared.destination(for: l) == nil,
              WindowAnimator.shared.destination(for: r) == nil,
              let engine = WindowDividerResize(left: pair.left.frame, right: pair.right.frame, axis: pair.axis,
                  minimumLeft: WindowDividerGeometry.minimumExtent(reported: prepared.left.minimum,
                      current: pair.left.frame.size, axis: pair.axis),
                  minimumRight: WindowDividerGeometry.minimumExtent(reported: prepared.right.minimum,
                      current: pair.right.frame.size, axis: pair.axis)) else { return false }
        active = pair; resize = engine; dragging = true
        panel.holdVisible()
        let captureEnabled = WindowDividerSnapshot.enabled
        overlay.snapshotScreenFrame = captureEnabled ? pair.left.screen.frame : nil
        pointerOffset = (pointerX ?? pair.divider) - pair.divider
        overlay.show(in: engine.geometry.outer.screenFlipped, divider: pair.divider, gap: engine.geometry.gap, axis: pair.axis, below: panel)
        if captureEnabled { captureBackground(engine: engine, pair: pair) }
        return true
    }

    private func transition(to x: CGFloat) {
        DiagnosticTrace.event("divider-release")
        guard let engine = resize, let pair = active,
              let target = engine.geometry.frames(at: x, minimumLeft: engine.minimumLeft, minimumRight: engine.minimumRight) else { interrupt(); return }
        dragging = false
        engine.cancelPreview()

        snapshotRequest = nil
        snapshotTask?.cancel(); snapshotTask = nil
        snapshot.clear()
        panel.hide(animated: false)
        // Keep the preview visible until both windows acknowledge placement.
        overlay.show(in: engine.geometry.outer.screenFlipped,
                     divider: pair.axis.rect(target.left).maxX + engine.geometry.gap / 2,
                     gap: engine.geometry.gap, axis: pair.axis, below: panel)
        DiagnosticTrace.event("divider-surface-ready", fields: ["frozen": overlay.guide.frozenImage != nil])
        place(engine: engine, pair: pair, divider: x)
    }

    private func captureBackground(engine: WindowDividerResize, pair: Pair) {
        let request = UUID()
        snapshotRequest = request
        snapshot.prepare()
        DiagnosticTrace.event("divider-snapshot-start")
        snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await self.snapshot.capture(frame: self.overlay.frame.screenFlipped,
                displayID: self.screenID(pair.left.screen), scale: pair.left.screen.backingScaleFactor)
            guard !Task.isCancelled, self.snapshotRequest == request, self.active === pair,
                  self.resize === engine, self.dragging else { return }
            self.snapshotRequest = nil
            self.snapshotTask = nil
            self.snapshot.clear()
            DiagnosticTrace.event("divider-snapshot-result", fields: ["captured": image != nil])
            if let image, WindowDividerSnapshot.enabled { self.overlay.freeze(image) }
        }
    }

    private func place(engine: WindowDividerResize, pair: Pair, divider x: CGFloat) {
        guard let prepared = pair.prepared, workAreaIsCurrent(pair) else { interrupt(); return }
        DiagnosticTrace.event("divider-placement-start")
        let fence = WindowWriteFence.shared
        let targets = [pair.left, pair.right].map { WindowWriteTarget(element: $0.element, windowID: $0.id) }
        let lease = fence.claim(targets, onSuperseded: { [weak self, weak pair] in
            guard let self, let pair, self.active === pair else { return }
            self.interrupt()
        })
        let operation = WindowDividerOperation(lease: lease)
        self.operation = operation
        let ignoring = Set([panel, overlay].compactMap { CGWindowID(exactly: $0.windowNumber) })
        let hoverFrame = pair.hoverFrame
        let policy = Defaults.enhancedUI.value
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        let left = engine.left, right = engine.right, axis = pair.axis
        let placeWhenReady = { [weak self] in
            guard lease.isCurrent, let self, self.active === pair, self.operation === operation else { return }
            guard self.workAreaIsCurrent(pair) else {
                self.interrupt()
                return
            }
            fence.perform(lease, work: {
                let result = prepared.place(left: left, right: right, axis: axis, divider: x,
                    ignoring: ignoring, hoverFrame: hoverFrame, policy: policy, assistive: assistive, operation: operation)
                let observed = result == nil && lease.isCurrent ? prepared.observedFrames() : (left: nil, right: nil)
                return (result, observed)
            }, completion: { [weak self] result, observed in
                defer { fence.finish(lease) }
                guard let self, lease.isCurrent, self.operation === operation,
                      self.active === pair, self.resize === engine else { return }
                self.operation = nil
                guard let result else {
                    let display = self.screenID(pair.left.screen)
                    if self.pairs[display] === pair { self.pairs.removeValue(forKey: display) }
                    for (entry, actual) in [(pair.left, observed.left), (pair.right, observed.right)] {
                        self.entries.removeValue(forKey: entry.id)
                        Self.reconcileAfterFailure(id: entry.id, original: entry.frame, observed: actual,
                                                   history: AppDelegate.windowHistory)
                    }
                    self.interrupt()
                    return
                }
                engine.accept(left: result.left, right: result.right)
                pair.left.frame = result.left
                pair.right.frame = result.right
                pair.observedAt = ProcessInfo.processInfo.systemUptime
                pair.settleUntil = pair.observedAt + 0.5
                for entry in [pair.left, pair.right] {
                    self.entries[entry.id] = entry
                    if !result.rolledBack && (result.left != left || result.right != right) {
                        AppDelegate.windowHistory.recordAction(windowId: entry.id, resultingRect: entry.frame,
                                                              action: .specified, subAction: nil)
                    }
                }
                if fence.hasPendingPlans(overlapping: targets) {
                    self.pairs.removeValue(forKey: self.screenID(pair.left.screen))
                    self.finishMovement()
                    return
                }
                self.overlay.show(in: engine.geometry.outer.screenFlipped, divider: engine.divider,
                                  gap: engine.geometry.gap, axis: pair.axis, below: self.panel)
                DiagnosticTrace.event(result.rolledBack ? "divider-placement-rolled-back" : "divider-placement-completed")
                self.reveal(pair: pair, minimumSizeReached: result.minimumSizeReached)
            })
        }
        fence.whenReady(lease) {
            guard lease.isCurrent else { return }
            WindowAnimator.shared.drainWrites(for: [pair.left.element, pair.right.element], completion: placeWhenReady)
        }
    }

    static func reconcileAfterFailure(id: CGWindowID, original: CGRect, observed: CGRect?, history: WindowHistory) {
        guard let previous = history.lastRectangleActions[id],
              WindowGeometry.matches(previous.rect, original, tolerance: 1) else { return }
        // An independently verified return to the original needs no history update.
        // A missing or partially restored member cannot represent its previous snap.
        if observed.map({ WindowGeometry.matches($0, original, tolerance: 1) }) != true {
            history.lastRectangleActions.removeValue(forKey: id)
        }
    }

    private func reveal(pair: Pair, minimumSizeReached: Bool) {
        DiagnosticTrace.event("divider-reveal")
        overlay.fadeOut { [weak self] in
            guard let self, self.active === pair else { return }
            self.finishMovement()
            if minimumSizeReached, Defaults.showMinimumWindowSizeWarning.userEnabled {
                if self.sizeWarning == nil { self.sizeWarning = WindowSizeWarning() }
                self.sizeWarning?.show(on: pair.left.screen)
            }
            guard self.pairs[self.screenID(pair.left.screen)] === pair else { return }
            self.shown = pair
            if pair.hoverFrame.contains(NSEvent.mouseLocation.screenFlipped) { self.showHandle(pair) }
        }
    }

    private func reset() {
        guard begin(resetting: true), let engine = resize else { return }
        transition(to: engine.geometry.axis.rect(engine.geometry.outer).midX)
    }

    private func endDrag() {
        guard dragging else { return }
        if let x = resize?.takePreview() { transition(to: x) }
        else { finishMovement() }
    }

    private func showHandle(_ pair: Pair) {
        if Defaults.windowDividerEnhanced.enabled { _ = WindowCapturePermission.previewsAllowed }
        panel.show(at: pair.center.screenFlipped, axis: pair.axis)
    }

    private func finishMovement() {
        snapshotRequest = nil
        snapshotTask?.cancel(); snapshotTask = nil
        snapshot.clear()
        let wasPlacing = operation != nil
        if let operation {
            self.operation = nil
            WindowWriteFence.shared.finish(operation.lease)
        }
        overlay.dismiss()
        dragging = false
        if let pair = active, wasPlacing {
            // A cancelled in-flight write may still finish. Rediscover a pair
            // from a subsequent accepted snap rather than retaining stale frames.
            let display = screenID(pair.left.screen)
            if pairs[display] === pair { pairs.removeValue(forKey: display) }
        }
        active = nil
        resize = nil
    }

    enum Interruption { case ignore, rollback, cancel }

    static func interruption(_ event: NSEvent, placingMembers: Set<CGWindowID>?) -> Interruption {
        if event.type == .keyDown {
            guard event.keyCode == 53 else { return .ignore }
            return placingMembers == nil ? .cancel : .rollback
        }
        guard let members = placingMembers else { return .cancel }
        // The visual window can be our click-through overlay. Use the actual
        // event recipient; unknown targets conservatively transfer ownership.
        let raw = event.cgEvent?.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) ?? 0
        guard raw > 0, let id = CGWindowID(exactly: raw) else { return .cancel }
        return members.contains(id) ? .cancel : .ignore
    }

    static func retainedWindowIDs(recorded: Set<CGWindowID>, existing: [WindowInfo], recording: CGWindowID) -> Set<CGWindowID> {
        let live = Set(existing.map(\.id))
        // A missing just-recorded window signals an incomplete enumeration.
        guard live.contains(recording) else { return recorded }
        return recorded.intersection(live)
    }

    func handleInterruption(_ event: NSEvent) {
        let members = operation == nil ? nil : active.map { Set([$0.left.id, $0.right.id]) }
        switch Self.interruption(event, placingMembers: members) {
        case .ignore: return
        case .rollback: operation?.requestRollback()
        case .cancel: interrupt()
        }
    }

    /// Called before another Rectangle command or a manual grab takes ownership.
    func interrupt(animated: Bool = true) {
        guard monitoring else { return }
        observationGeneration += 1
        resize?.cancelPreview()
        finishMovement()
        panel.hide(animated: animated); shown = nil
    }

    private func clear() {
        recordGeneration += 1
        pendingRecords.removeAll()
        recordRequests.removeAll()
        interrupt(animated: false)
        entries.removeAll(); pairs.removeAll()
        hoverTimer?.invalidate(); hoverTimer = nil
    }
}
