//
//  CenterProminentlyCalculation.swift
//  Rectangle
//
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterProminentlyCalculation: WindowCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        
        var screenFrame: CGRect?
        if !Defaults.alwaysAccountForStage.userEnabled {
            screenFrame = params.usableScreens.currentScreen.adjustedVisibleFrame(params.ignoreTodo, true)
        }
                
        let rectResult = calculateRect(params.asRectParams(visibleFrame: screenFrame))
        
        let resultingAction: WindowAction = rectResult.resultingAction ?? params.action

        return WindowCalculationResult(rect: rectResult.rect,
                                       screen: params.usableScreens.currentScreen,
                                       resultingAction: resultingAction,
                                       resultingScreenFrame: screenFrame)
    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let rectResult = WindowCalculationFactory.centerCalculation.calculateRect(params)
        var rect = rectResult.rect
        rect.origin.y += -0.25 * rect.height + 0.25 * params.visibleFrameOfScreen.height
        return RectResult(rect, resultingAction: rectResult.resultingAction)

    }
    
}
