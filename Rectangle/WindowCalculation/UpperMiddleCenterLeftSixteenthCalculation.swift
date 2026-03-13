//
//  UpperMiddleCenterLeftSixteenthCalculation.swift
//  Rectangle
//
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

class UpperMiddleCenterLeftSixteenthCalculation: WindowCalculation, OrientationAware, SixteenthsRepeated {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        if last.action != .upperMiddleCenterLeftSixteenth {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
            return calculation(visibleFrameOfScreen)
        }

        return orientationBasedRect(visibleFrameOfScreen)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height * 2
        rect.origin.x = visibleFrameOfScreen.minX + rect.width
        return RectResult(rect, subAction: .upperMiddleCenterLeftSixteenth)
    }

    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height * 2
        rect.origin.x = visibleFrameOfScreen.minX + rect.width
        return RectResult(rect, subAction: .upperMiddleCenterLeftSixteenth)
    }
}
