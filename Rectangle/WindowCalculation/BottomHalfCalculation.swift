//
//  BottomHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomHalfCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.height = floor(oneHalfRect.height / 2.0)
        
        if Defaults.subsequentExecutionMode == .resize {
            if abs(windowRect.midX - oneHalfRect.midX) <= 1.0 {
                var twoThirdsRect = oneHalfRect
                twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
                
                if rectCenteredWithinRect(oneHalfRect, windowRect) {
                    return twoThirdsRect
                }
                
                if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                    var oneThirdRect = oneHalfRect
                    oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
                    return oneThirdRect
                }
            }
        }
        
        return oneHalfRect
    }
}
