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
