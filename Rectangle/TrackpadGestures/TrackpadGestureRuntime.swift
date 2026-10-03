import AppKit

// Recognition state is lock-protected; action callbacks are installed before start and delivered on main.
final class TrackpadGestureRuntime: @unchecked Sendable {
    private let source: TrackpadTouchSource
    private let capture: TrackpadExclusiveGestureCapturing
    private let targeter: TrackpadCursorWindowShortcutTargeter
    private let lock = NSLock()
    private var recognizer = TrackpadGestureRecognizer(config: .default)
    private var settings = TrackpadGestureSettings()
    private var systemFingers = Set<Int>()
    private var threeFingerOrigin: TrackpadPoint?
    private var generation: UInt = 0
    private var running = false
    private let epochLock = NSLock()
    private var healthEpoch: UInt = 0
    var onAction: ((Int, TrackpadCursorWindowShortcutTargeter.Target, UInt, UInt) -> Void)?
    var onHealthChange: (() -> Void)?

    var deviceCount: Int { source.deviceCount }
    var healthy: Bool { capture.isHealthy }

    init(source: TrackpadTouchSource = TrackpadMultitouchTouchSource(),
         capture: TrackpadExclusiveGestureCapturing = TrackpadExclusiveGestureCapture(),
         targeter: TrackpadCursorWindowShortcutTargeter = TrackpadCursorWindowShortcutTargeter()) {
        self.source = source
        self.capture = capture
        self.targeter = targeter
        // Scroll events do not identify their trackpad reliably. When devices overlap,
        // allow scrolling and reject window gestures until the session ends.
        source.onDeviceOverlap = { [weak capture] in capture?.contaminateSession() }
        source.onContactCount = { [weak capture] in capture?.observeContactCount($0) }
        source.onFrame = { [weak self] in self?.handle($0) }
        capture.onHealthChange = { [weak self] _ in
            guard let self else { return }
            self.epochLock.lock()
            self.healthEpoch &+= 1
            self.epochLock.unlock()
            DispatchQueue.main.async { [weak self] in self?.onHealthChange?() }
        }
    }

    func start(settings: TrackpadGestureSettings, systemFingers: Set<Int>) {
        stop()
        guard settings.enabled, [3, 4].contains(settings.fingers),
              !systemFingers.contains(settings.fingers) else { return }
        lock.lock()
        generation &+= 1
        self.settings = settings
        self.systemFingers = systemFingers
        recognizer = TrackpadGestureRecognizer(config: TrackpadConfig(effectiveThresholds: settings.sensitivity.thresholds))
        threeFingerOrigin = nil
        running = true
        lock.unlock()
        capture.setAllowedFingerCounts([settings.fingers])
        capture.setEnabled(true)
        capture.setAccessibilityTrusted(AXIsProcessTrusted())
        capture.start()
        source.start()
    }

    func stop() {
        // Invalidate queued actions before waiting for source callbacks to drain.
        lock.lock()
        running = false
        generation &+= 1
        lock.unlock()
        source.stop()
        targeter.reset()
        capture.setEnabled(false)
        capture.stop()
    }

    func recheck() { capture.recheck(accessibilityTrusted: AXIsProcessTrusted()) }

    func accepts(generation: UInt, epoch: UInt) -> Bool {
        lock.lock()
        let active = running && self.generation == generation
        lock.unlock()
        epochLock.lock()
        let sameHealth = healthEpoch == epoch
        epochLock.unlock()
        return active && sameHealth && capture.isHealthy
    }

    private func handle(_ frame: TrackpadTouchFrame) {
        lock.lock()
        guard running else { lock.unlock(); return }
        let configuration = settings
        let event = recognizer.process(frame)
        let action = event.flatMap {
            $0.fingers == configuration.fingers && configuration[$0.direction] != TrackpadGestureAction.none
                ? configuration[$0.direction] : nil
        }
        // Invalidate older work before it reaches the main queue or finishes
        // activating an application, not only once this gesture executes.
        if action != nil { generation &+= 1 }
        let token = generation
        var contaminated = false
        if systemFingers.contains(3), frame.touches.count == 3 {
            let center = centroid(of: frame.touches)
            if let origin = threeFingerOrigin {
                let dx = center.x - origin.x, dy = center.y - origin.y
                contaminated = dx * dx + dy * dy >= 0.02 * 0.02
            } else { threeFingerOrigin = center }
        } else { threeFingerOrigin = nil }
        lock.unlock()
        // Once a three-finger system gesture moves, adding a fourth finger
        // must not turn it into a Rectangle gesture.
        if contaminated { capture.contaminateSession() }
        targeter.observeFrame(contactCount: frame.touches.count)
        guard let action else { return }
        capture.performIfHealthy {
            epochLock.lock()
            let epoch = healthEpoch
            epochLock.unlock()
            targeter.withPreparedWindow { [weak self] target in
                guard let self, self.accepts(generation: token, epoch: epoch) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.accepts(generation: token, epoch: epoch) else { return }
                    self.onAction?(action, target, token, epoch)
                }
            }
        }
    }
}
