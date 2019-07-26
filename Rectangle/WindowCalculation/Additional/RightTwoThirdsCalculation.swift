//
//  RightTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class RightTwoThirdsCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
        twoThirdsRect.origin.x = visibleFrameOfDestinationScreen.minX + visibleFrameOfDestinationScreen.width - twoThirdsRect.width
        
        return twoThirdsRect
    }
    
}

