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
