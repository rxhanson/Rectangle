//
//  LeftTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstTwoThirdsCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfDestinationScreen)
            ? leftTwoThirds(visibleFrameOfDestinationScreen)
            : topTwoThirds(visibleFrameOfDestinationScreen)
    }
    
    private func leftTwoThirds(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
        return twoThirdsRect
    }
    
    private func topTwoThirds(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.height = floor(visibleFrameOfDestinationScreen.height * 2 / 3.0)
        twoThirdsRect.origin.y = visibleFrameOfDestinationScreen.origin.y + visibleFrameOfDestinationScreen.height - twoThirdsRect.height
        return twoThirdsRect
    }
}

