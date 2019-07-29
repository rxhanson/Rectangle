//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstThirdCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfDestinationScreen)
            ? leftThird(visibleFrameOfDestinationScreen)
            : topThird(visibleFrameOfDestinationScreen)
    }
    
    private func leftThird(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfDestinationScreen
        oneThirdRect.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
        return oneThirdRect
    }
    
    private func topThird(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfDestinationScreen
        oneThirdRect.size.height = floor(visibleFrameOfDestinationScreen.height / 3.0)
        oneThirdRect.origin.y = visibleFrameOfDestinationScreen.origin.y + visibleFrameOfDestinationScreen.height - oneThirdRect.height
        return oneThirdRect
    }
    
}
