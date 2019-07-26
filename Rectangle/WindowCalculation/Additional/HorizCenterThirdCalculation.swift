//
//  HorizCenterThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class HorizCenterThirdCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var centerThirdRect = visibleFrameOfDestinationScreen
        centerThirdRect.origin.x = visibleFrameOfDestinationScreen.minX + floor(visibleFrameOfDestinationScreen.width / 3.0)
        centerThirdRect.origin.y = visibleFrameOfDestinationScreen.minY
        centerThirdRect.size.width = visibleFrameOfDestinationScreen.width / 3.0
        centerThirdRect.size.height = visibleFrameOfDestinationScreen.height
        return centerThirdRect
    }
    
}

