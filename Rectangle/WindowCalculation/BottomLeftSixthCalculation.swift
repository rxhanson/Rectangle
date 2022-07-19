//
//  BottomLeftSixthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomLeftSixthCalculation: WindowCalculation, OrientationAware, SixthsRepeated {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        if last.action != .bottomLeftSixth
            && lastSubAction != .bottomLeftSixthLandscape
            && lastSubAction != .bottomLeftSixthPortrait {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        if let calculation = self.nextCalculation(subAction: lastSubAction, direction: .right) {
            return calculation(visibleFrameOfScreen)
        }

        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        // TODO: Find a cleaner solution instead of the +10px workaround for gaps between windows
        rect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.origin.y + 10
        rect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.origin.x
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.size.width = floor((visibleFrameOfScreen.width / 3.0) * 0.8)
        return RectResult(rect, subAction: .topLeftSixthLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        return RectResult(rect, subAction: .bottomLeftSixthPortrait)
    }
}
