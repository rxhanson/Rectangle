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
        
        if !Defaults.strictWindowActions.enabled {
            if abs(windowRect.midY - oneHalfRect.midY) <= 1.0 {
                
                var twoThirdRect = visibleFrameOfDestinationScreen
                twoThirdRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
                twoThirdRect.origin.x = floor(visibleFrameOfDestinationScreen.width / 3.0)

                if rectCenteredWithinRect(oneHalfRect, windowRect) {
                    return twoThirdRect
                }
                
                if rectCenteredWithinRect(twoThirdRect, windowRect) {
                    var oneThirdsRect = visibleFrameOfDestinationScreen
                    oneThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
                    oneThirdsRect.origin.x = visibleFrameOfDestinationScreen.origin.x + visibleFrameOfDestinationScreen.width - oneThirdsRect.width
                    return oneThirdsRect
                }
            }
        }
        
        return oneHalfRect
    }
    
}
