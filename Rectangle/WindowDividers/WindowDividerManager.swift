import Cocoa

/// Resizes one left/right or top/bottom pair per display independently of Layout Helper.
final class WindowDividerManager {
    static let shared = WindowDividerManager()

    private struct Entry {
        let id: CGWindowID
        let element: AccessibilityElement
        let app: NSRunningApplication
        let screen: NSScreen
        var frame: CGRect
    }
    private final class Pair {
        var left: Entry
        var right: Entry
        let screenFrame: CGRect
        let axis: WindowSplitAxis
        var settleUntil: TimeInterval = 0
        var observedAt: TimeInterval = 0
        var prepared: WindowDividerPreparedPair?
        var minimumLeft: CGSize?
        var minimumRight: CGSize?
        func discardDisprovedMinimums() {
            if WindowDividerGeometry.rememberedExtent(minimumLeft, current: left.frame.size, axis: axis) == nil {
                minimumLeft = nil
            }
            if WindowDividerGeometry.rememberedExtent(minimumRight, current: right.frame.size, axis: axis) == nil {
                minimumRight = nil
            }
        }
        var divider: CGFloat { (axis.rect(left.frame).maxX + axis.rect(right.frame).minX) / 2 }
        var center: CGPoint { point(at: divider) }
        func point(at value: CGFloat) -> CGPoint { axis.point(value, cross: axis.rect(left.frame).midY) }
        var hoverFrame: CGRect {
            axis.rect(CGRect(x: divider - 24, y: axis.rect(left.frame).midY - 54, width: 48, height: 108))
        }
        init(left: Entry, right: Entry, screenFrame: CGRect, axis: WindowSplitAxis) {
            self.left = left; self.right = right; self.screenFrame = screenFrame; self.axis = axis
        }
    }

    private var entries: [CGWindowID: Entry] = [:]
    private var pairs: [UInt32: Pair] = [:]
    private var shown: Pair?
    private var active: Pair?
    private var resize: WindowDividerResize?
    private var placementCancellation: WindowPlacementCoordinator.Cancellation?
    private var pendingPlacements = 0
    private var placementCompleted = false
    var hasPendingPlacement: Bool { pendingPlacements > 0 }
    private var observationRunning = false
    private var observationGeneration = 0
    private var recordGeneration = 0
    private var recordRunning = false
    private var pendingRecord: (() -> Void)?
    private var hoverTimer: Timer?
    private var pointerOffset: CGFloat = 0
    private var snapshotTask: Task<Void, Never>?
    private var snapshotRequest: UUID?
    private var rememberedMinima: (left: CGFloat?, right: CGFloat?)?
    private let snapshot = WindowDividerSnapshot()
    private var dragging = false
    private let panel = WindowDividerPanel()
    private let overlay = WindowDividerOverlay()
    private var observations: [NSObjectProtocol] = []
    private var mouseMonitor: Any?

    private init() {
        observations.append(NotificationCenter.default.addObserver(forName: .windowActionWillExecute,
            object: nil, queue: .main) { [weak self] note in
                if note.object == nil { self?.interrupt() }
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
            if event.type != .keyDown || event.keyCode == 53 { self?.interrupt() }
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didChangeScreenParametersNotification, .configImported, NSApplication.willTerminateNotification] {
            observations.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.clear() })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.clear() })
        }
        observations.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.interrupt(animated: false) })
    }

    private func screenID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func containsPointerEvent(_ event: NSEvent) -> Bool {
        // AX validation can lag behind the next pointer update. Classify the
        // original event, otherwise a quick drag can cancel its own mouse-down.
        return dragging || panel.containsPointerEvent(event)
    }

    /// Called only for placements known to Rectangle, including compatible
    /// neighbors retained by a completed two-cell Layout Helper sequence.
    func record(_ window: AccessibilityElement, id: CGWindowID?, frame: CGRect, screen: NSScreen,
                eligibilityConfirmed: Bool = false) {
        guard Defaults.windowDivider.enabled, let id, let pid = window.pid,
              let app = NSRunningApplication(processIdentifier: pid), !app.isHidden, !app.isTerminated else {
            WindowAnimationDiagnostics.event("divider-record-ineligible", fields: ["windowID": id ?? 0])
            return
        }
        let area = screen.adjustedVisibleFrame().screenFlipped
        let gap = max(0, CGFloat(Defaults.gapSize.value))
        let bounds = GapCalculation.applyGaps(screen.adjustedVisibleFrame(), gapSize: Float(gap),
            skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
        let axis: WindowSplitAxis
        if abs(frame.minY - bounds.minY) <= 3, abs(frame.maxY - bounds.maxY) <= 3,
           frame.width < bounds.width - 10 { axis = .horizontal }
        else if abs(frame.minX - bounds.minX) <= 3, abs(frame.maxX - bounds.maxX) <= 3,
                frame.height < bounds.height - 10 { axis = .vertical }
        else {
            WindowAnimationDiagnostics.event("divider-record-shape", fields: ["windowID": id,
                "frame": [frame.minX, frame.minY, frame.width, frame.height],
                "bounds": [bounds.minX, bounds.minY, bounds.width, bounds.height]])
            return
        }
        let normalized = axis.rect(frame), extent = axis.rect(bounds)
        guard abs(normalized.minX - extent.minX) <= 3 || abs(normalized.maxX - extent.maxX) <= 3 else { return }
        // Start asynchronous identity validation before a divider drag needs a restored hint.
        let entry = Entry(id: id, element: window, app: app, screen: screen, frame: frame)
        entries[id] = entry
        entries = entries.filter { !$0.value.app.isTerminated }
        if entries.count > 32, let oldest = entries.keys.first(where: { $0 != id }) { entries.removeValue(forKey: oldest) }
        // Inventory and optional AX eligibility are copied on a worker. A newer
        // placement replaces this entry before an old observation can pair it.
        let candidates = Array(entries.values)
        recordGeneration += 1
        let generation = recordGeneration
        pendingRecord = { [weak self] in
            guard let self else { return }
            self.recordRunning = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let eligible = eligibilityConfirmed || WindowDividerPreparedPair.Input(id: id, pid: pid)
                    .flatMap { WindowDividerPreparedPair.read($0) } != nil
                let visibleOrder = eligible ? WindowUtil.getWindowList(forceRefresh: true, cacheResult: false) : []
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.recordRunning = false
                    self.pumpRecord()
                    guard eligible, self.recordGeneration == generation, Defaults.windowDivider.enabled,
                          let current = self.entries[id], current.frame == frame,
                          current.element == window else { return }
                    self.recordPair(entry, candidates: candidates, visibleOrder: visibleOrder,
                        screen: screen, axis: axis, normalized: normalized, extent: extent, area: area, gap: gap)
                }
            }
        }
        pumpRecord()
    }

    private func pumpRecord() {
        guard !recordRunning, let work = pendingRecord else { return }
        pendingRecord = nil
        work()
    }

    private func recordPair(_ entry: Entry, candidates: [Entry], visibleOrder: [WindowInfo],
                            screen: NSScreen, axis: WindowSplitAxis, normalized: CGRect,
                            extent: CGRect, area: CGRect, gap: CGFloat) {
        let id = entry.id
        let orderedEntries = candidates.sorted { a, b in
            (visibleOrder.firstIndex(where: { $0.id == a.id }) ?? Int.max)
                < (visibleOrder.firstIndex(where: { $0.id == b.id }) ?? Int.max)
        }
        for other in orderedEntries where other.id != id && screenID(other.screen) == screenID(screen) {
            guard !other.app.isTerminated, visibleOrder.contains(where: {
                $0.id == other.id && $0.pid == other.app.processIdentifier
                    && LayoutHelperLayout.matches($0.frame, other.frame)
            }) else { continue }
            let left = normalized.minX < axis.rect(other.frame).minX ? entry : other
            let right = left.id == id ? other : entry
            guard abs(axis.rect(left.frame).minX - extent.minX) <= 3,
                  abs(axis.rect(right.frame).maxX - extent.maxX) <= 3,
                  let geometry = WindowDividerGeometry(left: left.frame, right: right.frame, axis: axis),
                  abs(geometry.gap - gap) <= 3 else { continue }
            let key = screenID(screen)
            if let current = pairs[key], current.left.id == left.id, current.right.id == right.id,
               LayoutHelperLayout.matches(current.left.frame, left.frame), LayoutHelperLayout.matches(current.right.frame, right.frame) { return }
            if active != nil { interrupt() }
            pairs[key] = Pair(left: left, right: right, screenFrame: area, axis: axis)
            WindowAnimationDiagnostics.event("divider-pair-recorded", fields: ["left": left.id, "right": right.id, "display": key])
            startHoverTimer()
            return
        }
        WindowAnimationDiagnostics.event("divider-record-unpaired", fields: ["windowID": id, "known": Array(entries.keys)])
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
        guard let pair = active ?? pairs.values.first(where: { $0.hoverFrame.contains(point) }),
              !LayoutHelperManager.shared.isPresenting else { panel.hide(); shown = nil; return }
        // Release owns all AX I/O until placement finishes. Pointer tracking
        // uses the proposed geometry and never waits for an app or WindowServer.
        guard active == nil else { return }
        guard !observationRunning,
              let left = WindowDividerPreparedPair.Input(id: pair.left.id, pid: pair.left.app.processIdentifier),
              let right = WindowDividerPreparedPair.Input(id: pair.right.id, pid: pair.right.app.processIdentifier) else { return }
        observationRunning = true
        let generation = observationGeneration
        let prepared = pair.prepared
        let ownedPIDs: Set<pid_t> = [pair.left.app.processIdentifier, pair.right.app.processIdentifier, getpid()]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let infos = WindowUtil.getWindowList(forceRefresh: true, cacheResult: false)
            let preparation = prepared ?? WindowDividerPreparedPair(left: left, right: right)
            let passive = WindowDividerPreparedPair.passiveCaptureOverlayIDs(in: infos, at: point, ownedPIDs: ownedPIDs)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.observationRunning = false
                guard self.observationGeneration == generation, self.active == nil,
                      self.pairs[self.screenID(pair.left.screen)] === pair,
                      pair.hoverFrame.contains(NSEvent.mouseLocation.screenFlipped),
                      !LayoutHelperManager.shared.isPresenting else { return }
                guard let preparation, self.visible(pair, in: infos, ignoring: passive),
                      let l = infos.first(where: { $0.id == pair.left.id })?.frame,
                      let r = infos.first(where: { $0.id == pair.right.id })?.frame,
                      let original = WindowDividerGeometry(left: pair.left.frame, right: pair.right.frame, axis: pair.axis),
                      original.containsPair(left: l, right: r),
                      LayoutHelperLayout.matches(pair.left.screen.adjustedVisibleFrame().screenFlipped, pair.screenFrame) else {
                    if ProcessInfo.processInfo.systemUptime < pair.settleUntil { return }
                    self.pairs.removeValue(forKey: self.screenID(pair.left.screen))
                    self.interrupt(); return
                }
                pair.left.frame = l; pair.right.frame = r
                pair.discardDisprovedMinimums()
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

    private func begin(pointerX: CGFloat? = nil) -> Bool {
        finishMovement()
        guard let pair = shown, let prepared = pair.prepared,
              ProcessInfo.processInfo.systemUptime - pair.observedAt < 0.3 else { panel.hide(); poll(); return false }
        LayoutHelperManager.shared.cancel()
        WindowAnimator.shared.finish()
        let l = pair.left.element, r = pair.right.element
        let leftHint: CGSize? = nil, rightHint: CGSize? = nil
        guard WindowAnimator.shared.destination(for: l) == nil,
              WindowAnimator.shared.destination(for: r) == nil,
              let engine = WindowDividerResize(left: pair.left.frame, right: pair.right.frame, axis: pair.axis,
                  minimumLeft: WindowDividerGeometry.minimumExtent(reported: prepared.left.minimum,
                      remembered: leftHint, acknowledged: pair.minimumLeft, current: pair.left.frame.size, axis: pair.axis),
                  minimumRight: WindowDividerGeometry.minimumExtent(reported: prepared.right.minimum,
                      remembered: rightHint, acknowledged: pair.minimumRight, current: pair.right.frame.size, axis: pair.axis),
                  write: { _, _, _, _ in false }, read: { _ in .null }) else { return false }
        rememberedMinima = ([leftHint, pair.minimumLeft].compactMap {
            WindowDividerGeometry.rememberedExtent($0, current: pair.left.frame.size, axis: pair.axis)
        }.max(), [rightHint, pair.minimumRight].compactMap {
            WindowDividerGeometry.rememberedExtent($0, current: pair.right.frame.size, axis: pair.axis)
        }.max())
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
        WindowAnimationDiagnostics.event("divider-release")
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
        WindowAnimationDiagnostics.event("divider-surface-ready", fields: ["frozen": overlay.guide.frozenImage != nil])
        place(engine: engine, pair: pair, divider: x)
    }

    private func captureBackground(engine: WindowDividerResize, pair: Pair) {
        let request = UUID()
        snapshotRequest = request
        snapshot.prepare()
        WindowAnimationDiagnostics.event("divider-snapshot-start")
        snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await self.snapshot.capture(frame: self.overlay.frame.screenFlipped,
                displayID: self.screenID(pair.left.screen), scale: pair.left.screen.backingScaleFactor)
            guard !Task.isCancelled, self.snapshotRequest == request, self.active === pair,
                  self.resize === engine, self.dragging else { return }
            self.snapshotRequest = nil
            self.snapshotTask = nil
            self.snapshot.clear()
            WindowAnimationDiagnostics.event("divider-snapshot-result", fields: ["captured": image != nil])
            if let image, WindowDividerSnapshot.enabled { self.overlay.freeze(image) }
        }
    }

    private func place(engine: WindowDividerResize, pair: Pair, divider x: CGFloat) {
        guard let prepared = pair.prepared else { interrupt(); return }
        WindowAnimationDiagnostics.event("divider-placement-start")
        let cancellation = WindowPlacementCoordinator.Cancellation()
        placementCancellation = cancellation
        pendingPlacements += 1
        let left = engine.left, right = engine.right
        let minimumLeft = engine.minimumLeft, minimumRight = engine.minimumRight
        let remembered = rememberedMinima
        let ignoring = Set([panel, overlay].compactMap { CGWindowID(exactly: $0.windowNumber) })
        let hoverFrame = pair.hoverFrame
        let policy = Defaults.enhancedUI.value
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        WindowAnimator.shared.performPlacementWork { [weak self] in
            let result = prepared.place(left: left, right: right, axis: pair.axis, divider: x,
                minimumLeft: minimumLeft, minimumRight: minimumRight,
                remembered: remembered, ignoring: ignoring, hoverFrame: hoverFrame,
                policy: policy, assistive: assistive, cancellation: cancellation)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingPlacements -= 1
                guard self.placementCancellation === cancellation, !cancellation.isCancelled,
                      self.active === pair, self.resize === engine else { return }
                self.placementCancellation = nil
                guard let result else {
                    self.pairs.removeValue(forKey: self.screenID(pair.left.screen))
                    self.interrupt(); return
                }
                engine.accept(left: result.left, right: result.right)
                // Carry a verified clamp into the next drag without waiting for
                // optional persistent learning or asynchronous identity reads.
                if let minimum = result.minimumLeft {
                    pair.minimumLeft = pair.axis.size(CGSize(width: minimum, height: 0))
                }
                if let minimum = result.minimumRight {
                    pair.minimumRight = pair.axis.size(CGSize(width: minimum, height: 0))
                }
                pair.left.frame = result.left; pair.right.frame = result.right
                pair.observedAt = ProcessInfo.processInfo.systemUptime
                pair.settleUntil = pair.observedAt + 0.5
                self.placementCompleted = true
                self.overlay.show(in: engine.geometry.outer.screenFlipped, divider: engine.divider,
                    gap: engine.geometry.gap, axis: pair.axis, below: self.panel)
                WindowAnimationDiagnostics.event("divider-placement-completed")
                self.reveal(pair: pair, minimumSizeReached: result.minimumSizeReached)
            }
        }
    }

    private func reveal(pair: Pair, minimumSizeReached: Bool) {
        WindowAnimationDiagnostics.event("divider-reveal")
        overlay.fadeOut { [weak self] in
            guard let self, self.active === pair else { return }
            self.finishMovement()
            if minimumSizeReached { WindowSizeWarning.shared.show(on: pair.left.screen) }
            self.shown = pair
            if pair.hoverFrame.contains(NSEvent.mouseLocation.screenFlipped) { self.showHandle(pair) }
        }
    }

    private func reset() {
        guard begin(), let engine = resize else { return }
        transition(to: engine.geometry.axis.rect(engine.geometry.outer).midX)
    }

    private func endDrag() {
        guard dragging else { return }
        if let x = resize?.takePreview() { transition(to: x) }
        else { finishMovement() }
    }

    private func showHandle(_ pair: Pair) {
        panel.show(at: pair.center.screenFlipped, axis: pair.axis)
    }

    private func finishMovement() {
        snapshotRequest = nil
        snapshotTask?.cancel(); snapshotTask = nil
        snapshot.clear()
        let wasPlacing = placementCancellation != nil
        placementCancellation?.cancel(); placementCancellation = nil
        overlay.dismiss()
        dragging = false
        if let pair = active, wasPlacing {
            // A cancelled in-flight write may still finish. Rediscover a pair
            // from a subsequent accepted snap rather than retaining stale frames.
            pairs.removeValue(forKey: screenID(pair.left.screen))
        }
        if let pair = active, placementCompleted {
            for entry in [pair.left, pair.right] {
                AppDelegate.windowHistory.lastRectangleActions[entry.id] = RectangleAction(action: .specified, subAction: nil, rect: entry.frame, count: 1)
                entries[entry.id] = entry
            }
        }
        active = nil; resize = nil
        placementCompleted = false
        rememberedMinima = nil

    }

    /// Called before another Rectangle command or a manual grab takes ownership.
    func interrupt(animated: Bool = true) {
        observationGeneration += 1
        recordGeneration += 1; pendingRecord = nil
        resize?.cancelPreview()
        finishMovement()
        panel.hide(animated: animated); shown = nil
    }

    func clear() {
        interrupt(animated: false)
        entries.removeAll(); pairs.removeAll()
        hoverTimer?.invalidate(); hoverTimer = nil
    }
}
