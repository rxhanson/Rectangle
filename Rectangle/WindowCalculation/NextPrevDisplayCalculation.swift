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
            let oldRectParams = params.asRectParams(visibleFrame: usableScreens.currentScreen.adjustedVisibleFrame)
            let rectParams = params.asRectParams(visibleFrame: screen.adjustedVisibleFrame)
            
            let existingPositionCalculation = getExistingPositionCalculation(oldRectParams: oldRectParams, newRectParams: rectParams)
            
            if existingPositionCalculation != nil {
                return WindowCalculationResult(rect: existingPositionCalculation!.rect, screen: screen, resultingAction: params.action)
            }
            
            let rectResult = calculateRect(rectParams)
            return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: params.action)
        }
        
        return nil
    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        if !Defaults.retainSizeNextPrevDisplay.userEnabled,
           params.lastAction?.action == .maximize {
            return WindowCalculationFactory.maximizeCalculation.calculateRect(params)
        }
        
        return WindowCalculationFactory.centerCalculation.calculateRect(params)
    }


    private func getExistingPositionCalculation(oldRectParams: RectCalculationParameters, newRectParams: RectCalculationParameters) -> RectResult? {
        for action in WindowAction.positionalActions {
            let oldCalculationParams = RectCalculationParameters(
                    window: oldRectParams.window,
                    visibleFrameOfScreen: oldRectParams.visibleFrameOfScreen,
                    action: action,
                    lastAction: oldRectParams.lastAction)
            let oldCalculation = WindowCalculationFactory.calculationsByAction[action]!.calculateRect(oldCalculationParams)
            if (closeEnough(thisRect: oldRectParams.window.rect, thatRect: oldCalculation.rect)) {
                let newCalculationParams = RectCalculationParameters(
                        window: newRectParams.window,
                        visibleFrameOfScreen: newRectParams.visibleFrameOfScreen,
                        action: action,
                        lastAction: newRectParams.lastAction)
                return WindowCalculationFactory.calculationsByAction[action]?.calculateRect(newCalculationParams)
            }
        }
        return nil
    }

    private func closeEnough(thisRect: CGRect, thatRect: CGRect) -> Bool {
        if thisRect.equalTo(thatRect) {
            return true
        }
        return closeEnough(thisCGFloat: thisRect.origin.x, thatCGFloat: thatRect.origin.x) &&
                closeEnough(thisCGFloat: thisRect.origin.y, thatCGFloat: thatRect.origin.y) &&
                closeEnough(thisCGFloat: thisRect.width, thatCGFloat: thatRect.width) &&
                closeEnough(thisCGFloat: thisRect.height, thatCGFloat: thatRect.height)
    }

    private func closeEnough(thisCGFloat: CGFloat, thatCGFloat: CGFloat) -> Bool {
        abs(thisCGFloat - thatCGFloat) <= 1
    }

}
