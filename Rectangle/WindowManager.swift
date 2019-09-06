//
//  WindowManager.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class WindowManager {

    private let screenDetection = ScreenDetection()
    private let windowMoverChain: [WindowMover]
    private let windowCalculationFactory: WindowCalculationFactory
    private let windowHistory: WindowHistory
    
    init(windowCalculationFactory: WindowCalculationFactory, windowHistory: WindowHistory) {
        self.windowCalculationFactory = windowCalculationFactory
        self.windowHistory = windowHistory
        windowMoverChain = [
            StandardWindowMover(),
            // QuantizedWindowMover(), // This was used in Spectacle, but doesn't seem to help on any windows I've tried. It just makes some actions feel more jenky
            BestEffortWindowMover()
        ]
    }
    
    func execute(_ parameters: ExecutionParameters) {
        guard let frontmostWindowElement = AccessibilityElement.frontmostWindow(),
            let windowId = frontmostWindowElement.getIdentifier()
        else {
            NSSound.beep()
            return
        }
        
        let action = parameters.action
        
        if action == .restore {
            if let restoreRect = windowHistory.restoreRects[windowId] {
                frontmostWindowElement.setRectOf(restoreRect)
            }
            windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            return
        }
        
        guard let usableScreens = screenDetection.detectScreens(using: frontmostWindowElement) else {
            NSSound.beep()
            return
        }
        
        let currentWindowRect: CGRect = frontmostWindowElement.rectOfElement()
        
        let lastRectangleAction = windowHistory.lastRectangleActions[windowId]
        
        if parameters.updateRestoreRect {
            if windowHistory.restoreRects[windowId] == nil
                || currentWindowRect != lastRectangleAction?.rect {
                windowHistory.restoreRects[windowId] = currentWindowRect
            }
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
        windowHistory.lastRectangleActions[windowId] = RectangleAction(action: calcResult.resultingAction, rect: resultingRect)
    }
}

struct RectangleAction {
    let action: WindowAction
    let rect: CGRect
}

struct ExecutionParameters {
    let action: WindowAction
    let updateRestoreRect: Bool
    
    init(_ action: WindowAction, updateRestoreRect: Bool = true) {
        self.action = action
        self.updateRestoreRect = updateRestoreRect
    }
}
