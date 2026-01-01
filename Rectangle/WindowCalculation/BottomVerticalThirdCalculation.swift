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
        
        if last.action == .topVerticalThird || last.action == .bottomVerticalThird {
            switch lastSubAction {
            case .topThird:
                calculation = WindowCalculationFactory.middleVerticalThirdCalculation
            case .bottomThird:
                calculation = WindowCalculationFactory.topVerticalThirdCalculation
            default:
                break
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
