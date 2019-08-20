//
//  UpperLeftCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class UpperLeftCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var oneQuarterRect = visibleFrameOfDestinationScreen
        oneQuarterRect.size.width = floor(visibleFrameOfDestinationScreen.width / 2.0)
        oneQuarterRect.size.height = floor(visibleFrameOfDestinationScreen.height / 2.0)
        oneQuarterRect.origin.y = visibleFrameOfDestinationScreen.minY + floor(visibleFrameOfDestinationScreen.height / 2.0) + (visibleFrameOfDestinationScreen.height.truncatingRemainder(dividingBy: 2.0))

        if Defaults.subsequentExecutionMode == .resize {
            if abs(windowRect.midY - oneQuarterRect.midY) <= 1.0 {
                var twoThirdRect = oneQuarterRect
                twoThirdRect.size.width = floor(visibleFrameOfDestinationScreen.width * 2 / 3.0)
                if rectCenteredWithinRect(oneQuarterRect, windowRect) {
                    return twoThirdRect
                }
                if rectCenteredWithinRect(twoThirdRect, windowRect) {
                    var oneThirdsRect = oneQuarterRect
                    oneThirdsRect.size.width = floor(visibleFrameOfDestinationScreen.width / 3.0)
                    return oneThirdsRect
                }
            }
        }

        return oneQuarterRect
    }
    
    
}
