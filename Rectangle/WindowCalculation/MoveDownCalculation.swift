//
//  MoveDownCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveDownCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var calculatedWindowRect = windowRect
        calculatedWindowRect.origin.y = visibleFrameOfScreen.minY
        
        if windowRect.width >= visibleFrameOfScreen.width {
            calculatedWindowRect.size.width = visibleFrameOfScreen.width
            calculatedWindowRect.origin.x = visibleFrameOfScreen.minX
        } else {
            calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - windowRect.width) / 2.0) + visibleFrameOfScreen.minX
        }
        return calculatedWindowRect

    }
    
}

