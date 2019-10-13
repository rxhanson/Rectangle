//
//  TopHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class TopHalfCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.height = floor(oneHalfRect.height / 2.0)
        oneHalfRect.origin.y += oneHalfRect.height + (visibleFrameOfScreen.height.truncatingRemainder(dividingBy: 2.0))

        if Defaults.subsequentExecutionMode.value == .none {
            return oneHalfRect
        }
        
        let count = (lastAction?.action == action) ? (lastAction?.count ?? 0) : 0
        let position = count % 3
        
        switch (position) {
            case 2:
                var oneThirdRect = oneHalfRect
                oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
                oneThirdRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - oneThirdRect.height
                return oneThirdRect
            
            case 1:
                var twoThirdsRect = oneHalfRect
                twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
                twoThirdsRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - twoThirdsRect.height
                return twoThirdsRect
            
            default:
                return oneHalfRect
        }
    }
    
}
