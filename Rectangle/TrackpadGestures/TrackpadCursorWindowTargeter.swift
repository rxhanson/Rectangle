import AppKit
import ApplicationServices
final class TrackpadCursorWindowShortcutTargeter: @unchecked Sendable {
    final class Target: @unchecked Sendable {
        let window: AXUIElement
        let pid: pid_t

        init(window: AXUIElement, pid: pid_t) {
            self.window = window
            self.pid = pid
        }
    }

    private let lock = NSLock()
    private let lookupQueue: DispatchQueue
    private let cursorLocation: @Sendable () -> CGPoint?
    private let findWindow: @Sendable (CGPoint) -> Target?
    private let now: @Sendable () -> TimeInterval
    private var generation: UInt64 = 0
    private var inSession = false
    private var target: Target?
    private var lookupPending = false
    private var pendingAction: ((Target) -> Void)?
    private var pendingDeadline: TimeInterval = 0

    convenience init() {
        self.init(
            cursorLocation: { CGEvent(source: nil)?.location },
            findWindow: { Self.window(at: $0) }
        )
    }

    init(
        cursorLocation: @escaping @Sendable () -> CGPoint?,
        findWindow: @escaping @Sendable (CGPoint) -> Target?,
        lookupQueue: DispatchQueue = DispatchQueue(label: "com.rectangle.trackpad.window-lookup", qos: .userInteractive),
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.cursorLocation = cursorLocation
        self.findWindow = findWindow
        self.lookupQueue = lookupQueue
        self.now = now
    }
    func observeFrame(contactCount: Int) {
        lock.lock()
        if contactCount == 0 {
            // A recognized swipe may finish its already-started lookup after
            // lift, within the same 40 ms grace period as synchronous lookup.
            if pendingAction == nil { generation &+= 1 }
            inSession = false
            target = nil
            lock.unlock()
            return
        }
        guard contactCount >= 3, !inSession else {
            lock.unlock()
            return
        }
        inSession = true
        generation &+= 1
        pendingAction = nil
        let session = generation
        let cursor = cursorLocation()
        lookupPending = true
        lock.unlock()

        lookupQueue.async { [weak self] in
            guard let self else { return }
            // A slow application must not make later gestures wait for AX
            // lookups belonging to sessions that have already ended.
            self.lock.lock()
            let current = self.generation == session
                && (self.inSession || self.pendingAction != nil && self.now() <= self.pendingDeadline)
            self.lock.unlock()
            guard current else { return }
            let found = cursor.flatMap { self.findWindow($0) }
            self.lock.lock()
            var action: ((Target) -> Void)?
            if self.generation == session {
                self.target = self.inSession ? found : nil
                self.lookupPending = false
                if self.now() <= self.pendingDeadline { action = self.pendingAction }
                self.pendingAction = nil
            }
            self.lock.unlock()
            if let found { action?(found) }
        }
    }

    func withPreparedWindow(_ action: @escaping (Target) -> Void) {
        lock.lock()
        guard inSession else { lock.unlock(); return }
        let selected = target
        if selected == nil, lookupPending {
            pendingAction = action
            pendingDeadline = now() + 0.040
        }
        lock.unlock()
        // Never wait for AX from the frame-delivery callback: its state lock
        // is also needed to publish new contacts and to stop the source.
        if let selected { action(selected) }
    }

    func reset() {
        lock.lock()
        generation &+= 1
        inSession = false
        target = nil
        pendingAction = nil
        lock.unlock()
    }

    private static func window(at point: CGPoint) -> Target? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.10)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.10)

        var rawWindow: CFTypeRef?
        let window: AXUIElement
        if AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &rawWindow) == .success,
           let rawWindow, CFGetTypeID(rawWindow) == AXUIElementGetTypeID() {
            window = unsafeDowncast(rawWindow as AnyObject, to: AXUIElement.self)
        } else {
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role) == .success,
                  (role as? String) == (kAXWindowRole as String) else { return nil }
            window = hit
        }
        AXUIElementSetMessagingTimeout(window, 0.10)
        var role: CFTypeRef?
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
              (role as? String) == (kAXWindowRole as String),
              AXUIElementCopyAttributeValue(
                  window, kAXSubroleAttribute as CFString, &subrole) == .success,
              let subrole = subrole as? String,
              subrole == (kAXStandardWindowSubrole as String)
                  || subrole == (kAXDialogSubrole as String) else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              pid > 0,
              NSRunningApplication(processIdentifier: pid) != nil else { return nil }
        return Target(window: window, pid: pid)
    }

}
