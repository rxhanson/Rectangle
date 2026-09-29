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
    private let lookupQueue = DispatchQueue(label: "com.rectangle.trackpad.window-lookup", qos: .userInteractive)
    private let cursorLocation: @Sendable () -> CGPoint?
    private let findWindow: @Sendable (CGPoint) -> Target?
    private var generation: UInt64 = 0
    private var inSession = false
    private var target: Target?
    private var lookupDone = DispatchGroup()

    convenience init() {
        self.init(
            cursorLocation: { CGEvent(source: nil)?.location },
            findWindow: { Self.window(at: $0) }
        )
    }

    init(
        cursorLocation: @escaping @Sendable () -> CGPoint?,
        findWindow: @escaping @Sendable (CGPoint) -> Target?
    ) {
        self.cursorLocation = cursorLocation
        self.findWindow = findWindow
    }
    func observeFrame(contactCount: Int) {
        lock.lock()
        if contactCount == 0 {
            generation &+= 1
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
        let session = generation
        let cursor = cursorLocation()
        let group = DispatchGroup()
        group.enter()
        lookupDone = group
        lock.unlock()

        lookupQueue.async { [weak self] in
            guard let self else {
                group.leave()
                return
            }
            let found = cursor.flatMap { self.findWindow($0) }
            self.lock.lock()
            if self.generation == session, self.inSession {
                self.target = found
            }
            self.lock.unlock()
            group.leave()
        }
    }

    func preparedWindow() -> Target? {
        lock.lock()
        let group = lookupDone
        let session = generation
        let active = inSession
        lock.unlock()
        guard active else { return nil }
        guard group.wait(timeout: .now() + .milliseconds(40)) == .success else { return nil }

        lock.lock()
        let selected = generation == session ? target : nil
        lock.unlock()
        return selected
    }

    func reset() {
        lock.lock()
        generation &+= 1
        inSession = false
        target = nil
        lock.unlock()
    }

    private static func window(at point: CGPoint) -> Target? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.10)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }

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
        AXUIElementSetMessagingTimeout(window, 0.10)
        return Target(window: window, pid: pid)
    }

}
