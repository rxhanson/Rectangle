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
    private let standardWindowMoverChain: [WindowMover]
    private let fixedSizeWindowMoverChain: [WindowMover]
    private let windowCalculationFactory: WindowCalculationFactory
    private let windowHistory: WindowHistory
    private let gapSize = Defaults.gapSize.value
    
    init(windowCalculationFactory: WindowCalculationFactory, windowHistory: WindowHistory) {
        self.windowCalculationFactory = windowCalculationFactory
        self.windowHistory = windowHistory
        standardWindowMoverChain = [
            StandardWindowMover(),
            BestEffortWindowMover()
        ]
        
        fixedSizeWindowMoverChain = [
            CenteringFixedSizedWindowMover(),
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
        
        var screens: UsableScreens?
        if let screen = parameters.screen {
            screens = UsableScreens(currentScreen: screen, numScreens: 1)
        } else {
            screens = screenDetection.detectScreens(using: frontmostWindowElement)
        }
        
        guard let usableScreens = screens else {
            NSSound.beep()
            Logger.log("Unable to obtain usable screens")
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
            Logger.log("Window is not snappable or usable screen is not valid")
            return
        }

        let currentNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(currentWindowRect, frameOfScreen: usableScreens.frameOfCurrentScreen)
        let currentWindow = Window(id: windowId, rect: currentNormalizedRect)
        
        let windowCalculation = windowCalculationFactory.calculation(for: action)
        
        guard var calcResult = windowCalculation?.calculate(currentWindow, lastAction: lastRectangleAction, usableScreens: usableScreens, action: action) else {
            NSSound.beep()
            Logger.log("Nil calculation result")
            return
        }
        
        if gapSize > 0, calcResult.resultingAction.gapsApplicable {
            let gapSharedEdges = calcResult.resultingSubAction?.gapSharedEdge ?? calcResult.resultingAction.gapSharedEdge
            
            calcResult.rect = GapCalculation.applyGaps(calcResult.rect, sharedEdges: gapSharedEdges, gapSize: gapSize)
        }

        if currentNormalizedRect.equalTo(calcResult.rect) {
            Logger.log("Current frame is equal to new frame")
            return
        }
        
        let newRect = AccessibilityElement.normalizeCoordinatesOf(calcResult.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)

        let visibleFrameOfDestinationScreen = NSRectToCGRect(calcResult.screen.visibleFrame)

        let useFixedSizeMover = !frontmostWindowElement.isResizable() && action.resizes
        let windowMoverChain = useFixedSizeMover
            ? fixedSizeWindowMoverChain
            : standardWindowMoverChain

        for windowMover in windowMoverChain {
            windowMover.moveWindowRect(newRect, frameOfScreen: usableScreens.frameOfCurrentScreen, visibleFrameOfScreen: visibleFrameOfDestinationScreen, frontmostWindowElement: frontmostWindowElement, action: action)
        }

        let resultingRect = frontmostWindowElement.rectOfElement()
        
        var newCount = 1
        if lastRectangleAction?.action == calcResult.resultingAction,
            let currentCount = lastRectangleAction?.count {
            newCount = currentCount + 1
            newCount %= 3
        }
        
        windowHistory.lastRectangleActions[windowId] = RectangleAction(
            action: calcResult.resultingAction,
            subAction: calcResult.resultingSubAction,
            rect: resultingRect,
            count: newCount
        )
        
        if Logger.logging {
            var srcDestScreens: String = ""
            if #available(OSX 10.15, *) {
                srcDestScreens += ", srcScreen: \(usableScreens.currentScreen.localizedName)"
                srcDestScreens += ", destScreen: \(calcResult.screen.localizedName)"
                if let resultScreens = screenDetection.detectScreens(using: frontmostWindowElement) {
                    srcDestScreens += ", resultScreen: \(resultScreens.currentScreen.localizedName)"
                }
            }
            
            Logger.log("\(action.name) | display: \(visibleFrameOfDestinationScreen.debugDescription), calculatedRect: \(newRect.debugDescription), resultRect: \(resultingRect.debugDescription)\(srcDestScreens)")
        }
    }
}

struct RectangleAction {
    let action: WindowAction
    let subAction: SubWindowAction?
    let rect: CGRect
    let count: Int
}

struct ExecutionParameters {
    let action: WindowAction
    let updateRestoreRect: Bool
    let screen: NSScreen?
    
    init(_ action: WindowAction, updateRestoreRect: Bool = true, screen: NSScreen? = nil) {
        self.action = action
        self.updateRestoreRect = updateRestoreRect
        self.screen = screen
    }
}
