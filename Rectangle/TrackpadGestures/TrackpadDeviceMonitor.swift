import CoreFoundation
import Foundation
import IOKit

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
