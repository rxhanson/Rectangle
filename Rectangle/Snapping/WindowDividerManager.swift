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
    private var restoreAccessibility: [() -> Void] = []
    private var hoverTimer: Timer?
    private var pointerOffset: CGFloat = 0
    private var settlement: DispatchWorkItem?
    private var snapshotTask: Task<Void, Never>?
    private var snapshotRequest: UUID?
    private var rememberedMinima: (left: CGFloat?, right: CGFloat?)?
    private let snapshot = WindowDividerSnapshot()
    private var sizeAttempt: (beforeLeft: CGRect, beforeRight: CGRect, requestedLeft: CGRect, requestedRight: CGRect, generation: UUID)?
    private var dragging = false
    private let panel = WindowDividerPanel()
    private let overlay = WindowDividerOverlay()
    private var observations: [NSObjectProtocol] = []
    private var mouseMonitor: Any?

    private init() {
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
              let app = NSRunningApplication(processIdentifier: pid),
              eligibilityConfirmed || (window.isResizable() && window.isSystemDialog != true
                  && window.isMinimized != true && window.isHidden != true) else {
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
        _ = window.rememberedMinimumSize
        let entry = Entry(id: id, element: window, app: app, screen: screen, frame: frame)
        entries[id] = entry
        entries = entries.filter { !$0.value.app.isTerminated }
        if entries.count > 32, let oldest = entries.keys.first(where: { $0 != id }) { entries.removeValue(forKey: oldest) }
        let visibleOrder = WindowUtil.getWindowList(forceRefresh: true)
        let orderedEntries = entries.values.sorted { a, b in
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
        // AX placement and the inventory cache can disagree for a short time.
        // Never invalidate a newly resized pair from a cached pre-resize frame.
        let infos = WindowUtil.getWindowList(forceRefresh: true)
        guard visible(pair, in: infos) else {
            if shown != nil || active != nil { WindowAnimationDiagnostics.event("divider-pair-obscured") }
            interrupt(); return
        }
        if active != nil && !dragging { return }
        if active == nil || dragging {
            guard let left = infos.first(where: { $0.id == pair.left.id }),
                  let right = infos.first(where: { $0.id == pair.right.id }),
                  LayoutHelperLayout.matches(left.frame, pair.left.frame),
                  LayoutHelperLayout.matches(right.frame, pair.right.frame),
                  LayoutHelperLayout.matches(pair.left.screen.adjustedVisibleFrame().screenFlipped, pair.screenFrame) else {
                if !dragging, reconcile(pair) { showHandle(pair); return }
                if !dragging && ProcessInfo.processInfo.systemUptime < pair.settleUntil { return }
                WindowAnimationDiagnostics.event("divider-pair-invalidated", fields: ["left": pair.left.id, "right": pair.right.id])
                pairs.removeValue(forKey: screenID(pair.left.screen)); interrupt(); return
            }
        }
        shown = pair
        let x = dragging ? (resize?.pendingDivider ?? pair.divider) : pair.divider
        panel.show(at: pair.point(at: x).screenFlipped, axis: pair.axis)
    }

    private func visible(_ pair: Pair, in infos: [WindowInfo]) -> Bool {
        guard !pair.left.app.isTerminated, !pair.right.app.isTerminated,
              infos.contains(where: { $0.id == pair.left.id && $0.pid == pair.left.app.processIdentifier }),
              infos.contains(where: { $0.id == pair.right.id && $0.pid == pair.right.app.processIdentifier }) else { return false }
        return WindowDividerGeometry.unobscured(left: pair.left.id, right: pair.right.id,
                                                    in: infos, near: pair.hoverFrame)
    }

    private func begin(pointerX: CGFloat? = nil) -> Bool {
        WindowSizeConstraints.shared.cancelPendingObservations()
        finishMovement()
        guard let pair = shown, visible(pair, in: WindowUtil.getWindowList(forceRefresh: true)),
              LayoutHelperLayout.matches(frame(of: pair.left.element), pair.left.frame),
              LayoutHelperLayout.matches(frame(of: pair.right.element), pair.right.frame) else { panel.hide(); return false }
        LayoutHelperManager.shared.cancel()
        WindowAnimator.shared.finish()
        let l = pair.left.element, r = pair.right.element
        let leftHint = l.rememberedMinimumSize, rightHint = r.rememberedMinimumSize
        guard WindowAnimator.shared.destination(for: l) == nil,
              WindowAnimator.shared.destination(for: r) == nil,
              l.isResizable(), r.isResizable(),
              let engine = WindowDividerResize(left: pair.left.frame, right: pair.right.frame, axis: pair.axis,
                  minimumLeft: WindowDividerGeometry.minimumExtent(reported: l.minimumSize,
                      remembered: leftHint, current: pair.left.frame.size, axis: pair.axis),
                  minimumRight: WindowDividerGeometry.minimumExtent(reported: r.minimumSize,
                      remembered: rightHint, current: pair.right.frame.size, axis: pair.axis),
                  write: { isLeft, frame, positionFirst, resizeOnly in
                      guard WindowAnimator.shared.destination(for: l) == nil,
                            WindowAnimator.shared.destination(for: r) == nil else { return false }
                      return (isLeft ? l : r).setAnimationFrame(frame, resizeOnly: resizeOnly, positionFirst: positionFirst)
                  },
                  read: { [weak self] in self?.frame(of: $0 ? l : r) ?? .null }) else { return false }
        rememberedMinima = (WindowDividerGeometry.rememberedExtent(leftHint, current: pair.left.frame.size, axis: pair.axis),
                            WindowDividerGeometry.rememberedExtent(rightHint, current: pair.right.frame.size, axis: pair.axis))
        active = pair; resize = engine; dragging = true
        panel.holdVisible()
        let captureEnabled = WindowDividerSnapshot.enabled
        overlay.snapshotScreenFrame = captureEnabled ? pair.left.screen.frame : nil
        pointerOffset = (pointerX ?? pair.divider) - pair.divider
        overlay.show(in: engine.geometry.outer.screenFlipped, divider: pair.divider, gap: engine.geometry.gap, axis: pair.axis, below: panel)
        if captureEnabled { captureBackground(engine: engine, pair: pair) }
        return true
    }

    private func frame(of element: AccessibilityElement) -> CGRect {
        let timeout = element.messagingTimeout, cache = element.animationReads
        element.setMessagingTimeout(timeout > 0 ? min(timeout, 0.05) : 0.05)
        element.animationReads = WindowAnimationReadCache()
        defer { element.animationReads = cache; element.setMessagingTimeout(timeout) }
        return element.frame
    }

    private func prepareAccessibility(_ pair: Pair) {
        guard restoreAccessibility.isEmpty else { return }
        restoreAccessibility = [pair.left.element.beginAnimatedAdjustment(), pair.right.element.beginAnimatedAdjustment()]
    }

    private func transition(to x: CGFloat) {
        WindowAnimationDiagnostics.event("divider-release")
        guard let engine = resize, let pair = active,
              let target = engine.geometry.frames(at: x, minimumLeft: engine.minimumLeft, minimumRight: engine.minimumRight) else { interrupt(); return }
        dragging = false
        engine.cancelPreview()
        sizeAttempt = (engine.left, engine.right, target.left, target.right, WindowSizeConstraints.shared.observationGeneration)
        let infos = WindowUtil.getWindowList(forceRefresh: true)
        guard visible(pair, in: infos),
              let left = infos.first(where: { $0.id == pair.left.id })?.frame,
              let right = infos.first(where: { $0.id == pair.right.id })?.frame else { interrupt(); return }
        guard LayoutHelperLayout.matches(left, engine.left), LayoutHelperLayout.matches(right, engine.right) else { interrupt(); return }
        WindowAnimationDiagnostics.event("divider-release-validated")
        snapshotRequest = nil
        snapshotTask?.cancel(); snapshotTask = nil
        snapshot.clear()
        panel.hide(animated: false)
        if LayoutHelperLayout.matches(left, target.left, tolerance: 0.5),
           LayoutHelperLayout.matches(right, target.right, tolerance: 0.5) {
            sizeAttempt = nil
            let reference = engine.geometry.warningReference(at: x,
                rememberedMinimumLeft: rememberedMinima?.left, rememberedMinimumRight: rememberedMinima?.right)
            reveal(pair: pair, minimumSizeReached: abs(engine.divider - reference) > 1)
            return
        }
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
        WindowAnimationDiagnostics.event("divider-placement-start")
        prepareAccessibility(pair)
        guard let placement = WindowDividerPlacement(left: engine.left, right: engine.right,
            axis: pair.axis, divider: x, minimumLeft: engine.minimumLeft, minimumRight: engine.minimumRight,
            rememberedMinimumLeft: rememberedMinima?.left, rememberedMinimumRight: rememberedMinima?.right,
            write: { [weak self] isLeft, frame, attribute in
                guard let self, self.active === pair, self.resize === engine,
                      WindowAnimator.shared.destination(for: pair.left.element) == nil,
                      WindowAnimator.shared.destination(for: pair.right.element) == nil else { return false }
                let element = isLeft ? pair.left.element : pair.right.element
                if attribute == .size { return element.setAnimationFrame(frame, resizeOnly: true) }
                return element.setDividerPosition(frame.origin)
            }, read: { [weak self] in self?.frame(of: $0 ? pair.left.element : pair.right.element) ?? .null },
            acknowledged: { isLeft, expected in
                guard let actual = WindowUtil.getWindowFrame(id: isLeft ? pair.left.id : pair.right.id) else { return false }
                return LayoutHelperLayout.matches(actual, expected, tolerance: 1)
            }) else { interrupt(); return }
        advancePlacement(placement, engine: engine, pair: pair)
    }

    private func advancePlacement(_ placement: WindowDividerPlacement, engine: WindowDividerResize, pair: Pair) {
        guard active === pair, resize === engine else { return }
        switch placement.advance(at: ProcessInfo.processInfo.systemUptime) {
        case .waiting:
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.active === pair, self.resize === engine else { return }
                self.settlement = nil
                self.advancePlacement(placement, engine: engine, pair: pair)
            }
            settlement = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: work)
        case .completed, .rolledBack:
            engine.accept(left: placement.left, right: placement.right)
            if let attempt = sizeAttempt,
               LayoutHelperLayout.matches(placement.left, attempt.beforeLeft),
               LayoutHelperLayout.matches(placement.right, attempt.beforeRight) { sizeAttempt = nil }
            overlay.show(in: engine.geometry.outer.screenFlipped, divider: engine.divider,
                         gap: engine.geometry.gap, axis: pair.axis, below: panel)
            WindowAnimationDiagnostics.event("divider-placement-completed")
            awaitSettlement(engine: engine, pair: pair, minimumSizeReached: placement.minimumSizeReached,
                gate: WindowDividerRevealGate(left: engine.left, right: engine.right,
                    startedAt: ProcessInfo.processInfo.systemUptime, matchedSince: placement.verifiedPairSince))
        case .failed:
            sizeAttempt = nil
            pairs.removeValue(forKey: screenID(pair.left.screen))
            interrupt()
        }
    }

    private func awaitSettlement(engine: WindowDividerResize, pair: Pair, minimumSizeReached: Bool,
                                 gate: WindowDividerRevealGate) {
        guard active === pair, resize === engine else { return }
        var gate = gate
        let left = frame(of: pair.left.element), right = frame(of: pair.right.element)
        switch gate.observe(left: left, right: right,
                            at: ProcessInfo.processInfo.systemUptime) {
        case .waiting:
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.active === pair, self.resize === engine else { return }
                self.settlement = nil
                self.awaitSettlement(engine: engine, pair: pair, minimumSizeReached: minimumSizeReached, gate: gate)
            }
            settlement = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: work)
        case .ready:
            if let attempt = sizeAttempt {
                WindowSizeConstraints.shared.recordSettledResize(pair.left.element, before: attempt.beforeLeft,
                    requested: attempt.requestedLeft, first: engine.left, settled: left, verifiedClamp: true, generation: attempt.generation)
                WindowSizeConstraints.shared.recordSettledResize(pair.right.element, before: attempt.beforeRight,
                    requested: attempt.requestedRight, first: engine.right, settled: right, verifiedClamp: true, generation: attempt.generation)
            }
            pair.left.frame = engine.left; pair.right.frame = engine.right
            pair.settleUntil = ProcessInfo.processInfo.systemUptime + 0.5
            reveal(pair: pair, minimumSizeReached: minimumSizeReached)
        case .timedOut:
            // A stalled app must not leave a permanent mask or a stale pair.
            pairs.removeValue(forKey: screenID(pair.left.screen))
            interrupt()
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

    @discardableResult private func reconcile(_ pair: Pair) -> Bool {
        let left = frame(of: pair.left.element), right = frame(of: pair.right.element)
        guard let original = WindowDividerGeometry(left: pair.left.frame, right: pair.right.frame, axis: pair.axis),
              original.containsPair(left: left, right: right),
              LayoutHelperLayout.matches(pair.left.screen.adjustedVisibleFrame().screenFlipped, pair.screenFrame) else { return false }
        pair.left.frame = left; pair.right.frame = right
        return true
    }

    private func finishMovement() {
        snapshotRequest = nil
        snapshotTask?.cancel(); snapshotTask = nil
        snapshot.clear()
        settlement?.cancel(); settlement = nil
        overlay.dismiss()
        dragging = false
        restoreAccessibility.reversed().forEach { $0() }
        restoreAccessibility.removeAll()
        if let pair = active, reconcile(pair) {
            for entry in [pair.left, pair.right] {
                AppDelegate.windowHistory.lastRectangleActions[entry.id] = RectangleAction(action: .specified, subAction: nil, rect: entry.frame, count: 1)
                entries[entry.id] = entry
            }
        }
        active = nil; resize = nil
        rememberedMinima = nil
        sizeAttempt = nil
    }

    /// Called before another Rectangle command or a manual grab takes ownership.
    func interrupt(animated: Bool = true) {
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
