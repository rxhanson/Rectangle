/// MaximizeCalculation.swift

import Foundation

class MaximizeCalculation: WindowCalculation {

    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        RepeatedMaximizeRestore.calculate(params) ?? super.calculate(params)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        return RectResult(visibleFrameOfScreen)
    }
    
}
