/// UpperRightCalculation.swift

import Foundation

class UpperRightCalculation: WindowCalculation, CornerCycleExpansionCalculation, QuartersRepeated {
    
    let horizontalSide: HalfSplitSide = .trailing
    let verticalSide: HalfSplitSide = .leading
    var horizontalSplitFraction: Float { 1.0 - Defaults.horizontalSplitRatio.value / 100.0 }
    var verticalSplitFraction: Float { Defaults.verticalSplitRatio.value / 100.0 }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.subsequentExecutionMode.cyclesQuadrantPositions {
            if let last = params.lastAction,
               let lastSubAction = last.subAction,
               last.action == .topRight || lastSubAction == .topRightQuarter {
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
                                     horizontalFraction: horizontalSplitFraction,
                                     verticalFraction: verticalSplitFraction),
                          subAction: .topRightQuarter)
    }

    private func cornerRect(_ visibleFrameOfScreen: CGRect, horizontalFraction: Float, verticalFraction: Float) -> CGRect {
        HalfSplitFrameCalculation.cornerRect(in: visibleFrameOfScreen,
                                             horizontalSide: horizontalSide,
                                             verticalSide: verticalSide,
                                             horizontalFraction: horizontalFraction,
                                             verticalFraction: verticalFraction)
    }
}
