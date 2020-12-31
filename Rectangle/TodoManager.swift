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
import Cocoa

class TodoManager {
    static var todoScreen : NSScreen?
    
    static func refreshTodoScreen() {
        let todoWindow = AccessibilityElement.todoWindow()
        let screens = ScreenDetection().detectScreens(using: todoWindow)
        TodoManager.todoScreen = screens?.currentScreen
    }
    
    func moveAll() {
        TodoManager.refreshTodoScreen()

        let windows = AccessibilityElement.allWindows()

        if let todoWindow = AccessibilityElement.todoWindow() {
            if let screen = TodoManager.todoScreen {
                let screenFrame = screen.frame as CGRect
                let sd = ScreenDetection()
                // Clear all windows from the todo app sidebar
                for w in windows {
                    let wScreen = sd.detectScreens(using: w)?.currentScreen
                    if w.getIdentifier() != todoWindow.getIdentifier() &&
                        wScreen == TodoManager.todoScreen {
                        shiftWindowOffSidebar(w, screenFrame: screenFrame)
                    }
                }

                var rect = todoWindow.rectOfElement()
                rect.origin.x = screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value)
                rect.origin.y = screenFrame.minY
                rect.size.height = screen.adjustedVisibleFrame.height
                rect.size.width = CGFloat(Defaults.todoSidebarWidth.value)
                todoWindow.setRectOf(rect)
            }
        }
    }
    
    func shiftWindowOffSidebar(_ w: AccessibilityElement, screenFrame: CGRect) {
        var rect = w.rectOfElement()

        if (rect.maxX > (screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value))) {
            // Shift it to the left
            rect.origin.x = max (0, rect.origin.x - (rect.maxX - (screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value))))

            // If it's still too wide, scale it down
            if (rect.origin.x == 0) {
                rect.size.width = min(rect.size.width, screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value))
            }

            w.setRectOf(rect)
        }
    }
}
