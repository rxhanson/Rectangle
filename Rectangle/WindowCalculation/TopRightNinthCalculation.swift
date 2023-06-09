//
//  TopRightNinthCalculation.swift
//  Rectangle
//
//  Created by Daniel Schultz on 1/2/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class TopRightNinthCalculation: WindowCalculation, OrientationAware, NinthsRepeated {
        
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if last.action != .topRightNinth {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
            return calculation(visibleFrameOfScreen)
        }

        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height
        rect.origin.x = visibleFrameOfScreen.minX + (2.0 * rect.width)
        return RectResult(rect, subAction: .topRightNinth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height
        rect.origin.x = visibleFrameOfScreen.minX + (2.0 * rect.width)
        return RectResult(rect, subAction: .topRightNinth)
    }
}

