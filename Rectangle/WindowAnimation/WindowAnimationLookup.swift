import Cocoa

enum WindowAccessibilityLookup {
    enum Result {
        case found(AXUIElement)
        case unavailable
        case timedOut
        case cancelled
    }

    static func resolve(pid: pid_t, id: CGWindowID, launch: TimeInterval,
                        preferred: AXUIElement?, isCurrent: @escaping () -> Bool) -> AXUIElement? {
        if case .found(let element) = resolveResult(pid: pid, id: id, launch: launch,
            preferred: preferred, isCurrent: isCurrent) { return element }
        return nil
    }

    static func resolveResult(pid: pid_t, id: CGWindowID, launch: TimeInterval,
                              preferred: AXUIElement?, isCurrent: @escaping () -> Bool) -> Result {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        func valid() -> Bool { isCurrent() && WindowProcessIdentity.launchTime(for: pid) == launch }
        while valid(), ProcessInfo.processInfo.systemUptime < deadline {
            let reader = AccessibilityReadBatch(budget: deadline - ProcessInfo.processInfo.systemUptime, isCurrent: valid)
            // Activation can stall AXWindows even while the selected window responds.
            if let preferred {
                var owner: pid_t = 0
                if AXUIElementGetPid(preferred, &owner) == .success, owner == pid,
                   reader.windowID(preferred) == id, valid() { return .found(preferred) }
            }
            if reader.available,
               let windows = reader.value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement],
               let window = windows.first(where: { reader.windowID($0) == id }),
               reader.available, valid() { return .found(window) }
            guard valid() else { return .cancelled }
            guard reader.timedOut else { return reader.available ? .unavailable : .timedOut }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { Thread.sleep(forTimeInterval: min(0.02, remaining)) }
        }
        return valid() ? .timedOut : .cancelled
    }
}

import Cocoa

/// All attribute reads share one deadline. Stop on timeout; skip unsupported
/// optional attributes without extending the deadline.
final class AccessibilityReadBatch {
    private let deadline: TimeInterval
    private var failed = false
    var timedOut: Bool { failed }
    private let isCurrent: () -> Bool
    init(budget: TimeInterval, isCurrent: @escaping () -> Bool = { true }) {
        deadline = ProcessInfo.processInfo.systemUptime + budget
        self.isCurrent = isCurrent
    }
    var available: Bool { isCurrent() && !failed && ProcessInfo.processInfo.systemUptime < deadline }
    private func prepare(_ element: AXUIElement) -> Bool {
        guard available else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(0.05, max(0.001, deadline - ProcessInfo.processInfo.systemUptime))))
        return true
    }
    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard prepare(element) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        if status == .cannotComplete { failed = true }
        return status == .success ? result : nil
    }
    func windowID(_ element: AXUIElement) -> CGWindowID? {
        guard prepare(element) else { return nil }
        var id: CGWindowID = 0
        let status = _AXUIElementGetWindow(element, &id)
        if status == .cannotComplete { failed = true }
        return status == .success && id != 0 ? id : nil
    }
    func wrapped<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> T? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(value as! AXValue, type, pointer) ? pointer.pointee : nil
    }
    func settable(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard prepare(element) else { return nil }
        var result = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &result)
        if status == .cannotComplete { failed = true }
        return status == .success ? result.boolValue : nil
    }
    func observe(_ observer: AXObserver, _ element: AXUIElement, _ notification: String,
                 context: UnsafeMutableRawPointer) {
        guard prepare(element) else { return }
        if AXObserverAddNotification(observer, element, notification as CFString, context) == .cannotComplete {
            failed = true
        }
    }
}
