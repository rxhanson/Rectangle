//
//  RightHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class RightHalfCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        oneHalfRect.origin.x += oneHalfRect.size.width
        
        if Defaults.subsequentExecutionMode == .resize {
            if abs(windowRect.midY - oneHalfRect.midY) <= 1.0 {
                
                var twoThirdsRect = visibleFrameOfScreen
                twoThirdsRect.size.width = floor(visibleFrameOfScreen.width * 2 / 3.0)
                twoThirdsRect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width - twoThirdsRect.width

                if rectCenteredWithinRect(oneHalfRect, windowRect) {
                    return twoThirdsRect
                }
                
                if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                    var oneThirdRect = visibleFrameOfScreen
                    oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
                    oneThirdRect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - oneThirdRect.width
                    return oneThirdRect
                }
            }
        }
        
        return oneHalfRect
    }
    
}
