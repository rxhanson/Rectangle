//
//  WindowManager.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class WindowManager {
    typealias appBundleId = String

    private let screenDetection = ScreenDetection()
    private let windowMoverChain: [WindowMover]
    private let windowCalculationFactory = WindowCalculationFactory()
    
    private var restoreRects = [appBundleId: CGRect]() // the last window frame that the user positioned
    private var lastRectangleRects = [appBundleId: CGRect]() // the last window frame that this app positioned
    
    init() {
        windowMoverChain = [
            StandardWindowMover(),
//            QuantizedWindowMover(),
            BestEffortWindowMover()
        ]
    }
    
    func execute(_ action: WindowAction) {
        guard let frontmostWindowElement = AccessibilityElement.frontmostWindow(),
            let frontmostAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else {
            NSSound.beep()
            return
        }
        
        if action == .restore {
            if let restoreRect = restoreRects[frontmostAppBundleId] {
                frontmostWindowElement.setRectOf(restoreRect)
            }
            lastRectangleRects.removeValue(forKey: frontmostAppBundleId)
            return
        }
        
        guard let usableScreens = screenDetection.detectScreens(for: action, using: frontmostWindowElement) else {
            NSSound.beep()
            return
        }
        
        let currentWindowRect: CGRect = frontmostWindowElement.rectOfElement()
        
        if restoreRects[frontmostAppBundleId] == nil
            || currentWindowRect != lastRectangleRects[frontmostAppBundleId] {
            restoreRects[frontmostAppBundleId] = currentWindowRect
        }
        
        if frontmostWindowElement.isSheet()
            || frontmostWindowElement.isSystemDialog()
            || currentWindowRect.isNull
            || usableScreens.frameOfCurrentScreen.isNull
            || usableScreens.visibleFrameOfCurrentScreen.isNull {
            NSSound.beep()
            return
        }

        let currentNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(currentWindowRect, frameOfScreen: usableScreens.frameOfCurrentScreen)
        
        let windowCalculation = windowCalculationFactory.calculation(for: action)

        guard let calcResult = windowCalculation?.calculate(currentNormalizedRect, usableScreens: usableScreens, action: action) else {
            NSSound.beep()
            return
        }

        let newNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(calcResult.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)

        if currentNormalizedRect.equalTo(newNormalizedRect) {
            NSSound.beep()
            return
        }

        let visibleFrameOfDestinationScreen = NSRectToCGRect(calcResult.screen.visibleFrame)

        for windowMover in windowMoverChain {
            windowMover.moveWindowRect(newNormalizedRect, frameOfScreen: usableScreens.frameOfCurrentScreen, visibleFrameOfScreen: visibleFrameOfDestinationScreen, frontmostWindowElement: frontmostWindowElement, action: action)
        }

        let resultingRect = frontmostWindowElement.rectOfElement()
        lastRectangleRects[frontmostAppBundleId] = resultingRect
    }
}
