/// AXExtension.swift

import Foundation

extension NSAccessibility.Attribute {
    static let enhancedUserInterface = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    static let windowIds = NSAccessibility.Attribute(rawValue: "AXWindowsIDs")
    static let minSize = NSAccessibility.Attribute(rawValue: "AXMinSize")
    static let minimumSize = NSAccessibility.Attribute(rawValue: "AXMinimumSize")
}

extension AXValue {
    /// Safely extracts value of type `T` from an `AXValue` if the underlying `AXValueType` matches `expectedType`.
    func toValue<T>(type expectedType: AXValueType) -> T? {
        // Ensure the AXValue contains the expected type before attempting conversion
        guard AXValueGetType(self) == expectedType else { return nil }
        
        // Allocate raw uninitialized memory suitable for T
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        
        // Only read pointee if AXValueGetValue returns true
        let success = AXValueGetValue(self, expectedType, pointer)
        return success ? pointer.pointee : nil
    }
    
    static func from<T>(value: T, type: AXValueType) -> AXValue? {
        var value = value
        return withUnsafePointer(to: &value) { valuePointer in
            AXValueCreate(type, valuePointer)
        }
    }
}

struct AXLookupResult<Value> {
    let value: Value?
    let error: AXError
    let timedOut: Bool
}

extension AXUIElement {
    static let systemWide = AXUIElementCreateSystemWide()

    static func didMessagingTimeout(error: AXError, elapsed: TimeInterval, timeout: Float) -> Bool {
        timeout > 0 && error == .cannotComplete && elapsed >= TimeInterval(timeout) * 0.8
    }

    func isValueSettable(_ attribute: NSAccessibility.Attribute) -> Bool? {
        var isSettable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(self, attribute.rawValue as CFString, &isSettable)
        guard result == .success else { return nil }
        return isSettable.boolValue
    }
    
    func getValue(_ attribute: NSAccessibility.Attribute) -> AnyObject? {
        getValueResult(attribute).value
    }

    func getValueResult(_ attribute: NSAccessibility.Attribute, timeout: Float? = nil) -> AXLookupResult<AnyObject> {
        performTimedLookup(timeout: timeout) {
            var value: AnyObject?
            let result = AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)
            return (result == .success ? value : nil, result)
        }
    }
    
    /// Helper to fetch and extract a struct value with explicit type validation.
    func getWrappedValue<T>(_ attribute: NSAccessibility.Attribute, type: AXValueType) -> T? {
        guard let value = getValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue).toValue(type: type)
    }
    
    private func setValue(_ attribute: NSAccessibility.Attribute, _ value: AnyObject) {
        AXUIElementSetAttributeValue(self, attribute.rawValue as CFString, value)
    }
    
    func setValue(_ attribute: NSAccessibility.Attribute, _ value: Bool) {
        setValue(attribute, value as CFBoolean)
    }
    
    private func setWrappedValue<T>(_ attribute: NSAccessibility.Attribute, _ value: T, _ type: AXValueType) {
        guard let value = AXValue.from(value: value, type: type) else { return }
        setValue(attribute, value)
    }
    
    func setValue(_ attribute: NSAccessibility.Attribute, _ value: CGPoint) {
        setWrappedValue(attribute, value, .cgPoint)
    }
    
    func setValue(_ attribute: NSAccessibility.Attribute, _ value: CGSize) {
        setWrappedValue(attribute, value, .cgSize)
    }
    
    func getElementAtPosition(_ position: CGPoint) -> AXUIElement? {
        getElementAtPositionResult(position).value
    }

    func getElementAtPositionResult(_ position: CGPoint, timeout: Float? = nil) -> AXLookupResult<AXUIElement> {
        performTimedLookup(timeout: timeout) {
            var element: AXUIElement?
            let result = AXUIElementCopyElementAtPosition(self, Float(position.x), Float(position.y), &element)
            return (result == .success ? element : nil, result)
        }
    }

    private func performTimedLookup<Value>(timeout: Float?, _ call: () -> (value: Value?, error: AXError)) -> AXLookupResult<Value> {
        if let timeout {
            AXUIElementSetMessagingTimeout(self, timeout)
        }
        defer {
            if timeout != nil {
                AXUIElementSetMessagingTimeout(self, 0)
            }
        }
        let start = timeout != nil ? CFAbsoluteTimeGetCurrent() : 0
        let outcome = call()
        let elapsed = timeout != nil ? CFAbsoluteTimeGetCurrent() - start : 0
        let timedOut = timeout.map { Self.didMessagingTimeout(error: outcome.error, elapsed: elapsed, timeout: $0) } ?? false
        return AXLookupResult(value: outcome.value, error: outcome.error, timedOut: timedOut)
    }
    
    func getPid() -> pid_t? {
        var pid = pid_t(0)
        let result = AXUIElementGetPid(self, &pid)
        guard result == .success else { return nil }
        return pid
    }
    
    func getWindowId() -> CGWindowID? {
        var windowId = CGWindowID(0)
        let result = _AXUIElementGetWindow(self, &windowId)
        guard result == .success else { return nil }
        return windowId
    }
}
