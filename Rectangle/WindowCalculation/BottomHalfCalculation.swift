/// BottomHalfCalculation.swift

import Foundation

class BottomHalfCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.halvesPreserveOtherAxisSize.enabled, let tiledRect = HalvesPreserveOtherAxisSize.rect(for: params) {
            return tiledRect
        }

        if Defaults.subsequentExecutionMode.value == .switchSides {
            // Repeating Bottom Half while the window still sits on the bottom half moves it to the top
            // half; see LeftRightHalfCalculation.calculateSwitchSides.
            guard isRepeatedCommand(params) else { return calculateFirstRect(params) }
            let opposite = RectCalculationParameters(window: params.window, visibleFrameOfScreen: params.visibleFrameOfScreen,
                                                     action: .topHalf, lastAction: params.lastAction)
            return RectResult(WindowCalculationFactory.topHalfCalculation.calculateFirstRect(opposite).rect, resultingAction: .topHalf)
        }

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
