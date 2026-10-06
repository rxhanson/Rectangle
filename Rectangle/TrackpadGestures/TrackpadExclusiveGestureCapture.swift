import CoreGraphics
import Foundation

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

final class QuartzScrollEventTap: TrackpadScrollEventTapDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var filter: (@Sendable (TrackpadScrollStreamPhase) -> Bool)?
    private var disabledCallback: (@Sendable () -> Void)?
    private var unexpectedStopCallback: (@Sendable () -> Void)?
    private var generation: UInt = 0

    var onDisabled: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return disabledCallback
        }
        set {
            lock.lock()
            disabledCallback = newValue
            lock.unlock()
        }
    }

    var onUnexpectedStop: (@Sendable () -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return unexpectedStopCallback
        }
        set {
            lock.lock()
            unexpectedStopCallback = newValue
            lock.unlock()
        }
    }

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    deinit {
        stop()
    }

    func start(filter: @escaping @Sendable (TrackpadScrollStreamPhase) -> Bool) -> Bool {
        lock.lock()
        if let tap {
            self.filter = filter
            let enabled = CGEvent.tapIsEnabled(tap: tap)
            lock.unlock()
            return enabled
        }
        generation &+= 1
        let startGeneration = generation
        self.filter = filter
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            Thread.current.name = "com.rectangle.trackpad.exclusive-event-tap"
            let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: quartzScrollTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                return
            }

            guard let source = CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault,
                tap,
                0
            ) else {
                ready.signal()
                return
            }
            let runLoop = CFRunLoopGetCurrent()

            self.lock.lock()
            guard self.generation == startGeneration, self.tap == nil else {
                self.lock.unlock()
                ready.signal()
                return
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.tap = tap
            self.source = source
            self.runLoop = runLoop
            self.lock.unlock()

            ready.signal()
            CFRunLoopRun()

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            self.lock.lock()
            let stoppedUnexpectedly = self.generation == startGeneration
            if stoppedUnexpectedly {
                self.tap = nil
                self.source = nil
                self.runLoop = nil
                self.filter = nil
            }
            let callback = stoppedUnexpectedly ? self.unexpectedStopCallback : nil
            self.lock.unlock()
            callback?()
        }
        thread.qualityOfService = QualityOfService.userInteractive
        thread.start()

        guard ready.wait(timeout: .now() + 2) == .success else {
            cancelStart(generation: startGeneration)
            return false
        }
        return isEnabled
    }

    func reenable() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func recreate(filter: @escaping @Sendable (TrackpadScrollStreamPhase) -> Bool) -> Bool {
        stop()
        return start(filter: filter)
    }

    func stop() {
        lock.lock()
        generation &+= 1
        let tap = self.tap
        let source = self.source
        let runLoop = self.runLoop
        self.tap = nil
        self.source = nil
        self.runLoop = nil
        filter = nil
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let callback = disabledCallback
            lock.unlock()
            callback?()
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }

        let phase = QuartzScrollEventPhaseDecoder.phase(
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        )

        lock.lock()
        let currentFilter = filter
        lock.unlock()
        let shouldSuppress = currentFilter?(phase) ?? false
        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    private func cancelStart(generation startGeneration: UInt) {
        lock.lock()
        guard generation == startGeneration else {
            lock.unlock()
            return
        }
        generation &+= 1
        let tap = self.tap
        let source = self.source
        let runLoop = self.runLoop
        self.tap = nil
        self.source = nil
        self.runLoop = nil
        filter = nil
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }
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

private let quartzScrollTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let driver = Unmanaged<QuartzScrollEventTap>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return driver.handle(type: type, event: event)
}
