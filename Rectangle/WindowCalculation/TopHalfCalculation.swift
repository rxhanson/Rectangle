/// TopHalfCalculation.swift

import Foundation

class TopHalfCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.halvesPreserveOtherAxisSize.enabled, let tiledRect = HalvesPreserveOtherAxisSize.rect(for: params) {
            return tiledRect
        }

        if Defaults.subsequentExecutionMode.value == .switchSides {
            // Repeating Top Half while the window still sits on the top half moves it to the bottom
            // half; see LeftRightHalfCalculation.calculateSwitchSides.
            guard isRepeatedCommand(params) else { return calculateFirstRect(params) }
            let opposite = RectCalculationParameters(window: params.window, visibleFrameOfScreen: params.visibleFrameOfScreen,
                                                     action: .bottomHalf, lastAction: params.lastAction)
            return RectResult(WindowCalculationFactory.bottomHalfCalculation.calculateFirstRect(opposite).rect, resultingAction: .bottomHalf)
        }

        if params.lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(params)
        }
        
        return calculateRepeatedSideRect(params)
    }
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        return RectResult(HalfSplitFrameCalculation.verticalRect(in: params.visibleFrameOfScreen,
                                                                 side: .leading,
                                                                 fraction: ActiveSideSplitRatios.shared.verticalRatio(for: params.visibleFrameOfScreen)))
    }

    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        return RectResult(HalfSplitFrameCalculation.verticalRect(in: params.visibleFrameOfScreen, side: .leading, fraction: fraction))
    }

    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        calculateRepeatedSideRect(params)
    }
    
}
