//
//  WindowManager.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class WindowManager {
    typealias WindowId = Int

    private let screenDetection = ScreenDetection()
    private let windowMoverChain: [WindowMover]
    private let windowCalculationFactory: WindowCalculationFactory
    
    private var restoreRects = [WindowId: CGRect]() // the last window frame that the user positioned
    private var lastRectangleActions = [WindowId: RectangleAction]() // the last window frame that this app positioned
    
    init(windowCalculationFactory: WindowCalculationFactory) {
        self.windowCalculationFactory = windowCalculationFactory
        windowMoverChain = [
            StandardWindowMover(),
            // QuantizedWindowMover(), // This was used in Spectacle, but doesn't seem to help on any windows I've tried. It just makes some actions feel more jenky
            BestEffortWindowMover()
        ]
    }
    
    func execute(_ action: WindowAction) {
        guard let frontmostWindowElement = AccessibilityElement.frontmostWindow(),
            let windowId = frontmostWindowElement.getIdentifier()
        else {
            NSSound.beep()
            return
        }
        
        if action == .restore {
            if let restoreRect = restoreRects[windowId] {
                frontmostWindowElement.setRectOf(restoreRect)
            }
            lastRectangleActions.removeValue(forKey: windowId)
            return
        }
        
        guard let usableScreens = screenDetection.detectScreens(using: frontmostWindowElement) else {
            NSSound.beep()
            return
        }
        
        let currentWindowRect: CGRect = frontmostWindowElement.rectOfElement()
        
        let lastRectangleAction = lastRectangleActions[windowId]
        
        if restoreRects[windowId] == nil
            || currentWindowRect != lastRectangleAction?.rect {
            restoreRects[windowId] = currentWindowRect
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

        guard let calcResult = windowCalculation?.calculate(currentNormalizedRect, lastAction: lastRectangleAction, usableScreens: usableScreens, action: action) else {
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
        lastRectangleActions[windowId] = RectangleAction(action: calcResult.resultingAction, rect: resultingRect)
    }
}

struct RectangleAction {
    let action: WindowAction
    let rect: CGRect
}
