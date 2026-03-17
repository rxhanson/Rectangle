//
//  LowerLeftCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LowerLeftCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation, QuartersRepeated {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return quarterRect(params.visibleFrameOfScreen)
        }

        if last.action != .bottomLeft && lastSubAction != .bottomLeftQuarter {
            return quarterRect(params.visibleFrameOfScreen)
        }

        if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
            return calculation(params.visibleFrameOfScreen)
        }

        return quarterRect(params.visibleFrameOfScreen)
    }

    func quarterRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        return RectResult(rect, subAction: .bottomLeftQuarter)
    }

    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * CGFloat(fraction))
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        return RectResult(rect)
    }
}
