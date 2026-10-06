import Cocoa

/// All attribute reads share one deadline. Stop on timeout; skip unsupported
/// optional attributes without extending the deadline.
final class AccessibilityReadBatch {
    private let deadline: TimeInterval
    private var failed = false
    var timedOut: Bool { failed }
    init(budget: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + budget }
    var available: Bool { !failed && ProcessInfo.processInfo.systemUptime < deadline }
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
