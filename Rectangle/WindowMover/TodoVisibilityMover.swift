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

class TodoVisibilityWindowMover: WindowMover {
    private let kTodoWidth = CGFloat(400)

    func moveAll() {
        let windows = AccessibilityElement.allWindows()

        // Clear all windows from the todo app sidebar
        for w in windows {
            shiftWindowOffSidebar(w)
        }

        // Place the todo app in the sidebar
        if let todoApplication = AccessibilityElement.todoWindow() {
            var rect = todoApplication.rectOfElement()
            let screen = NSScreen.screens[0].frame as CGRect
            rect.origin.x = screen.maxX - kTodoWidth
            rect.size.width = kTodoWidth
            todoApplication.setRectOf(rect)
        }
    }
    
    func shiftWindowOffSidebar(_ w: AccessibilityElement) {
        var rect = w.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect

        if (rect.maxX > (screen.maxX - kTodoWidth)) {
            // Shift it to the left
            rect.origin.x = max (0, rect.origin.x - (rect.maxX - (screen.maxX - kTodoWidth)))

            // If it's still too wide, scale it down
            if (rect.origin.x == 0) {
                rect.size.width = min(rect.size.width, screen.maxX - kTodoWidth)
            }

            w.setRectOf(rect)
        }
    }

    func scaledDimensionsFor (_ window: AccessibilityElement) -> CGRect {
        var rect = window.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect

        rect.size.width *= (screen.maxX - kTodoWidth) / screen.maxX
        rect.origin.x *= (screen.maxX - kTodoWidth) / screen.maxX
        
        return rect
    }

    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        if(Defaults.todoMode.enabled) {
            guard let window: AccessibilityElement = frontmostWindowElement else { return }

            window.setRectOf(scaledDimensionsFor(window))
            shiftWindowOffSidebar(window)
        }
    }
}
