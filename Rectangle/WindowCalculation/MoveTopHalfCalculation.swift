//
//  MoveTopHalfCalculation.swift
//  Rectangle
//
//  Created by Charlie Harding on 12/05/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveTopHalfCalculation: WindowCalculation, GapCounteractionCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        let windowRectWithGaps = counteractHorizontalGaps(params.window.rect, visibleFrameOfScreen)
        
        var calculatedWindowRect = windowRectWithGaps
            
        calculatedWindowRect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        calculatedWindowRect.origin.y = visibleFrameOfScreen.maxY - calculatedWindowRect.size.height
        
        if calculatedWindowRect == windowRectWithGaps {
            calculatedWindowRect.origin.y = visibleFrameOfScreen.minY
        }
        
        return RectResult(calculatedWindowRect)

    }
    
}
