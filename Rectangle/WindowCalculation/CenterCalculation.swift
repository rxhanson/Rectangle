//
//  CenterCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterCalculation: WindowCalculation {
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {

        if rectFitsWithinRect(rect1: window.rect, rect2: visibleFrameOfScreen) {
            var calculatedWindowRect = window.rect
            calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - window.rect.width) / 2.0) + visibleFrameOfScreen.minX
            calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - window.rect.height) / 2.0) + visibleFrameOfScreen.minY
            return RectResult(calculatedWindowRect)
        } else {
            return RectResult(visibleFrameOfScreen)
        }

    }
    
}
