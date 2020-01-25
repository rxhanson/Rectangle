//
//  LeftTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstTwoThirdsCalculation: WindowCalculation {
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(leftTwoThirds(visibleFrameOfScreen), subAction: .leftTwoThirds)
            : RectResult(topTwoThirds(visibleFrameOfScreen), subAction: .topTwoThirds)
    }
    
    private func leftTwoThirds(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.width = floor(visibleFrameOfScreen.width * 2 / 3.0)
        return twoThirdsRect
    }
    
    private func topTwoThirds(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
        twoThirdsRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - twoThirdsRect.height
        return twoThirdsRect
    }
}

