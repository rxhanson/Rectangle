//
//  RightTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LastTwoThirdsCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfScreen)
            ? rightTwoThirds(visibleFrameOfScreen)
            : bottomTwoThirds(visibleFrameOfScreen)
    }
    
    private func rightTwoThirds(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.width = floor(visibleFrameOfScreen.width * 2 / 3.0)
        twoThirdsRect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width - twoThirdsRect.width
        return twoThirdsRect
    }
    
    private func bottomTwoThirds(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
        return twoThirdsRect
    }
}

