//
//  TopHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class TopHalfCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfDestinationScreen
        oneHalfRect.size.height = floor(oneHalfRect.height / 2.0)
        oneHalfRect.origin.y += oneHalfRect.height + (visibleFrameOfDestinationScreen.height.truncatingRemainder(dividingBy: 2.0))

        if !Defaults.strictWindowActions.enabled {
            if abs(windowRect.midX - oneHalfRect.midX) <= 1.0 {
                var twoThirdsRect = oneHalfRect
                twoThirdsRect.size.height = floor(visibleFrameOfDestinationScreen.height * 2 / 3.0)
                twoThirdsRect.origin.y = visibleFrameOfDestinationScreen.origin.y + visibleFrameOfDestinationScreen.height - twoThirdsRect.height
                if rectCenteredWithinRect(oneHalfRect, windowRect) {
                    return twoThirdsRect
                }
                if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                    var oneThirdRect = oneHalfRect
                    oneThirdRect.size.height = floor(visibleFrameOfDestinationScreen.height / 3.0)
                    oneThirdRect.origin.y = visibleFrameOfDestinationScreen.origin.y + visibleFrameOfDestinationScreen.height - oneThirdRect.height
                    return oneThirdRect
                }
            }
        }
        
        return oneHalfRect
        
    }
    
}
