//
//  AlmostMaximizeCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class AlmostMaximizeCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {

        var calculatedWindowRect = visibleFrameOfScreen
        
        // Resize
        calculatedWindowRect.size.width = visibleFrameOfScreen.width * 0.9
        calculatedWindowRect.size.height = visibleFrameOfScreen.height * 0.9
        
        // Center
        calculatedWindowRect.origin.x = round((visibleFrameOfScreen.width - calculatedWindowRect.width) / 2.0) + visibleFrameOfScreen.minX
        calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - calculatedWindowRect.height) / 2.0) + visibleFrameOfScreen.minY
        
        return calculatedWindowRect
    }
    
}

