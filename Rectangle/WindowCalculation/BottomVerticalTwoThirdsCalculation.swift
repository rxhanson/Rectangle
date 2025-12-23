//
//  BottomVerticalTwoThirdsCalculation.swift
//  Rectangle
//
//  Created on 12/22/25.
//

import Foundation

class BottomVerticalTwoThirdsCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction, let lastSubAction = last.subAction else {
            return calculateBottomTwoThirds(visibleFrameOfScreen)
        }

        if lastSubAction == .bottomTwoThirds {
            return WindowCalculationFactory.topVerticalTwoThirdsCalculation.calculateRect(params)
        }
        
        return calculateBottomTwoThirds(visibleFrameOfScreen)
    }
    
    func calculateBottomTwoThirds(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY
        return RectResult(rect, subAction: .bottomTwoThirds)
    }
}
