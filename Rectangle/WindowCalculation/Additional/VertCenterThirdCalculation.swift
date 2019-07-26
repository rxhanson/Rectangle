//
//  VertCenterThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class VertCenterThirdCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var centerThirdRect = visibleFrameOfDestinationScreen
        centerThirdRect.origin.x = visibleFrameOfDestinationScreen.minX
        centerThirdRect.origin.y = visibleFrameOfDestinationScreen.minY + floor(visibleFrameOfDestinationScreen.height / 3.0)
        centerThirdRect.size.width = visibleFrameOfDestinationScreen.width
        centerThirdRect.size.height = visibleFrameOfDestinationScreen.height / 3.0
        return centerThirdRect
    }
    
}

