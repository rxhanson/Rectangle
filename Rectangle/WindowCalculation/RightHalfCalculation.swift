//
//  RightHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class RightHalfCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfDestinationScreen
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        oneHalfRect.origin.x += oneHalfRect.size.width
        
        if Defaults.subsequentExecutionMode == .resize {
            if abs(windowRect.midY - oneHalfRect.midY) <= 1.0 {
                
                var twoThirdsRect = visibleFrameOfDestinationScreen
                twoThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
                twoThirdsRect.origin.x = visibleFrameOfDestinationScreen.minX + visibleFrameOfDestinationScreen.width - twoThirdsRect.width

                if rectCenteredWithinRect(oneHalfRect, windowRect) {
                    return twoThirdsRect
                }
                
                if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                    var oneThirdRect = visibleFrameOfDestinationScreen
                    oneThirdRect.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
                    oneThirdRect.origin.x = visibleFrameOfDestinationScreen.origin.x + visibleFrameOfDestinationScreen.width - oneThirdRect.width
                    return oneThirdRect
                }
            }
        }
        
        return oneHalfRect
    }
    
}
