/// MiddleVerticalThirdCalculation.swift

import Foundation

class MiddleVerticalThirdCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
            let visibleFrameOfScreen = params.visibleFrameOfScreen
            return calculateMiddleThird(visibleFrameOfScreen)
        }
        
        func calculateMiddleThird(_ visibleFrameOfScreen: CGRect) -> RectResult {
            var rect = visibleFrameOfScreen
            let thirdHeight = floor(visibleFrameOfScreen.height / 3.0)
            rect.origin.x = visibleFrameOfScreen.minX
            rect.origin.y = visibleFrameOfScreen.minY + thirdHeight
            rect.size.width = visibleFrameOfScreen.width
            rect.size.height = visibleFrameOfScreen.height - thirdHeight * 2
            return RectResult(rect, subAction: .centerVerticalThird)
        }
}
