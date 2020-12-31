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

class WindowProxy {
    var frame: CGRect
    private var number: Int
    private var owner: String
    private var ownerPID: Int
    
    init(frame: CGRect, number: Int, owner: String, ownerPID: Int) {
        self.frame = frame
        self.number = number
        self.owner = owner
        self.ownerPID = ownerPID
    }
}

class TodoVisibilityWindowMover: WindowMover {
    private let kTodoWidth = CGFloat(400)

    func activeWindows() -> [WindowProxy] {
        let options = CGWindowListOption(arrayLiteral: CGWindowListOption.excludeDesktopElements, CGWindowListOption.optionOnScreenOnly)
        let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        guard let infoList = (windowListInfo as NSArray?) as? [[String: AnyObject]] else { return [] }
        var windows: [WindowProxy] = []
        
        for w in infoList {
            let bounds = w[kCGWindowBounds as String] as! NSDictionary
            if let rect = CGRect.init(dictionaryRepresentation: bounds as CFDictionary),
               let num = w[kCGWindowNumber as String] as? Int,
               let ownerPID = w[kCGWindowOwnerPID as String] as? Int,
               let owner = w[kCGWindowOwnerName as String] as? String {
                windows.append(WindowProxy(frame: rect, number: num, owner: owner, ownerPID: ownerPID))
            }
        }

        return windows
    }
    
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
