import CoreFoundation
import Foundation
import IOKit
private let contactState: Int32 = 4
// The C callback has no context pointer. One source is retained for the process lifetime.
private nonisolated(unsafe) var activeSource: TrackpadMultitouchTouchSource?

private func contactCallback(
    device: MTDeviceRef?,
    touches: UnsafeMutablePointer<MTTouch>?,
    numTouches: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard let source = activeSource, let device else { return 0 }

    var contacts: [TrackpadTouch] = []
    contacts.reserveCapacity(Int(max(numTouches, 0)))

    if let touches {
        for i in 0..<Int(numTouches) {
            let t = touches[i]
            guard t.state == contactState else { continue }
            contacts.append(
                TrackpadTouch(
                    identifier: Int(t.identifier),
                    position: TrackpadPoint(x: Double(t.normalized.position.x), y: Double(t.normalized.position.y)),
                    velocity: TrackpadPoint(x: Double(t.normalized.velocity.x), y: Double(t.normalized.velocity.y))
                )
            )
        }
    }

    source.deliver(TrackpadTouchFrame(timestamp: timestamp, touches: contacts), device: UInt(bitPattern: device))
    return 0
}

final class TrackpadMultitouchTouchSource: TrackpadTouchSource, @unchecked Sendable {
    var onDeviceOverlap: (() -> Void)?
    var onContactCount: ((Int) -> Void)?
    var onFrame: ((TrackpadTouchFrame) -> Void)?
    private let lifecycleLock = NSRecursiveLock()
    private let lock = NSLock()
    private var devices: [MTDeviceRef] = []
    private var started = false
    private let deliveryStateLock = NSRecursiveLock()
    private let contactDeliveryLock = NSLock()
    private var deviceSession = TrackpadDeviceSession()
    // Stop closes acceptance, drains synchronous callbacks, then unregisters devices.
    private let synchronousContactCallbacks = DispatchGroup()
    private var deliveryGeneration: UInt = 0
    private var acceptingFrames: Bool
    private let beforeDeviceTeardown: (@Sendable () -> Void)?
    // The array owns the device objects; retain it until callbacks are unregistered.
    private var deviceList: CFArray?
    private let deliveryQueue: DispatchQueue

    var deviceCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return devices.count
    }

    convenience init() {
        self.init(
            deliveryQueue: DispatchQueue(
                label: "com.rectangle.trackpad.frame-delivery",
                qos: .userInteractive
            ),
            acceptingFrames: false
        )
    }

    init(
        deliveryQueue: DispatchQueue,
        acceptingFrames: Bool = true,
        beforeDeviceTeardown: (@Sendable () -> Void)? = nil
    ) {
        self.deliveryQueue = deliveryQueue
        self.acceptingFrames = acceptingFrames
        self.beforeDeviceTeardown = beforeDeviceTeardown
        activeSource = self
    }

    func start() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        deliveryStateLock.lock()
        acceptingFrames = true
        deliveryStateLock.unlock()
        lock.lock()
        startLocked()
        lock.unlock()
    }

    func stop() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        deliveryStateLock.lock()
        acceptingFrames = false
        deviceSession = TrackpadDeviceSession()
        deliveryGeneration &+= 1
        deliveryStateLock.unlock()
        synchronousContactCallbacks.wait()
        beforeDeviceTeardown?()
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    private func startLocked() {
        guard !started, let api = TrackpadMultitouchAPI.shared else { return }
        started = true
        let enumerated = Self.enumerateDevices()
        deviceList = enumerated.list
        devices = enumerated.devices
        for device in devices {
            api.register(device, contactCallback)
            api.start(device, 0)
        }

    }

    private func stopLocked() {
        guard started, let api = TrackpadMultitouchAPI.shared else { return }
        for device in devices {
            api.stop(device)
            api.unregister(device, contactCallback)
        }
        devices = []
        deviceList = nil
        started = false

    }
    func deliver(_ frame: TrackpadTouchFrame, device: UInt = 0) {
        contactDeliveryLock.lock()
        defer { contactDeliveryLock.unlock() }
        deliveryStateLock.lock()
        guard acceptingFrames else { deliveryStateLock.unlock(); return }
        let acceptsDevice = deviceSession.accepts(device: device, contacts: frame.touches.count)
        // Publish contacts before queueing recognition so scrolling cannot leak first.
        let generation = deliveryGeneration
        synchronousContactCallbacks.enter()
        deliveryStateLock.unlock()
        defer { synchronousContactCallbacks.leave() }
        guard acceptsDevice else {
            if !frame.touches.isEmpty { onDeviceOverlap?() }
            return
        }
        onContactCount?(frame.touches.count)
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            self.deliveryStateLock.lock()
            defer { self.deliveryStateLock.unlock() }
            guard self.acceptingFrames, self.deliveryGeneration == generation else { return }
            self.onFrame?(frame)
        }
    }
    private static func enumerateDevices() -> (list: CFArray?, devices: [MTDeviceRef]) {
        guard let list = TrackpadMultitouchAPI.shared?.createList()?.takeRetainedValue() else { return (nil, []) }
        let count = CFArrayGetCount(list)
        let devices = (0..<count).map { i in
            unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: MTDeviceRef.self)
        }
        return (list, devices)
    }
}
protocol TrackpadTouchSource: AnyObject {
    var onDeviceOverlap: (() -> Void)? { get set }
    var onContactCount: ((Int) -> Void)? { get set }
    var onFrame: ((TrackpadTouchFrame) -> Void)? { get set }
    var deviceCount: Int { get }
    func start()
    func stop()
}

// Load only when enabled: unavailable private APIs must not prevent Rectangle launching.
final class TrackpadMultitouchAPI {
    typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    typealias Register = @convention(c) (MTDeviceRef?, MTContactCallbackFunction?) -> Void
    typealias Start = @convention(c) (MTDeviceRef?, Int32) -> Void
    typealias Stop = @convention(c) (MTDeviceRef?) -> Void
    static let shared = TrackpadMultitouchAPI()
    private let handle: UnsafeMutableRawPointer
    let createList: CreateList
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let create = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.createList = unsafeBitCast(create, to: CreateList.self)
        self.register = unsafeBitCast(register, to: Register.self)
        self.unregister = unsafeBitCast(unregister, to: Register.self)
        self.start = unsafeBitCast(start, to: Start.self)
        self.stop = unsafeBitCast(stop, to: Stop.self)
    }
}

// Match the same device family consumed by MultitouchSupport without polling its device list.
final class TrackpadDeviceMonitor {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var pendingChange = false
    private var generation: UInt = 0
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, notification,
                IOServiceMatching("AppleMultitouchDevice"), { context, iterator in
                    guard let context else { return }
                    let monitor = Unmanaged<TrackpadDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                    if TrackpadDeviceMonitor.drain(iterator) { monitor.deviceChanged() }
                }, Unmanaged.passUnretained(self).toOpaque(), &iterator)
            guard result == KERN_SUCCESS else {
                if iterator != 0 { IOObjectRelease(iterator) }
                stop()
                return
            }
            iterators.append(iterator)
            // Draining the initial inventory arms notifications; startup already enumerates devices.
            _ = Self.drain(iterator)
        }
    }

    func stop() {
        generation &+= 1
        pendingChange = false
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private static func drain(_ iterator: io_iterator_t) -> Bool {
        var found = false
        while case let device = IOIteratorNext(iterator), device != 0 {
            found = true
            IOObjectRelease(device)
        }
        return found
    }

    private func deviceChanged() {
        guard !pendingChange else { return }
        pendingChange = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.port != nil, self.generation == token else { return }
            self.pendingChange = false
            self.onChange()
        }
    }

    deinit { stop() }
}

// A second trackpad must lift before it can claim a fresh session after the current owner.
struct TrackpadDeviceSession {
    private var owner: UInt?
    private var waitingForLift = Set<UInt>()

    mutating func accepts(device: UInt, contacts: Int) -> Bool {
        if owner == device {
            if contacts == 0 { owner = nil }
            return true
        }
        if contacts == 0 {
            waitingForLift.remove(device)
            return false
        }
        guard owner == nil, waitingForLift.isEmpty else {
            waitingForLift.insert(device)
            return false
        }
        owner = device
        return true
    }
}
