//
//  TitleBarManager.swift
//  Rectangle
//
//  Copyright © 2023 Ryan Hanson. All rights reserved.
//

import Foundation

class TitleBarManager {
    private var eventMonitor: EventMonitor!
    private var lastEventNumber: Int?

    init() {
        eventMonitor = PassiveEventMonitor(mask: .leftMouseUp, handler: handle)
        toggleListening()
        Notification.Name.windowTitleBar.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }
    
    private func toggleListening() {
        if WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil {
            eventMonitor.start()
        } else {
            eventMonitor.stop()
        }
    }
    
    private func handle(_ event: NSEvent) {
        guard
            event.type == .leftMouseUp,
            event.clickCount == 2,
            event.eventNumber != lastEventNumber,
            TitleBarManager.systemSettingDisabled,
            let action = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1),
            case let location = NSEvent.mouseLocation.screenFlipped,
            let element = AccessibilityElement(location)?.getSelfOrChildElementRecursively(location),
            let windowElement = element.windowElement,
            var titleBarFrame = windowElement.titleBarFrame
        else {
            return
        }
        lastEventNumber = event.eventNumber
        
        var bundleIdentifier: String?
        if let pid = element.pid {
            bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        
        if let toolbarFrame = windowElement.getChildElement(.toolbar)?.frame, toolbarFrame != .null {
            if let bundleIdentifier,
               let toolbarIgnoredIds = Defaults.doubleClickToolBarIgnoredApps.typedValue,
               toolbarIgnoredIds.contains(bundleIdentifier) {
               // don't add the toolbar frame to the title bar
            } else {
                titleBarFrame = titleBarFrame.union(toolbarFrame)
            }
        }
        guard
            titleBarFrame.contains(location),
            element.isWindow == true || element.isToolbar == true || element.isGroup == true || element.isTabGroup == true || element.isStaticText == true
        else {
            return
        }
        if let bundleIdentifier,
            let ignoredApps = Defaults.doubleClickTitleBarIgnoredApps.typedValue,
            ignoredApps.contains(bundleIdentifier) {
            return
        }
        if Defaults.doubleClickTitleBarRestore.enabled != false,
           let windowId = windowElement.windowId,
           case let windowFrame = windowElement.frame,
           windowFrame != .null,
           let historyAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
           historyAction.action == action,
           historyAction.rect == windowFrame {
            WindowAction.restore.postTitleBar(windowElement: windowElement)
            return
        }
        action.postTitleBar(windowElement: windowElement)
    }
}

extension TitleBarManager {
    static var systemSettingDisabled: Bool {
        UserDefaults(suiteName: ".GlobalPreferences")?.string(forKey: "AppleActionOnDoubleClick") == "None"
    }
}
