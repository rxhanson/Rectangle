//
//  MouseGestureManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class MouseGestureManager {
    
    let windowCalculationFactory: WindowCalculationFactory
    let windowHistory: WindowHistory
    
    var eventMonitor: EventMonitor?
    var frontmostWindow: AccessibilityElement?
    
    var startLoc: NSPoint?
    var windowElement: AccessibilityElement?
    
    init(windowCalculationFactory: WindowCalculationFactory, windowHistory: WindowHistory) {
        self.windowCalculationFactory = windowCalculationFactory
        self.windowHistory = windowHistory
        
        if Defaults.windowSnapping.enabled != false {
            enableSnapping()
        }
        
        subscribeToWindowSnappingToggle()
    }
    

    func handle(event: NSEvent?) {
        
        guard let event = event else { return }
        if event.modifierFlags.contains(.command) {
            if startLoc == nil {
                startLoc = event.locationInWindow
                windowElement = AccessibilityElement.windowUnderCursor()
            }
        }
        if let startLoc = startLoc, !event.modifierFlags.contains(.command) {
            if let windowElement = windowElement {
                if event.locationInWindow.x < startLoc.x {
                    WindowAction.leftHalf.postGesture(windowElement: windowElement)
                } else {
                    WindowAction.rightHalf.postGesture(windowElement: windowElement)
                }
            }
            self.startLoc = nil
            self.windowElement = nil
        }
    }
    
}

extension MouseGestureManager {
    
    private func subscribeToWindowSnappingToggle() {
        NotificationCenter.default.addObserver(self, selector: #selector(windowSnappingToggled), name: SettingsViewController.windowSnappingNotificationName, object: nil)
    }
    
    @objc func windowSnappingToggled(notification: Notification) {
        guard let enabled = notification.object as? Bool else { return }
        if enabled {
            enableSnapping()
        } else {
            disableSnapping()
        }
    }
    
    private func enableSnapping() {
        eventMonitor = EventMonitor(mask: [.mouseMoved], handler: handle)
        eventMonitor?.start()
    }
    
    private func disableSnapping() {
        eventMonitor?.stop()
        eventMonitor = nil
    }
    
}
