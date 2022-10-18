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

    static func disableEnhancedUI() {
        if let app = frontmostApplication() {
            AXUIElementSetAttributeValue(app.underlyingElement, kAXEnhancedUserInterface as CFString, kCFBooleanFalse)
        }
    }
    
    static func frontmostWindow() -> AccessibilityElement? {
        guard let appElement = AccessibilityElement.frontmostApplication() else {
            Logger.log("Failed to find the application that currently has focus.")
            return nil
        }
        let focusedAttr = NSAccessibility.Attribute.focusedWindow as CFString
        if let frontElement = appElement.withAttribute(focusedAttr) {
            return frontElement
        }
        if let firstWindow = appElement.allWindows().first {
            return firstWindow
        }
        Logger.log("Failed to find frontmost window.")
        return nil
    }

    static func windowUnderCursor() -> AccessibilityElement? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        
        var element: AXUIElement?
        let result: AXError = AXUIElementCopyElementAtPosition(systemWideElement.underlyingElement, Float(location.x), Float(location.y), &element)
        if result == .success, let element = element, let windowElement = AccessibilityElement(element).window() {
            return windowElement
        }
        
        if let windowInfo = getWindowInfo(at: location) {
            let pidWindows = Self.allWindows(pid: windowInfo.pid)
            for windowElement in pidWindows {
                if windowElement.rectOfElement().equalTo(windowInfo.frame) {
                    if Logger.logging {
                        let app = NSRunningApplication(processIdentifier: windowInfo.pid)?.localizedName ?? ""
                        Logger.log("Window under cursor fallback matched: \(app) \(windowInfo)")
                    }
                    return windowElement
                }
            }
            for windowElement in pidWindows {
                if windowElement.getIdentifier() == windowInfo.id {
                    if Logger.logging {
                        let app = NSRunningApplication(processIdentifier: windowInfo.pid)?.localizedName ?? ""
                        Logger.log("Window under cursor fallback matched: \(app) \(windowInfo)")
                    }
                    if StageUtil.stageCapable() && StageUtil.stageEnabled() && StageUtil.stageStripVisible() {
                        // In case the window is in Stage Manager recent apps
                        return FallbackAccessibilityElement(windowElement.underlyingElement)
                    }
                    return windowElement
                }
            }
        }
        
        Logger.log("Unable to obtain the accessibility element with the specified attribute at mouse location")
        return nil
    }
    
    static func getWindowInfo(at location: CGPoint) -> WindowInfo? {
        let infos = WindowUtil.windowList().filter { !["com.apple.dock", "com.apple.WindowManager"].contains($0.bundleIdentifier) }
        if var info = (infos.first { $0.frame.contains(location) }) {
            if StageUtil.stageCapable() && StageUtil.stageEnabled() && StageUtil.stageStripVisible() {
                // In case the window is in Stage Manager recent apps
                var prevInfo: WindowInfo?
                while prevInfo?.id != info.id {
                    prevInfo = info
                    info = infos.first { $0.frame.intersects(info.frame) }!
                }
            }
            return info
        }
        
        Logger.log("Unable to obtain window info from location")
        return nil
    }
    
    static func getWindowInfo(with identifier: CGWindowID) -> WindowInfo? {
        let infos = WindowUtil.windowList([identifier])
        if let info = infos.first {
            return info
        }
        
        Logger.log("Unable to obtain window info from identifier")
        return nil
    }
    
    static func allWindows(pid: pid_t) -> [AccessibilityElement] {
        var windows = [AccessibilityElement]()
        
        let app = AccessibilityElement(AXUIElementCreateApplication(pid))
        var rawValue: AnyObject? = nil
        if AXUIElementCopyAttributeValue(app.underlyingElement,
                                         NSAccessibility.Attribute.windows as CFString,
                                         &rawValue) == .success {
            windows.append(contentsOf: (rawValue as! [AXUIElement]).map { AccessibilityElement($0) })
        }

        return windows

    }
    
    func allWindows() -> [AccessibilityElement] {
        var windows = [AccessibilityElement]()
 
        guard let app = application() else { return windows }
        var rawValue: AnyObject? = nil
        if AXUIElementCopyAttributeValue(app.underlyingElement,
                                         NSAccessibility.Attribute.windows as CFString,
                                         &rawValue) == .success {
            windows.append(contentsOf: (rawValue as! [AXUIElement]).map { AccessibilityElement($0) })
        }

        return windows
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
        if Defaults.enhancedUI.value == .disableEnable, let app = app, enhancedUserInterfaceEnabled == true {
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
    
    static func normalizeCoordinatesOf(_ rect: CGRect) -> CGRect {
        var normalizedRect = rect
        let frameOfScreenWithMenuBar = NSScreen.screens[0].frame as CGRect
        normalizedRect.origin.y = frameOfScreenWithMenuBar.height - rect.maxY
        return normalizedRect
    }
    
    func isSheet() -> Bool {
        return value(for: .role) == kAXSheetRole
    }
    
    func isSystemDialog() -> Bool {
        return value(for: .subrole) == kAXSystemDialogSubrole
    }
    
    func isFullScreen() -> Bool {
        if let window = window() {
            if let fullScreenButton: AccessibilityElement = window.value(for: .fullScreenButton) {
                if let subrole: String = fullScreenButton.value(for: .subrole) {
                    if subrole == kAXZoomButtonSubrole {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    func isEnhancedUserInterfaceEnabled() -> Bool? {
        var rawValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(self.underlyingElement, kAXEnhancedUserInterface as CFString, &rawValue)

        if error == .success && CFGetTypeID(rawValue) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((rawValue as! CFBoolean))
        }

        return nil
    }

    func getIdentifier() -> CGWindowID? {
        var identifier: CGWindowID = 0
        _AXUIElementGetWindow(underlyingElement, &identifier)
        if identifier != 0 {
            return identifier
        }
        
        let infos = WindowUtil.windowList()
        let pid = getPid()
        let rect = rectOfElement()
        // Take the first match because there's no real way to guarantee which window we're actually getting
        if let info = (infos.first { $0.pid == pid && $0.frame == rect }) {
            return info.id
        }
        
        Logger.log("Unable to obtain window id")
        return nil
    }
    
    func getPid() -> pid_t {
        var pid: pid_t = 0;
        AXUIElementGetPid(self.underlyingElement, &pid);
        return pid
    }
    
    func isMinimized() -> Bool? {
        return self.rawValue(for: .minimized) as? Bool
    }
    
    func isHidden() -> Bool? {
        return self.rawValue(for: .hidden) as? Bool
    }
    
    func isWindow() -> Bool {
        return role() == kAXWindowRole
    }
    
    func isMainWindow() -> Bool? {
        return self.rawValue(for: .main) as? Bool
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
    
    private func application() -> AccessibilityElement? {
        if role() == kAXApplicationRole { return self }
        return AccessibilityElement(AXUIElementCreateApplication(getPid()))
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
    private static func PIDsWithWindows() -> [pid_t] {
        let infos = WindowUtil.windowList()
        let pids = infos.map { $0.pid }
        let uniquePids = Array(Set(pids))
        return uniquePids
    }

    static func allWindowsForPIDs(_ pids: [pid_t]) -> [AccessibilityElement] {
        let apps = pids.map {
            AccessibilityElement(AXUIElementCreateApplication($0))
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
        allWindowsForPIDs(PIDsWithWindows())
    }

    static func todoWindow() -> AccessibilityElement? {
        let apps = NSWorkspace.shared.runningApplications

        for app in apps {
            if app.bundleIdentifier == Defaults.todoApplication.value {
                let windows = allWindowsForPIDs([app.processIdentifier])
                if(windows.count > 0) {
                    return windows[0]
                }
            }
        }

        return nil
    }
}

class FallbackAccessibilityElement: AccessibilityElement {
    override func rectOfElement() -> CGRect {
        guard let id = getIdentifier(),
              let info = AccessibilityElement.getWindowInfo(with: id)
        else { return CGRect.null }
        return CGRect(origin: info.frame.origin, size: super.rectOfElement().size)
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

enum EnhancedUI: Int {
    case disableEnable = 1 /// The default behavior - disable Enhanced UI on every window move/resize
    case disableOnly = 2 /// Don't re-enable enhanced UI after it gets disabled
    case frontmostDisable = 3 /// Disable enhanced UI every time the frontmost app gets changed
}
