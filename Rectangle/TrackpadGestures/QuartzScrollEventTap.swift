import CoreGraphics
import Foundation

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

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
