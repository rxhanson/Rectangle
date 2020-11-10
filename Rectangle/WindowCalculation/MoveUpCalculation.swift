//
//  MoveUpCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveUpCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var calculatedWindowRect = params.window.rect
        calculatedWindowRect.origin.y = visibleFrameOfScreen.maxY - params.window.rect.height
        
        if params.window.rect.width >= visibleFrameOfScreen.width {
            calculatedWindowRect.size.width = visibleFrameOfScreen.width
            calculatedWindowRect.origin.x = visibleFrameOfScreen.minX
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - params.window.rect.width) / 2.0) + visibleFrameOfScreen.minX
        }
        return RectResult(calculatedWindowRect)

    }
    
}

