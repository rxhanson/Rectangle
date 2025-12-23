//
//  BottomVerticalThirdCalculation.swift
//  Rectangle
//
//  Created on 12/22/25.
//

import Foundation

class BottomVerticalThirdCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction, let lastSubAction = last.subAction else {
            return calculateBottomThird(visibleFrameOfScreen)
        }
        
        var calculation: WindowCalculation?
        
        if last.action == .bottomVerticalThird {
            if lastSubAction == .bottomThird {
                calculation = WindowCalculationFactory.middleVerticalThirdCalculation
            }
        } else if last.action == .topVerticalThird {
            if lastSubAction == .bottomThird {
                calculation = WindowCalculationFactory.middleVerticalThirdCalculation
            }
        }
        
        if let calculation = calculation {
            return calculation.calculateRect(params)
        }
        
        return calculateBottomThird(visibleFrameOfScreen)
    }
    
    func calculateBottomThird(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY
        return RectResult(rect, subAction: .bottomThird)
    }
}
