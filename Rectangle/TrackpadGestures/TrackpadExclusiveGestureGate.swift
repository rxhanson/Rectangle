import Foundation

enum TrackpadScrollStreamPhase: Equatable, Sendable {
    case none
    case active
    case scrollEnded
    case cancelled
    case momentumEnded
}

final class TrackpadExclusiveGestureGate: @unchecked Sendable {
    private enum State {
        case idle
        case exclusive
        case draining(deadline: TimeInterval)
    }

    private let lock = NSLock()
    private let quietInterval: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let beforeSetEnabled: (@Sendable (Bool) -> Void)?
    private var enabled = false
    private var allowedFingerCounts: Set<Int> = [3]
    private var lastContactCount = 0
    private var leakedScrollInSession = false
    private var state: State = .idle

    init(
        quietInterval: TimeInterval = 0.150,
        now: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        beforeSetEnabled: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.quietInterval = quietInterval
        self.now = now
        self.beforeSetEnabled = beforeSetEnabled
    }

    func setEnabled(_ enabled: Bool) {
        beforeSetEnabled?(enabled)
        lock.lock()
        defer { lock.unlock() }
        self.enabled = enabled
        if !enabled {
            state = .idle
        } else if allowedFingerCounts.contains(lastContactCount) && !leakedScrollInSession {
            state = .exclusive
        }
    }

    func setAllowedFingerCounts(_ counts: Set<Int>) {
        lock.lock()
        allowedFingerCounts = counts
        if lastContactCount >= 3 {
            if !counts.contains(lastContactCount) { state = .idle }
            else if enabled && !leakedScrollInSession { state = .exclusive }
        }
        lock.unlock()
    }

    func observeContactCount(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        lastContactCount = count
        if count == 0 { leakedScrollInSession = false }
        guard enabled else {
            state = .idle
            return
        }

        switch state {
        case .idle:
            if allowedFingerCounts.contains(count) && !leakedScrollInSession { state = .exclusive }
        case .exclusive:
            if count == 0 { state = .draining(deadline: now() + quietInterval) }
            else if count >= 3 && !allowedFingerCounts.contains(count) { state = .idle }
        case .draining:
            if allowedFingerCounts.contains(count) && !leakedScrollInSession { state = .exclusive }
        }
    }

    func reset() {
        lock.lock()
        lastContactCount = 0
        leakedScrollInSession = false
        state = .idle
        lock.unlock()
    }

    func shouldSuppressScroll(phase: TrackpadScrollStreamPhase) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return false }

        switch state {
        case .idle:
            if lastContactCount >= 3 { leakedScrollInSession = true }
            return false
        case .exclusive:
            return true
        case .draining(let deadline):
            let current = now()
            guard current <= deadline else {
                state = .idle
                return false
            }
            if phase == .momentumEnded || phase == .cancelled {
                state = .idle
            } else {
                state = .draining(deadline: current + quietInterval)
            }
            return true
        }
    }

    var hasLeakedScrollInSession: Bool {
        lock.lock()
        defer { lock.unlock() }
        return leakedScrollInSession
    }
}
