/// MaximizeCalculation.swift

import Foundation

class MaximizeCalculation: WindowCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        return RectResult(visibleFrameOfScreen)
    }
    
}
