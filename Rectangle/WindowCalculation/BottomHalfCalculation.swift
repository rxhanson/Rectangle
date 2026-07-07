/// BottomHalfCalculation.swift

import Foundation

class BottomHalfCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if params.lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(params)
        }
        
        return calculateRepeatedSideRect(params)
    }
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        return RectResult(HalfSplitFrameCalculation.verticalRect(in: params.visibleFrameOfScreen,
                                                                 side: .trailing,
                                                                 fraction: 1.0 - ActiveSideSplitRatios.shared.verticalRatio(for: params.visibleFrameOfScreen)))
    }

    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        return RectResult(HalfSplitFrameCalculation.verticalRect(in: params.visibleFrameOfScreen, side: .trailing, fraction: fraction))
    }

    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        calculateRepeatedSideRect(params)
    }
    
}
