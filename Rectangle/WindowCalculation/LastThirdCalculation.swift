//
//  RightThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LastThirdCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfDestinationScreen)
            ? rightThird(visibleFrameOfDestinationScreen)
            : bottomThird(visibleFrameOfDestinationScreen)
    }
    
    private func rightThird(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        
        var oneThirdRect = visibleFrameOfDestinationScreen
        oneThirdRect.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
        oneThirdRect.origin.x = visibleFrameOfDestinationScreen.origin.x + visibleFrameOfDestinationScreen.width - oneThirdRect.width
        return oneThirdRect
    }
    
    private func bottomThird(_ visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        
        var oneThirdRect = visibleFrameOfDestinationScreen
        oneThirdRect.size.height = floor(visibleFrameOfDestinationScreen.height / 3.0)
        return oneThirdRect
    }
}
