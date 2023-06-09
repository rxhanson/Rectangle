//
//  TopRightThirdCalculation.swift
//  Rectangle
//
//  Created by Daniel Schultz on 1/2/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class TopRightThirdCalculation: WindowCalculation, OrientationAware, HorizontalThirdsRepeated {
        
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if last.action != .topRightThird {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
            return calculation(visibleFrameOfScreen)
        }

        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(2.0 * visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height
        rect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width / 3.0
        return RectResult(rect, subAction: .topRightThird)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(2.0 * visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.maxY - visibleFrameOfScreen.height / 3.0
        rect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width / 2.0
        return RectResult(rect, subAction: .topRightThird)
    }
}
