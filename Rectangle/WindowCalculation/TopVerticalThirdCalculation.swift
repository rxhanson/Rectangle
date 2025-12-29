//
//  TopVerticalThirdCalculation.swift
//  Rectangle
//
//  Created on 12/22/25.
//

import Foundation

class TopVerticalThirdCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction, let lastSubAction = last.subAction else {
            return calculateTopThird(visibleFrameOfScreen)
        }
        
        var calculation: WindowCalculation?
        
        if last.action == .topVerticalThird {
            if lastSubAction == .topThird {
                calculation = WindowCalculationFactory.middleVerticalThirdCalculation
            } else if lastSubAction == .centerVerticalThird {
                calculation = WindowCalculationFactory.bottomVerticalThirdCalculation
            }
        } else if last.action == .bottomVerticalThird {
            if lastSubAction == .topThird {
                calculation = WindowCalculationFactory.middleVerticalThirdCalculation
            } else if lastSubAction == .centerVerticalThird {
                calculation = WindowCalculationFactory.bottomVerticalThirdCalculation
            }
        }
        
        if let calculation = calculation {
            return calculation.calculateRect(params)
        }
        
        return calculateTopThird(visibleFrameOfScreen)
    }
    
    func calculateTopThird(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - rect.height
        return RectResult(rect, subAction: .topThird)
    }
}
