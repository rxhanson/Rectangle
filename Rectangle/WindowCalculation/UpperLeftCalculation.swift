//
//  UpperLeftCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class UpperLeftCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        var oneQuarterRect = visibleFrameOfScreen
        oneQuarterRect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        oneQuarterRect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        oneQuarterRect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 2.0) + (visibleFrameOfScreen.height.truncatingRemainder(dividingBy: 2.0))

        if Defaults.subsequentExecutionMode == .resize {
            if abs(windowRect.midY - oneQuarterRect.midY) <= 1.0 {
                var twoThirdRect = oneQuarterRect
                twoThirdRect.size.width = floor(visibleFrameOfScreen.width * 2 / 3.0)
                if rectCenteredWithinRect(oneQuarterRect, windowRect) {
                    return twoThirdRect
                }
                if rectCenteredWithinRect(twoThirdRect, windowRect) {
                    var oneThirdsRect = oneQuarterRect
                    oneThirdsRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
                    return oneThirdsRect
                }
            }
        }

        return oneQuarterRect
    }
    
    
}
