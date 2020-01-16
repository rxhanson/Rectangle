//
//  MoveUpCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveUpCalculation: WindowCalculation {
    
    override func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        var calculatedWindowRect = windowRect
        calculatedWindowRect.origin.y = visibleFrameOfScreen.maxY - windowRect.height
        
        if windowRect.width >= visibleFrameOfScreen.width {
            calculatedWindowRect.size.width = visibleFrameOfScreen.width
            calculatedWindowRect.origin.x = visibleFrameOfScreen.minX
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - windowRect.width) / 2.0) + visibleFrameOfScreen.minX
        }
        return RectResult(calculatedWindowRect)

    }
    
}

