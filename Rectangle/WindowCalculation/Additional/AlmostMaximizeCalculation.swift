//
//  AlmostMaximizeCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class AlmostMaximizeCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {

        var calculatedWindowRect = visibleFrameOfDestinationScreen
        
        // Resize
        calculatedWindowRect.size.width = visibleFrameOfDestinationScreen.width * 0.9
        calculatedWindowRect.size.height = visibleFrameOfDestinationScreen.height * 0.9
        
        // Center
        calculatedWindowRect.origin.x = round((visibleFrameOfDestinationScreen.width - windowRect.width) / 2.0) + visibleFrameOfDestinationScreen.minX
        calculatedWindowRect.origin.y = round((visibleFrameOfDestinationScreen.height - windowRect.height) / 2.0) + visibleFrameOfDestinationScreen.minY
        
        return calculatedWindowRect
    }
    
}

