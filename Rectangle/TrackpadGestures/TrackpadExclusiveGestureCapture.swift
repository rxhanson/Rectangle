import CoreGraphics
import Foundation

final class TrackpadExclusiveGestureCapture: TrackpadExclusiveGestureCapturing, @unchecked Sendable {
    private typealias HealthNotification = (
        callback: @Sendable (Bool) -> Void,
        value: Bool,
        revision: UInt
    )
    private let operationLock = NSLock()
    // Update contacts before recovering the event tap, so recovery waits
        // for all fingers to lift before starting a new gesture.
    private let contactStateLock = NSLock()
    private let stateLock = NSLock()
    private let notificationLock = NSRecursiveLock()
    private let gate: TrackpadExclusiveGestureGate
    private let driver: any TrackpadScrollEventTapDriving
    private var healthy = false
    private var accessibilityTrusted = false
    private var started = false
    private var requestedEnabled = false
    private var allowedFingerCounts: Set<Int> = [3]
    private var rawContactCount = 0
    // A failed tap opens scrolling but blocks actions until every finger lifts.
    private var sessionContaminated = false
    private var outageActive = true
    private var healthRevision: UInt = 0
    private var healthChangeCallback: (@Sendable (Bool) -> Void)?
    private let afterContactStatePublished: (@Sendable () -> Void)?

    var isHealthy: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return healthy
    }

    var onHealthChange: (@Sendable (Bool) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return healthChangeCallback
        }
        set {
            stateLock.lock()
            healthChangeCallback = newValue
            stateLock.unlock()
        }
    }

    convenience init() {
        self.init(driver: QuartzScrollEventTap())
    }

    init(
        driver: any TrackpadScrollEventTapDriving,
        gate: TrackpadExclusiveGestureGate = .init(),
        afterContactStatePublished: (@Sendable () -> Void)? = nil
    ) {
        self.driver = driver
        self.gate = gate
        self.afterContactStatePublished = afterContactStatePublished
        driver.onDisabled = { [weak self] in
            self?.recoverAfterDisable()
        }
        driver.onUnexpectedStop = { [weak self] in
            self?.driverStoppedUnexpectedly()
        }
    }

    deinit {
        driver.onDisabled = nil
        driver.onUnexpectedStop = nil
        driver.stop()
    }

    func start() {
        operationLock.lock()
        stateLock.lock()
        started = true
        let trusted = accessibilityTrusted
        stateLock.unlock()

        let didStart = driver.start { [gate] phase in
            gate.shouldSuppressScroll(phase: phase)
        }
        let notification = transitionHealth(to: trusted && didStart && driver.isEnabled)
        operationLock.unlock()
        notify(notification)
    }

    func stop() {
        operationLock.lock()
        stateLock.lock()
        started = false
        stateLock.unlock()
        let notification = transitionHealth(to: false)
        resetSessionWhileLocked()
        driver.stop()
        operationLock.unlock()
        notify(notification)
    }

    func recheck(accessibilityTrusted trusted: Bool) {
        operationLock.lock()
        stateLock.lock()
        accessibilityTrusted = trusted
        stateLock.unlock()
        let notification = trusted ? recheckWhileLocked() : transitionHealth(to: false)
        operationLock.unlock()
        notify(notification)
    }

    func setAccessibilityTrusted(_ trusted: Bool) {
        operationLock.lock()
        stateLock.lock()
        accessibilityTrusted = trusted
        let hasStarted = started
        stateLock.unlock()

        let notification: HealthNotification?
        if trusted && hasStarted {
            notification = recheckWhileLocked()
        } else {
            notification = transitionHealth(to: false)
        }
        operationLock.unlock()
        notify(notification)
    }

    func setEnabled(_ enabled: Bool) {
        operationLock.lock()
        contactStateLock.lock()
        stateLock.lock()
        requestedEnabled = enabled
        synchronizeGateWhileLocked()
        stateLock.unlock()
        contactStateLock.unlock()
        operationLock.unlock()
    }

    func setAllowedFingerCounts(_ counts: Set<Int>) {
        operationLock.lock()
        contactStateLock.lock()
        stateLock.lock()
        if rawContactCount >= 3
            && allowedFingerCounts.contains(rawContactCount)
            && !counts.contains(rawContactCount) {
            sessionContaminated = true
        }
        allowedFingerCounts = counts
        synchronizeGateWhileLocked()
        stateLock.unlock()
        contactStateLock.unlock()
        operationLock.unlock()
    }

    func observeContactCount(_ count: Int) {
        contactStateLock.lock()
        if count == 0 {
            sessionContaminated = false
        } else if rawContactCount == 0 && outageActive {
            sessionContaminated = true
        }
        rawContactCount = count
        contactStateLock.unlock()
        afterContactStatePublished?()

        operationLock.lock()
        contactStateLock.lock()
        stateLock.lock()
        synchronizeGateWhileLocked()
        stateLock.unlock()
        contactStateLock.unlock()
        operationLock.unlock()
    }

    func contaminateSession() {
        operationLock.lock()
        contactStateLock.lock()
        stateLock.lock()
        if rawContactCount > 0 { sessionContaminated = true }
        synchronizeGateWhileLocked()
        stateLock.unlock()
        contactStateLock.unlock()
        operationLock.unlock()
    }

    @discardableResult
    func performIfHealthy(_ action: () -> Void) -> Bool {
        operationLock.lock()
        contactStateLock.lock()
        stateLock.lock()
        let approved = healthy && requestedEnabled && !outageActive
            && allowedFingerCounts.contains(rawContactCount)
            && !sessionContaminated && !gate.hasLeakedScrollInSession
        stateLock.unlock()
        contactStateLock.unlock()
        guard approved else {
            operationLock.unlock()
            return false
        }
        action()
        operationLock.unlock()
        return true
    }

    func reset() {
        operationLock.lock()
        resetSessionWhileLocked()
        operationLock.unlock()
    }

    private func recheckWhileLocked() -> HealthNotification? {
        stateLock.lock()
        let canRecover = accessibilityTrusted && started
        stateLock.unlock()
        guard canRecover else {
            return transitionHealth(to: false)
        }

        if driver.reenable() && driver.isEnabled {
            return transitionHealth(to: true)
        }

        let recreated = driver.recreate { [gate] phase in
            gate.shouldSuppressScroll(phase: phase)
        }
        return transitionHealth(to: recreated && driver.isEnabled)
    }

    private func recoverAfterDisable() {
        operationLock.lock()
        var notifications: [HealthNotification] = []
        if let notification = transitionHealth(to: false) {
            notifications.append(notification)
        }

        stateLock.lock()
        let canRecover = accessibilityTrusted && started
        stateLock.unlock()
        if canRecover {
            let enabled = driver.reenable() && driver.isEnabled
            if let notification = transitionHealth(to: enabled) {
                notifications.append(notification)
            }
        }
        operationLock.unlock()

        for notification in notifications {
            notify(notification)
        }
    }

    private func driverStoppedUnexpectedly() {
        operationLock.lock()
        let notification = transitionHealth(to: false)
        operationLock.unlock()
        notify(notification)
    }

    private func transitionHealth(to value: Bool) -> HealthNotification? {
        contactStateLock.lock()
        stateLock.lock()
        if value {
            if outageActive && rawContactCount > 0 {
                sessionContaminated = true
            }
            outageActive = false
        } else {
            outageActive = true
            if rawContactCount > 0 {
                sessionContaminated = true
            }
        }
        synchronizeGateWhileLocked(healthOverride: value)
        guard healthy != value else {
            stateLock.unlock()
            contactStateLock.unlock()
            return nil
        }
        healthy = value
        healthRevision &+= 1
        let revision = healthRevision
        let callback = healthChangeCallback
        stateLock.unlock()
        contactStateLock.unlock()
        return callback.map { ($0, value, revision) }
    }

    private func notify(_ notification: HealthNotification?) {
        guard let notification else { return }
        notificationLock.lock()
        defer { notificationLock.unlock() }
        stateLock.lock()
        let isCurrent = healthRevision == notification.revision && healthy == notification.value
        stateLock.unlock()
        guard isCurrent else { return }
        notification.callback(notification.value)
    }
    private func resetSessionWhileLocked() {
        contactStateLock.lock()
        rawContactCount = 0
        sessionContaminated = false
        gate.reset()
        contactStateLock.unlock()
    }
    private func synchronizeGateWhileLocked(healthOverride: Bool? = nil) {
        let effectiveHealth = healthOverride ?? healthy
        let shouldEnable = requestedEnabled && accessibilityTrusted && started && effectiveHealth
            && !outageActive && !sessionContaminated
        if !shouldEnable { gate.setEnabled(false) }
        gate.setAllowedFingerCounts(allowedFingerCounts)
        gate.observeContactCount(rawContactCount)
        if shouldEnable { gate.setEnabled(true) }
    }
}

protocol TrackpadExclusiveGestureCapturing: AnyObject, Sendable {
    var isHealthy: Bool { get }
    var onHealthChange: (@Sendable (Bool) -> Void)? { get set }
    func start()
    func stop()
    func recheck(accessibilityTrusted: Bool)
    func setAccessibilityTrusted(_ trusted: Bool)
    func setEnabled(_ enabled: Bool)
    func setAllowedFingerCounts(_ counts: Set<Int>)
    func observeContactCount(_ count: Int)
    func contaminateSession()
    @discardableResult
    func performIfHealthy(_ action: () -> Void) -> Bool
    func reset()
}

protocol TrackpadScrollEventTapDriving: AnyObject {
    var isEnabled: Bool { get }
    var onDisabled: (@Sendable () -> Void)? { get set }
    var onUnexpectedStop: (@Sendable () -> Void)? { get set }
    func start(filter: @escaping @Sendable (TrackpadScrollStreamPhase) -> Bool) -> Bool
    func reenable() -> Bool
    func recreate(filter: @escaping @Sendable (TrackpadScrollStreamPhase) -> Bool) -> Bool
    func stop()
}

enum TrackpadScrollStreamPhase: Equatable, Sendable {
    case none
    case active
    case scrollEnded
    case cancelled
    case momentumEnded
}

enum QuartzScrollEventPhaseDecoder {
    private static let scrollEnded = UInt64(CGScrollPhase.ended.rawValue)
    private static let scrollCancelled = UInt64(CGScrollPhase.cancelled.rawValue)
    private static let momentumEnd = Int64(CGMomentumScrollPhase.end.rawValue)

    static func phase(scrollPhase: Int64, momentumPhase: Int64) -> TrackpadScrollStreamPhase {
        if momentumPhase == momentumEnd {
            return .momentumEnded
        }
        if momentumPhase != 0 {
            return .active
        }
        let scrollBits = UInt64(bitPattern: scrollPhase)
        if (scrollBits & scrollCancelled) != 0 {
            return .cancelled
        }
        if (scrollBits & scrollEnded) != 0 {
            return .scrollEnded
        }
        if scrollPhase != 0 {
            return .active
        }
        return .none
    }
}
