/// LowerLeftCalculation.swift

import Foundation

class LowerLeftCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation, QuartersRepeated {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.subsequentExecutionMode.cyclesQuadrantPositions {
            if let last = params.lastAction,
               let lastSubAction = last.subAction,
               last.action == .bottomLeft || lastSubAction == .bottomLeftQuarter {
                if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
                    return calculation(params.visibleFrameOfScreen)
                }
            }
            return quarterRect(params.visibleFrameOfScreen)
        }

        if params.lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(params)
        }

        return calculateRepeatedRect(params)
    }

    func quarterRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        return RectResult(cornerRect(visibleFrameOfScreen,
                                     horizontalFraction: Defaults.horizontalSplitRatio.value / 100.0,
                                     verticalFraction: 1.0 - Defaults.verticalSplitRatio.value / 100.0),
                          subAction: .bottomLeftQuarter)
    }

    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        return RectResult(cornerRect(params.visibleFrameOfScreen,
                                     horizontalFraction: Defaults.horizontalSplitRatio.value / 100.0,
                                     verticalFraction: 1.0 - Defaults.verticalSplitRatio.value / 100.0))
    }

    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        return RectResult(cornerRect(params.visibleFrameOfScreen,
                                     horizontalFraction: fraction,
                                     verticalFraction: fraction))
    }

    private func cornerRect(_ visibleFrameOfScreen: CGRect, horizontalFraction: Float, verticalFraction: Float) -> CGRect {
        HalfSplitFrameCalculation.cornerRect(in: visibleFrameOfScreen,
                                             horizontalSide: .leading,
                                             verticalSide: .trailing,
                                             horizontalFraction: horizontalFraction,
                                             verticalFraction: verticalFraction)
    }
}
