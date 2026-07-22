/// UpperRightCalculation.swift

import Foundation

class UpperRightCalculation: WindowCalculation, CornerCycleExpansionCalculation, QuartersRepeated {
    
    let horizontalSide: HalfSplitSide = .trailing
    let verticalSide: HalfSplitSide = .leading

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.subsequentExecutionMode.cyclesQuadrantPositions {
            if let last = params.lastAction,
               let lastSubAction = last.subAction,
               last.action == .topRight || lastSubAction == .topRightQuarter {
                if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
                    return calculation(params.visibleFrameOfScreen)
                }
            }
            return quarterRect(params)
        }

        if params.lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(params)
        }

        return calculateRepeatedRect(params)
    }

    func quarterRect(_ params: RectCalculationParameters) -> RectResult {
        return RectResult(cornerRect(params,
                                     horizontalFraction: horizontalSplitFraction(params),
                                     verticalFraction: verticalSplitFraction(params)),
                          subAction: .topRightQuarter)
    }

    func quarterRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        quarterRect(RectCalculationParameters(window: Window(id: 0, rect: visibleFrameOfScreen),
                                              visibleFrameOfScreen: visibleFrameOfScreen,
                                              action: .topRight,
                                              lastAction: nil))
    }
}
