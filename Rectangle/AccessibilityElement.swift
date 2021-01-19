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

// The AXEnhancedUserInterface attribute is undocumented. However, it does appear in the
// Accessibility Inspector [1] under the name "Enhanced User Interface" and in the list of
// attribute names returned by AXUIElementCopyAttributeNames for an AXUIElement with a
// role of kAXApplicationRole.
// [1]: https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXTestingApps.html
let kAXEnhancedUserInterface: String = "AXEnhancedUserInterface"

class AccessibilityElement {
    static let systemWideElement = AccessibilityElement(AXUIElementCreateSystemWide())

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
            Logger.log("Failed to find the application that currently has focus.")
            return nil
        }
        let focusedAttr = NSAccessibility.Attribute.focusedWindow as CFString
        return frontmostApplicationElement.withAttribute(focusedAttr)
    }
    
    static func windowUnderCursor() -> AccessibilityElement? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var element: AXUIElement?
        let result: AXError = AXUIElementCopyElementAtPosition(systemWideElement.underlyingElement, Float(location.x), Float(location.y), &element)
        if result == .success {
            if let element = element {
                return AccessibilityElement(element).window()
            }
        } else {
            print("Unable to obtain the accessibility element with the specified attribute at mouse location")
        }
        return nil
    }
    
    func withAttribute(_ attribute: CFString) -> AccessibilityElement? {
        var copiedUnderlyingElement: AnyObject?
        let result: AXError = AXUIElementCopyAttributeValue(underlyingElement, attribute, &copiedUnderlyingElement)
        if result == .success {
            if let copiedUnderlyingElement = copiedUnderlyingElement {
                return AccessibilityElement(copiedUnderlyingElement as! AXUIElement)
            }
        }
        Logger.log("Unable to obtain accessibility element")
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
        // "Enhanced User Interface" is an undocumented attribute that has been
        // reported by others to cause issue with window resizing (e.g.
        // https://github.com/electron/electron/issues/7206). If this setting is
        // enabled for the application of the window being resized, disable this
        // attribute before performing the resizes. See:
        // * https://github.com/rxhanson/Rectangle/issues/15
        // * https://github.com/rxhanson/Rectangle/issues/29
        // * https://github.com/rxhanson/Rectangle/issues/94
        // * https://github.com/rxhanson/Rectangle/issues/165
        let app = application()
        var enhancedUserInterfaceEnabled: Bool? = nil

        if let app = app {
            enhancedUserInterfaceEnabled = app.isEnhancedUserInterfaceEnabled()
            if enhancedUserInterfaceEnabled == true {
                Logger.log("AXEnhancedUserInterface was enabled, will disable before resizing")
                AXUIElementSetAttributeValue(app.underlyingElement, kAXEnhancedUserInterface as CFString, kCFBooleanFalse)
            }
        }

        set(size: rect.size)
        set(position: rect.origin)
        set(size: rect.size)

        // If "enhanced user interface" was originally enabled for the app, turn it back on
        if let app = app, enhancedUserInterfaceEnabled == true {
            AXUIElementSetAttributeValue(app.underlyingElement, kAXEnhancedUserInterface as CFString, kCFBooleanTrue)
        }
    }
    
    func isResizable() -> Bool {
        var resizable: DarwinBoolean = true
        let status = AXUIElementIsAttributeSettable(self.underlyingElement, kAXSizeAttribute as CFString, &resizable)
        
        if status != .success {
            Logger.log("Unable to determine if window is resizeable. Assuming it is.")
        }
        return resizable.boolValue
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
    
    func isEnhancedUserInterfaceEnabled() -> Bool? {
        var rawValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, kAXEnhancedUserInterface as CFString, &rawValue)

        if error == .success && CFGetTypeID(rawValue) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((rawValue as! CFBoolean))
        }

        return nil
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
        Logger.log("Unable to obtain window id")
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
    
    func set(position: CGPoint) {
        if let value = AXValue.from(value: position, type: .cgPoint) {
            AXUIElementSetAttributeValue(self.underlyingElement, kAXPositionAttribute as CFString, value)
            Logger.log("AX position proposed: \(position.debugDescription), result: \(getPosition()?.debugDescription ?? "N/A")")
        }
    }
    
    private func getSize() -> CGSize? {
        return self.value(for: .size)
    }
    
    func set(size: CGSize) {
        if let value = AXValue.from(value: size, type: .cgSize) {
            AXUIElementSetAttributeValue(self.underlyingElement, kAXSizeAttribute as CFString, value)
            Logger.log("AX sizing proposed: \(size.debugDescription), result: \(getSize()?.debugDescription ?? "N/A")")
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
    
    private func window() -> Self? {
        if role() == kAXWindowRole { return self }
        return self.value(for: .window)
    }
    
    private func application() -> Self? {
        var element = self
        while element.role() != kAXApplicationRole {
            if let nextElement = element.parent() {
                element = nextElement
            } else {
                return nil
            }
        }

        return element
    }

    private func parent() -> Self? {
        return self.value(for: .parent)
    }

    private func role() -> String? {
        return self.value(for: .role)
    }
    
    func bringToFront(force: Bool = false) {
        let isMainWindow = self.rawValue(for: .main) as? Bool
        if isMainWindow != true {
            AXUIElementSetAttributeValue(self.underlyingElement, NSAccessibility.Attribute.main.rawValue as CFString, true as CFTypeRef)
        }

        if let app = NSRunningApplication(processIdentifier: getPid()) {
            if !app.isActive || force {
                app.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
}

// todo mode
extension AccessibilityElement {
    private static func PIDsWithWindows() -> Set<Int> {
        let options = CGWindowListOption(arrayLiteral: CGWindowListOption.excludeDesktopElements, CGWindowListOption.optionOnScreenOnly)
        let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        guard let infoList = (windowListInfo as NSArray?) as? [[String: AnyObject]] else { return [] }
        var PIDs: Set<Int> = []

        for w in infoList {
            if let ownerPID = w[kCGWindowOwnerPID as String] as? Int {
                PIDs.insert(ownerPID)
            }
        }

        return PIDs
    }

    static func allWindowsForPIDs(_ pids: [Int]) -> [AccessibilityElement] {
        let apps = pids.map {
            AccessibilityElement(AXUIElementCreateApplication(pid_t($0)))
        }
        var windows = [AccessibilityElement]()

        for app in apps {
            var rawValue: AnyObject? = nil
            if AXUIElementCopyAttributeValue(app.underlyingElement,
                                             NSAccessibility.Attribute.windows as CFString,
                                             &rawValue) == .success {
                windows.append(contentsOf: (rawValue as! [AXUIElement]).map { AccessibilityElement($0) })
            }
        }

        return windows
    }

    static func allWindows() -> [AccessibilityElement] {
        allWindowsForPIDs([Int](PIDsWithWindows()))
    }

    static func todoWindow() -> AccessibilityElement? {
        let apps = NSWorkspace.shared.runningApplications

        for app in apps {
            if app.bundleIdentifier == Defaults.todoApplication.value {
                let windows = allWindowsForPIDs([Int(app.processIdentifier)])
                if(windows.count > 0) {
                    return windows[0]
                }
            }
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
