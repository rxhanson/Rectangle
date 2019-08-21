//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstThirdCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return isLandscape(visibleFrameOfScreen)
            ? leftThird(visibleFrameOfScreen)
            : topThird(visibleFrameOfScreen)
    }
    
    private func leftThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        return oneThirdRect
    }
    
    private func topThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        oneThirdRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - oneThirdRect.height
        return oneThirdRect
    }
    
}
