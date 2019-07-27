//
//  WindowManager.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
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
        
        let screenDetectionResult: ScreenDetectionResult = screenDetection.screen(with: action, frontmostWindowElement: frontmostWindowElement)
        
        var frameOfDestinationScreen = CGRect.null
        var visibleFrameOfDestinationScreen = CGRect.null
        var visibleFrameOfSourceScreen = CGRect.null
        
        if let destinationScreen = screenDetectionResult.destinationScreen,
            let sourceScreen = screenDetectionResult.sourceScreen {
            frameOfDestinationScreen = NSRectToCGRect(destinationScreen.frame)
            visibleFrameOfDestinationScreen = NSRectToCGRect(destinationScreen.visibleFrame)
            visibleFrameOfSourceScreen = NSRectToCGRect(sourceScreen.visibleFrame)
        }

        let currentWindowRect: CGRect = frontmostWindowElement.rectOfElement()
        
        if restoreRects[frontmostAppBundleId] == nil
            || currentWindowRect != lastRectangleRects[frontmostAppBundleId] {
            restoreRects[frontmostAppBundleId] = currentWindowRect
        }
        
        if frontmostWindowElement.isSheet()
            || frontmostWindowElement.isSystemDialog()
            || currentWindowRect.isNull
            || frameOfDestinationScreen.isNull
            || visibleFrameOfDestinationScreen.isNull
            || visibleFrameOfSourceScreen.isNull {
            NSSound.beep()
            return
        }

        let currentNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(currentWindowRect, frameOfScreen: frameOfDestinationScreen)
        
        let windowCalculation = windowCalculationFactory.calculation(for: action)

        guard let newRect = windowCalculation?.calculate(currentNormalizedRect, visibleFrameOfSourceScreen: visibleFrameOfSourceScreen, visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen, action: action) else {
            NSSound.beep()
            return
        }
        
        let newNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(newRect, frameOfScreen: frameOfDestinationScreen)
        
        if currentNormalizedRect.equalTo(newNormalizedRect) {
            NSSound.beep()
            return
        }
        
        for windowMover in windowMoverChain {
            windowMover.moveWindowRect(newNormalizedRect, frameOfScreen: frameOfDestinationScreen, visibleFrameOfScreen: visibleFrameOfDestinationScreen, frontmostWindowElement: frontmostWindowElement, action: action)
        }
        
        let resultingRect = frontmostWindowElement.rectOfElement()
        lastRectangleRects[frontmostAppBundleId] = resultingRect
    }
}
