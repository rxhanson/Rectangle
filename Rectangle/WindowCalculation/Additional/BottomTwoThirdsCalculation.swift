//
//  BottomTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomTwoThirdsCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var twoThirdsRect = visibleFrameOfDestinationScreen
        twoThirdsRect.size.height = floor(visibleFrameOfDestinationScreen.height * 2 / 3.0)
        return twoThirdsRect
    }
    
}

