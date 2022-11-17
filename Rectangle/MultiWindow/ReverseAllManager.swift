//
//  TodoManager.swift
//  Rectangle
//
//  Created by Charlie Harding on 7/25/21.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//
import Cocoa
import MASShortcut

class ReverseAllManager {

    static func reverseAll(windowElement: AccessibilityElement? = nil) {
        let sd = ScreenDetection()

        let currentWindow = windowElement ?? AccessibilityElement.getFrontWindowElement()
        guard let currentScreen = sd.detectScreens(using: currentWindow)?.currentScreen else { return }

        let windows = AccessibilityElement.getAllWindowElements()

        let screenFrame = currentScreen.adjustedVisibleFrame

        for w in windows {
            let wScreen = sd.detectScreens(using: w)?.currentScreen
            if Defaults.todo.userEnabled && TodoManager.isTodoWindow(w) { continue }
            if wScreen == currentScreen {
                reverseWindowPosition(w, screenFrame: screenFrame)
            }
        }
    }

    private static func reverseWindowPosition(_ w: AccessibilityElement, screenFrame: CGRect) {
        var rect = w.frame

        let offsetFromLeft = rect.minX - screenFrame.minX

        rect.origin.x = screenFrame.maxX - offsetFromLeft - rect.width

        w.setFrame(rect)
    }
}
