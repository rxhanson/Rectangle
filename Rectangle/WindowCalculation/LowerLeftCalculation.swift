/// LowerLeftCalculation.swift

import Foundation

class LowerLeftCalculation: WindowCalculation, CornerCycleExpansionCalculation, QuartersRepeated {
    
    let horizontalSide: HalfSplitSide = .leading
    let verticalSide: HalfSplitSide = .trailing

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.subsequentExecutionMode.cyclesQuadrantPositions {
            if let last = params.lastAction,
               let lastSubAction = last.subAction,
               last.action == .bottomLeft || lastSubAction == .bottomLeftQuarter {
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
                          subAction: .bottomLeftQuarter)
    }

    func quarterRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        quarterRect(RectCalculationParameters(window: Window(id: 0, rect: visibleFrameOfScreen),
                                              visibleFrameOfScreen: visibleFrameOfScreen,
                                              action: .bottomLeft,
                                              lastAction: nil))
    }
}
