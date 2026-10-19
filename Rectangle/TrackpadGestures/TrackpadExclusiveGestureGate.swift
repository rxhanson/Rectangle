import Foundation

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
    private var committed = false
    private var revision: UInt = 0
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
            committed = false
        }
    }

    func setAllowedFingerCounts(_ counts: Set<Int>) {
        lock.lock()
        if allowedFingerCounts != counts {
            allowedFingerCounts = counts
            if !counts.contains(lastContactCount) {
                state = .idle
                committed = false
            }
        }
        lock.unlock()
    }

    func observeContactCount(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        lastContactCount = count
        defer { if count == 0 { committed = false } }
        if count == 0 { leakedScrollInSession = false }
        guard enabled else {
            state = .idle
            return
        }

        switch state {
        case .idle:
            break
        case .exclusive:
            if count == 0 {
                state = committed ? .draining(deadline: now() + quietInterval) : .idle
            } else if !committed && !allowedFingerCounts.contains(count) { state = .idle }
        case .draining:
            // New contacts start a new session; only contact-free events belong
            // to the previous gesture's inertial tail.
            if count > 0 {
                state = .idle
            }
        }
    }

    func observeMotion(eligible: Bool, committed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, allowedFingerCounts.contains(lastContactCount), !leakedScrollInSession else { return }
        if eligible {
            state = .exclusive
            self.committed = self.committed || committed
        } else if !self.committed {
            state = .idle
        }
    }

    var actionRevision: UInt {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    var isExclusive: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .exclusive = state { return true }
        return false
    }

    func reset() {
        lock.lock()
        lastContactCount = 0
        leakedScrollInSession = false
        committed = false
        revision &+= 1
        state = .idle
        lock.unlock()
    }

    func shouldSuppressScroll(phase: TrackpadScrollStreamPhase) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return false }

        switch state {
        case .idle:
            if lastContactCount > 0 && !leakedScrollInSession {
                leakedScrollInSession = true
                revision &+= 1
            }
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
