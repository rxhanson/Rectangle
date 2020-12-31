//
//  TodoVisibilityMover.swift
//  Rectangle
//
//  Created by Patrick Collison on 12/30/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation
import AppKit
import CoreFoundation

class TodoManager {
    func moveAll() {
        let windows = AccessibilityElement.allWindows()

        if let todoApplication = AccessibilityElement.todoWindow() {
            // Clear all windows from the todo app sidebar
            for w in windows {
                if w.getIdentifier() != todoApplication.getIdentifier() {
                    shiftWindowOffSidebar(w)
                }
            }

            var rect = todoApplication.rectOfElement()
            let screen = NSScreen.screens[0]
            let screenFrame = screen.frame as CGRect
            rect.origin.x = screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value)
            rect.origin.y = screen.adjustedVisibleFrame.minY
            rect.size.height = screen.adjustedVisibleFrame.height
            rect.size.width = CGFloat(Defaults.todoSidebarWidth.value)
            todoApplication.setRectOf(rect)
        }
    }
    
    func shiftWindowOffSidebar(_ w: AccessibilityElement) {
        var rect = w.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect

        if (rect.maxX > (screen.maxX - CGFloat(Defaults.todoSidebarWidth.value))) {
            // Shift it to the left
            rect.origin.x = max (0, rect.origin.x - (rect.maxX - (screen.maxX - CGFloat(Defaults.todoSidebarWidth.value))))

            // If it's still too wide, scale it down
            if (rect.origin.x == 0) {
                rect.size.width = min(rect.size.width, screen.maxX - CGFloat(Defaults.todoSidebarWidth.value))
            }

            w.setRectOf(rect)
        }
    }
}
