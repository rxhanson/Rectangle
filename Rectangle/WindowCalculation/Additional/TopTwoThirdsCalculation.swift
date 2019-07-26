//
//  TopTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class TopTwoThirdsCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.height = floor(visibleFrameOfDestinationScreen.height * 2 / 3.0)
        twoThirdsRect.origin.y = visibleFrameOfDestinationScreen.origin.y + visibleFrameOfDestinationScreen.height - twoThirdsRect.height
        return twoThirdsRect
    }
    
}

