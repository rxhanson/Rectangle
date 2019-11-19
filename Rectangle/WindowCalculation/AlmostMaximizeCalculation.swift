//
//  AlmostMaximizeCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class AlmostMaximizeCalculation: WindowCalculation {
    
    let almostMaximizeRatio: CGFloat
        
    init() {
        let defaultRatio = Defaults.almostMaximizeRatio.value
        almostMaximizeRatio = (defaultRatio <= 0 || defaultRatio > 1)
            ? 0.9
            : CGFloat(defaultRatio)
    }
    
    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {

        var calculatedWindowRect = visibleFrameOfScreen
        
        // Resize
        calculatedWindowRect.size.width = visibleFrameOfScreen.width * almostMaximizeRatio
        calculatedWindowRect.size.height = visibleFrameOfScreen.height * almostMaximizeRatio
        
        // Center
        calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - calculatedWindowRect.width) / 2.0) + visibleFrameOfScreen.minX
        calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - calculatedWindowRect.height) / 2.0) + visibleFrameOfScreen.minY
        
        return calculatedWindowRect
    }
    
}

