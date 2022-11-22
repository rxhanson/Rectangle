//
//  AXExtension.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

extension NSAccessibility.Attribute {
    static let enhancedUserInterface = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
    static let windowIds = NSAccessibility.Attribute(rawValue: "AXWindowsIDs")
}

extension AXValue {
    func toValue<T>() -> T? {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        let success = AXValueGetValue(self, AXValueGetType(self), pointer)
        let value = pointer.pointee
        pointer.deallocate()
        return success ? value : nil
    }
    
    static func from<T>(value: T, type: AXValueType) -> AXValue? {
        var value = value
        return AXValueCreate(type, &value)
    }
}

extension AXUIElement {
    static let systemWide = AXUIElementCreateSystemWide()
    
    func isValueSettable(_ attribute: NSAccessibility.Attribute) -> Bool? {
        var isSettable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(self, attribute.rawValue as CFString, &isSettable)
        guard result == .success else { return nil }
        return isSettable.boolValue
    }
    
    func getValue(_ attribute: NSAccessibility.Attribute) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
    
    func getWrappedValue<T>(_ attribute: NSAccessibility.Attribute) -> T? {
        guard let value = getValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue).toValue()
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
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(self, Float(position.x), Float(position.y), &element)
        guard result == .success else { return nil }
        return element
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
