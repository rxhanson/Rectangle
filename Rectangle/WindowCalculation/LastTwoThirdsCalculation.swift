//
//  RightTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LastTwoThirdsCalculation: WindowCalculation, OrientationAware {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
            let last = params.lastAction, let lastSubAction = last.subAction else {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        if lastSubAction == .rightTwoThirds || lastSubAction == .bottomTwoThirds {
            return WindowCalculationFactory.firstTwoThirdsCalculation.orientationBasedRect(visibleFrameOfScreen)
        }
        
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = ((visibleFrameOfScreen.width / 3.0) * 1.4) / 2
        rect.origin.x = visibleFrameOfScreen.minX + floor(visibleFrameOfScreen.width / 3.0) - floor((visibleFrameOfScreen.width / 3.0) * 0.2) + rect.size.width
        rect.origin.y = visibleFrameOfScreen.minY
        rect.size.height = visibleFrameOfScreen.height
        return RectResult(rect, subAction: .rightTwoThirds)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
        return RectResult(rect, subAction: .bottomTwoThirds)
    }
}

