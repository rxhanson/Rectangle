//
//  MiddleVerticalThirdCalculation.swift
//  Rectangle
//
//  Created on 12/22/25.
//

import Foundation

class MiddleVerticalThirdCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction, let lastSubAction = last.subAction else {
            return calculateMiddleThird(visibleFrameOfScreen)
        }
        
        var calculation: WindowCalculation?
        
        if last.action == .middleVerticalThird {
            if lastSubAction == .centerVerticalThird {
                calculation = WindowCalculationFactory.topVerticalThirdCalculation
            } else if lastSubAction == .topThird {
                calculation = WindowCalculationFactory.bottomVerticalThirdCalculation
            }
        }
        
        if let calculation = calculation {
            return calculation.calculateRect(params)
        }
        
        return calculateMiddleThird(visibleFrameOfScreen)
    }
    
    func calculateMiddleThird(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX
        rect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 3.0)
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = visibleFrameOfScreen.height / 3.0
        return RectResult(rect, subAction: .centerVerticalThird)
    }
}
