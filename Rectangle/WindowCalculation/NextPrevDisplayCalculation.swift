//
//  NextPrevDisplayCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/19/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class NextPrevDisplayCalculation: WindowCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let usableScreens = params.usableScreens
        
        guard usableScreens.numScreens > 1 else { return nil }

        var screen: NSScreen?
        
        if params.action == .nextDisplay {
            screen = usableScreens.adjacentScreens?.next
        } else if params.action == .previousDisplay {
            screen = usableScreens.adjacentScreens?.prev
        }

        if let screen = screen {
            let destFrame = screen.adjustedVisibleFrame(params.ignoreTodo)
            let rectParams = params.asRectParams(visibleFrame: destFrame)

            if Defaults.attemptMatchOnNextPrevDisplay.userEnabled {
                if let lastAction = params.lastAction,
                   let calculation = WindowCalculationFactory.calculationsByAction[lastAction.action] {

                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: params.window.id)

                    let newCalculationParams = RectCalculationParameters(
                        window: rectParams.window,
                        visibleFrameOfScreen: rectParams.visibleFrameOfScreen,
                        action: lastAction.action,
                        lastAction: nil)
                    let rectResult = calculation.calculateRect(newCalculationParams)

                    return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: lastAction.action)
                }
            }

            if params.lastAction?.action == .maximize && !Defaults.autoMaximize.userDisabled {
                let rectResult = WindowCalculationFactory.maximizeCalculation.calculateRect(rectParams)
                return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: .maximize)
            }

            let sourceFrame = usableScreens.currentScreen.adjustedVisibleFrame(params.ignoreTodo)
            let windowRect = params.window.rect

            let relativeX = (windowRect.minX - sourceFrame.minX) / sourceFrame.width
            let relativeY = (windowRect.minY - sourceFrame.minY) / sourceFrame.height

            var newRect = windowRect
            newRect.origin.x = round(destFrame.minX + relativeX * destFrame.width)
            newRect.origin.y = round(destFrame.minY + relativeY * destFrame.height)

            newRect.origin.x = max(destFrame.minX, min(newRect.origin.x, destFrame.maxX - newRect.width))
            newRect.origin.y = max(destFrame.minY, min(newRect.origin.y, destFrame.maxY - newRect.height))

            return WindowCalculationResult(rect: newRect, screen: screen, resultingAction: params.action)
        }
        
        return nil
    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        if params.lastAction?.action == .maximize && !Defaults.autoMaximize.userDisabled {
            let rectResult = WindowCalculationFactory.maximizeCalculation.calculateRect(params)
            return RectResult(rectResult.rect, resultingAction: .maximize)
        }
        
        return WindowCalculationFactory.centerCalculation.calculateRect(params)
    }
}
