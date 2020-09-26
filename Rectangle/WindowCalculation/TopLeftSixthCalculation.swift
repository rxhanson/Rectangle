//
//  TopLeftSixthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class TopLeftSixthCalculation: WindowCalculation, OrientationAware {
        
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
              let last = lastAction, let lastSubAction = last.subAction else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.y = visibleFrameOfScreen.minY + rect.height
        return RectResult(rect, subAction: .topLeftSixthLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY + (rect.height * 2.0)
        return RectResult(rect, subAction: .topLeftSixthPortrait)
    }
}
