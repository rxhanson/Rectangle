//
//  TopRightSixthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class TopRightSixthCalculation: WindowCalculation, OrientationAware, SixthsRepeated {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if last.action != .topRightSixth
            && lastSubAction != .topRightSixthLandscape
            && lastSubAction != .topRightSixthPortrait {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .left) {
            return calculation(visibleFrameOfScreen)
        }

        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.minX + (rect.width * 2.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height
        return RectResult(rect, subAction: .topRightSixthLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.x = visibleFrameOfScreen.minX + rect.width
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height
        return RectResult(rect, subAction: .topRightSixthPortrait)
    }
}
