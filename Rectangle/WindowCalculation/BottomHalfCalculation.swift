//
//  BottomHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomHalfCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.height = floor(oneHalfRect.height / 2.0)
        
        if Defaults.subsequentExecutionMode.value == .none {
            return oneHalfRect
        }
        
        let count = (lastAction?.action == action) ? (lastAction?.count ?? 0) : 0
        let position = count % 3
        
        switch (position) {
            case 2:
                var oneThirdRect = oneHalfRect
                oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
                return oneThirdRect
            
            case 1:
                var twoThirdsRect = oneHalfRect
                twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
                return twoThirdsRect
            
            default:
                return oneHalfRect
        }
    }
}
