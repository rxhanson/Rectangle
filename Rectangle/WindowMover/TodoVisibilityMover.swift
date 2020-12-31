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
        for w in windows {
            w.setRectOf(shrunkenDimensionsFor(w))
            w.setRectOf(translatedDimensionsFor(w))
        }

        if let todoApplication = AccessibilityElement.todoWindow() {
            var rect = todoApplication.rectOfElement()
            let screen = NSScreen.screens[0].frame as CGRect
            rect.origin.x = screen.maxX - kTodoWidth
            rect.size.width = kTodoWidth
            todoApplication.setRectOf(rect)
        }
    }

    func shrunkenDimensionsFor(_ window: AccessibilityElement) -> CGRect {
        var rect = window.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect
        rect.size.width *= (screen.maxX - kTodoWidth) / screen.maxX
        return rect
    }

    func translatedDimensionsFor(_ window: AccessibilityElement) -> CGRect {
        var rect = window.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect
        rect.origin.x *= (screen.maxX - kTodoWidth) / screen.maxX
        return rect
    }

    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        if(Defaults.todoMode.enabled) {
            guard let window: AccessibilityElement = frontmostWindowElement else { return }

            window.setRectOf(shrunkenDimensionsFor(window))
            window.setRectOf(translatedDimensionsFor(window))
        }
    }
}
