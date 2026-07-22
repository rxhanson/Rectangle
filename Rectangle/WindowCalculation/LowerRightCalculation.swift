/// LowerRightCalculation.swift

import Foundation

class LowerRightCalculation: WindowCalculation, CornerCycleExpansionCalculation, QuartersRepeated {
    
    let horizontalSide: HalfSplitSide = .trailing
    let verticalSide: HalfSplitSide = .trailing

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.subsequentExecutionMode.cyclesQuadrantPositions {
            if let last = params.lastAction,
               let lastSubAction = last.subAction,
               last.action == .bottomRight || lastSubAction == .bottomRightQuarter {
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
                          subAction: .bottomRightQuarter)
    }

    func quarterRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        quarterRect(RectCalculationParameters(window: Window(id: 0, rect: visibleFrameOfScreen),
                                              visibleFrameOfScreen: visibleFrameOfScreen,
                                              action: .bottomRight,
                                              lastAction: nil))
    }
}
