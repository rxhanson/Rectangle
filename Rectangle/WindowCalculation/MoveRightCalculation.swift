//
//  MoveRightCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveRightCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var calculatedWindowRect = windowRect
        calculatedWindowRect.origin.x = visibleFrameOfScreen.maxX - windowRect.width
        
        if windowRect.height >= visibleFrameOfScreen.height {
            calculatedWindowRect.size.height = visibleFrameOfScreen.height
            calculatedWindowRect.origin.y = visibleFrameOfScreen.minY
        } else {
            calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - windowRect.height) / 2.0) + visibleFrameOfScreen.minY
        }
        return calculatedWindowRect

    }
    
}

