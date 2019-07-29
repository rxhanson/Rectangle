//
//  HorizCenterThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterThirdCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfDestinationScreen)
            ? horizontallyCenteredThird(visibleFrameOfDestinationScreen)
            : verticallyCenteredThird(visibleFrameOfDestinationScreen)
    }
    
    private func horizontallyCenteredThird(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var centerThirdRect = visibleFrameOfDestinationScreen
        centerThirdRect.origin.x = visibleFrameOfDestinationScreen.minX + floor(visibleFrameOfDestinationScreen.width / 3.0)
        centerThirdRect.origin.y = visibleFrameOfDestinationScreen.minY
        centerThirdRect.size.width = visibleFrameOfDestinationScreen.width / 3.0
        centerThirdRect.size.height = visibleFrameOfDestinationScreen.height
        return centerThirdRect
    }
    
    private func verticallyCenteredThird(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var centerThirdRect = visibleFrameOfDestinationScreen
        centerThirdRect.origin.x = visibleFrameOfDestinationScreen.minX
        centerThirdRect.origin.y = visibleFrameOfDestinationScreen.minY + floor(visibleFrameOfDestinationScreen.height / 3.0)
        centerThirdRect.size.width = visibleFrameOfDestinationScreen.width
        centerThirdRect.size.height = visibleFrameOfDestinationScreen.height / 3.0
        return centerThirdRect
    }
}

