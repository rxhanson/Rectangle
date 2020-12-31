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
            if windowNeedsAdjustment(w) {
                w.setRectOf(shrunkenDimensionsFor(w))

                if windowNeedsAdjustment(w) {
                    w.setRectOf(translatedDimensionsFor(w))
                }
            }
        }

        if let todoApplication = AccessibilityElement.todoWindow() {
            var rect = todoApplication.rectOfElement()
            let screen = NSScreen.screens[0].frame as CGRect
            rect.origin.x = screen.maxX - kTodoWidth
            rect.size.width = kTodoWidth
            todoApplication.setRectOf(rect)
        }
    }

    func windowNeedsAdjustment(_ window: AccessibilityElement) -> Bool {
        let screen = NSScreen.screens[0].frame as CGRect
        return window.rectOfElement().maxX > (screen.maxX - kTodoWidth)
    }

    func shrunkenDimensionsFor(_ window: AccessibilityElement) -> CGRect {
        var rect = window.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect
        rect.size.width -= (screen.maxX - (screen.maxX - kTodoWidth))
        return rect
    }

    func translatedDimensionsFor(_ window: AccessibilityElement) -> CGRect {
        var rect = window.rectOfElement()
        let screen = NSScreen.screens[0].frame as CGRect
        rect.origin.x -= (screen.maxX - (screen.maxX - kTodoWidth))
        return rect
    }

    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        if(Defaults.todoMode.enabled) {
            guard let beforeCorrection: CGRect = frontmostWindowElement?.rectOfElement() else { return }
            guard let window: AccessibilityElement = frontmostWindowElement else { return }
            let todoAccommodatingMaxX = visibleFrameOfScreen.maxX - kTodoWidth

            if beforeCorrection.maxX > todoAccommodatingMaxX {
                window.setRectOf(shrunkenDimensionsFor(window))

                if windowNeedsAdjustment(window) {
                    window.setRectOf(translatedDimensionsFor(window))
                }
            }
        }
    }
}
