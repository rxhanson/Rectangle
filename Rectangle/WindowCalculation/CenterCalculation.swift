//
//  CenterCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterCalculation: WindowCalculation {
    
    override func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {

        if rectFitsWithinRect(rect1: windowRect, rect2: visibleFrameOfScreen) {
            var calculatedWindowRect = windowRect
            calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - windowRect.width) / 2.0) + visibleFrameOfScreen.minX
            calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - windowRect.height) / 2.0) + visibleFrameOfScreen.minY
            return calculatedWindowRect
        } else {
            return visibleFrameOfScreen
        }

    }
    
}
