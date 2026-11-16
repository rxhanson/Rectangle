/// TopHalfCalculation.swift

import Foundation

class TopHalfCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation {

    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        calculateAcrossVerticalDisplays(params) ?? super.calculate(params)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.halvesPreserveOtherAxisSize.enabled, let tiledRect = HalvesPreserveOtherAxisSize.rect(for: params) {
            return tiledRect
        }

        if Defaults.subsequentExecutionMode.value == .switchSides {
            // Repeating Top Half while the window still sits on the top half moves it to the bottom
            // half; see LeftRightHalfCalculation.calculateSwitchSides.
            return isRepeatedCommand(params) ? facingVerticalHalf(params) : calculateFirstRect(params)
        }

        if params.lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(params)
        }
        
        return calculateRepeatedRect(params)
    }
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        return RectResult(HalfSplitFrameCalculation.verticalRect(in: params.visibleFrameOfScreen,
                                                                 side: .leading,
                                                                 fraction: ActiveSideSplitRatios.shared.verticalRatio(for: params.visibleFrameOfScreen)))
    }

    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        return RectResult(HalfSplitFrameCalculation.verticalRect(in: params.visibleFrameOfScreen, side: .leading, fraction: fraction))
    }

}
