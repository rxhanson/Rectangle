//
//  LeftHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LeftHalfCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfDestinationScreen
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        
        if Defaults.subsequentExecutionMode == .resize {
            if abs(windowRect.midY - oneHalfRect.midY) <= 1.0 {
                var twoThirdsRect = oneHalfRect
                twoThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
                if rectCenteredWithinRect(oneHalfRect, windowRect) {
                    return twoThirdsRect
                }
                if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                    var oneThirdRect = oneHalfRect
                    oneThirdRect.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
                    return oneThirdRect
                }
            }
        } else if Defaults.subsequentExecutionMode == .acrossMonitor {
            
        }
        
        return oneHalfRect
    }
    
}
