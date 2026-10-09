import Cocoa
import QuartzCore

final class WindowAnimationRequest {
    private let lock = NSLock()
    private var terminated = false
    private var cancellation: (() -> Void)?
    private var changed = false
    private var resized = false
    func geometryChanged(resized: Bool = false) { lock.lock(); changed = true; self.resized = self.resized || resized; lock.unlock() }
    func consumeGeometryChange() -> Bool { lock.lock(); defer { lock.unlock() }; let result = changed; changed = false; return result }
    func consumeResizeChange() -> Bool { lock.lock(); defer { lock.unlock() }; let result = resized; resized = false; return result }
    init(cancellation: (() -> Void)? = nil) { self.cancellation = cancellation }
    // Terminal callbacks run on main, separately from placement completion.
    func cancel() {
        lock.lock()
        guard !terminated else { lock.unlock(); return }
        terminated = true
        let callback = cancellation
        cancellation = nil
        lock.unlock()
        callback?()
    }
    func complete() {
        lock.lock()
        terminated = true
        cancellation = nil
        lock.unlock()
    }
    var isCurrent: Bool { lock.lock(); defer { lock.unlock() }; return !terminated }
}

/// Notifications only schedule readback; they do not prove a frame was displayed.
final class WindowAnimationObservation {
    private var observer: AXObserver?
    private let request: WindowAnimationRequest
    init(pid: pid_t, element: AXUIElement, request: WindowAnimationRequest) {
        self.request = request
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else { return }
            Unmanaged<WindowAnimationRequest>.fromOpaque(context).takeUnretainedValue()
                .geometryChanged(resized: notification as String == kAXResizedNotification)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let context = Unmanaged.passUnretained(request).toOpaque()
        for notification in [kAXMovedNotification, kAXResizedNotification] {
            _ = AXObserverAddNotification(observer, element, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}

enum WindowProcessIdentity {
    /// Launch Services may omit launchDate for apps started by an executable.
    /// Kernel start time still distinguishes a reused PID without an AX query.
    static func launchTime(for pid: pid_t) -> TimeInterval? {
        var info = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size {
            return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
                .timeIntervalSinceReferenceDate
        }
        return NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSinceReferenceDate
    }
}
