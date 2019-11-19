//
//  AccessibilityElement.swift
//  Rectangle, Ported from Spectacle, Combined with snippets from ModMove
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import Carbon
import Cocoa
import os.log

class AccessibilityElement {
    private let underlyingElement: AXUIElement
    
    required init(_ axUIElement: AXUIElement) {
        self.underlyingElement = axUIElement
    }
    
    private static func frontmostApplication() -> AccessibilityElement? {
        guard let frontmostApplication: NSRunningApplication = NSWorkspace.shared.frontmostApplication else { return nil }
        let underlyingElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        let frontmostApplicationElement = AccessibilityElement(underlyingElement)
        return frontmostApplicationElement
    }
    
    static func frontmostWindow() -> AccessibilityElement? {
        guard let frontmostApplicationElement = AccessibilityElement.frontmostApplication() else {
            os_log("Failed to find the application that currently has focus.", type: .info)
            return nil
        }
        let focusedAttr = NSAccessibility.Attribute.focusedWindow as CFString
        return frontmostApplicationElement.withAttribute(focusedAttr)
    }
    
    func withAttribute(_ attribute: CFString) -> AccessibilityElement? {
        var copiedUnderlyingElement: AnyObject?
        let result: AXError = AXUIElementCopyAttributeValue(underlyingElement, attribute, &copiedUnderlyingElement)
        if result == .success {
            if let copiedUnderlyingElement = copiedUnderlyingElement {
                return AccessibilityElement(copiedUnderlyingElement as! AXUIElement)
            }
        }
        os_log("Unable to obtain accessibility element", type: .debug)
        return nil
    }
    
    func rectOfElement() -> CGRect {
        guard let position: CGPoint = getPosition(),
            let size: CGSize = getSize()
            else {
                return CGRect.null
        }
        return CGRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }
    
    func setRectOf(_ rect: CGRect) {
        set(position: rect.origin)
        set(size: rect.size)
    }
    
    static func normalizeCoordinatesOf(_ rect: CGRect, frameOfScreen: CGRect) -> CGRect {
        var normalizedRect = rect
        let frameOfScreenWithMenuBar = NSScreen.screens[0].frame as CGRect
        normalizedRect.origin.y = frameOfScreen.size.height - rect.maxY + (frameOfScreenWithMenuBar.size.height - frameOfScreen.size.height)
        return normalizedRect
    }
    
    func isSheet() -> Bool {
        return value(for: .role) == kAXSheetRole
    }
    
    func isSystemDialog() -> Bool {
        return value(for: .subrole) == kAXSystemDialogSubrole
    }
    
    func getIdentifier() -> Int? {
        if let windowInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, 0) as? Array<Dictionary<String,Any>> {
            let pid = getPid()
            let rect = rectOfElement()
            
            let windowsOfSameApp = windowInfo.filter { (infoDict) -> Bool in
                infoDict[kCGWindowOwnerPID as String] as? pid_t == pid
            }
            
            let matchingWindows = windowsOfSameApp.filter { (infoDict) -> Bool in
                if let bounds = infoDict[kCGWindowBounds as String] as? [String: CGFloat] {
                    if bounds["X"] == rect.origin.x
                        && bounds["Y"] == rect.origin.y
                        && bounds["Height"] == rect.height
                        && bounds["Width"] == rect.width {
                        return true
                    }
                }
                return false
            }
            
            // Take the first match because there's no real way to guarantee which window we're actually getting
            if let firstMatch = matchingWindows.first {
                return firstMatch[kCGWindowNumber as String] as? Int
            }
        }
        return nil
    }
    
    func getPid() -> pid_t {
        var pid: pid_t = 0;
        AXUIElementGetPid(self.underlyingElement, &pid);
        return pid
    }
    
    private func getPosition() -> CGPoint? {
        return self.value(for: .position)
    }
    
    private func set(position: CGPoint) {
        if let value = AXValue.from(value: position, type: .cgPoint) {
            AXUIElementSetAttributeValue(self.underlyingElement, kAXPositionAttribute as CFString, value)
            if Defaults.debug.enabled {
                os_log("AX position proposed: %{public}@, result: %{public}@", type: .debug, position.debugDescription, getPosition()?.debugDescription ?? "N/A")
            }
        }
    }
    
    private func getSize() -> CGSize? {
        return self.value(for: .size)
    }
    
    private func set(size: CGSize) {
        if let value = AXValue.from(value: size, type: .cgSize) {
            AXUIElementSetAttributeValue(self.underlyingElement, kAXSizeAttribute as CFString, value)
            if Defaults.debug.enabled {
                os_log("AX sizing proposed: %{public}@, result: %{public}@", type: .debug, size.debugDescription, getSize()?.debugDescription ?? "N/A")
            }
        }
    }
    
    private func rawValue(for attribute: NSAccessibility.Attribute) -> AnyObject? {
        var rawValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, attribute.rawValue as CFString, &rawValue)
        return error == .success ? rawValue : nil
    }
    
    private func value(for attribute: NSAccessibility.Attribute) -> Self? {
        if let rawValue = self.rawValue(for: attribute), CFGetTypeID(rawValue) == AXUIElementGetTypeID() {
            return type(of: self).init(rawValue as! AXUIElement)
        }
        
        return nil
    }
    
    private func value(for attribute: NSAccessibility.Attribute) -> String? {
        return self.rawValue(for: attribute) as? String
    }
    
    private func value<T>(for attribute: NSAccessibility.Attribute) -> T? {
        if let rawValue = self.rawValue(for: attribute), CFGetTypeID(rawValue) == AXValueGetTypeID() {
            return (rawValue as! AXValue).toValue()
        }
        
        return nil
    }
}

extension AXValue {
    func toValue<T>() -> T? {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        let success = AXValueGetValue(self, AXValueGetType(self), pointer)
        return success ? pointer.pointee : nil
    }
    
    static func from<T>(value: T, type: AXValueType) -> AXValue? {
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        pointer.pointee = value
        return AXValueCreate(type, pointer)
    }
}
