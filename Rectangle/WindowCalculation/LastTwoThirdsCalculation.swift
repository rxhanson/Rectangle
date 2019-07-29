//
//  RightTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LastTwoThirdsCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfDestinationScreen)
            ? rightTwoThirds(visibleFrameOfDestinationScreen)
            : bottomTwoThirds(visibleFrameOfDestinationScreen)
    }
    
    private func rightTwoThirds(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
        twoThirdsRect.origin.x = visibleFrameOfDestinationScreen.minX + visibleFrameOfDestinationScreen.width - twoThirdsRect.width
        return twoThirdsRect
    }
    
    private func bottomTwoThirds(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.height = floor(visibleFrameOfDestinationScreen.height * 2 / 3.0)
        return twoThirdsRect
    }
}

