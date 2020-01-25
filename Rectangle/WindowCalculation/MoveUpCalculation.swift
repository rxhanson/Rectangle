//
//  MoveUpCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveUpCalculation: WindowCalculation {
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        var calculatedWindowRect = window.rect
        calculatedWindowRect.origin.y = visibleFrameOfScreen.maxY - window.rect.height
        
        if window.rect.width >= visibleFrameOfScreen.width {
            calculatedWindowRect.size.width = visibleFrameOfScreen.width
            calculatedWindowRect.origin.x = visibleFrameOfScreen.minX
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - window.rect.width) / 2.0) + visibleFrameOfScreen.minX
        }
        return RectResult(calculatedWindowRect)

    }
    
}

