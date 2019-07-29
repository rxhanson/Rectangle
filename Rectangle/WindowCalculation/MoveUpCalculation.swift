//
//  MoveUpCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveUpCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var calculatedWindowRect = windowRect
        calculatedWindowRect.origin.y = visibleFrameOfDestinationScreen.maxY - windowRect.height
        
        if windowRect.width >= visibleFrameOfDestinationScreen.width {
            calculatedWindowRect.size.width = visibleFrameOfDestinationScreen.width
            calculatedWindowRect.origin.x = visibleFrameOfDestinationScreen.minX
        } else {
            calculatedWindowRect.origin.x = round((visibleFrameOfDestinationScreen.width - windowRect.width) / 2.0) + visibleFrameOfDestinationScreen.minX
        }
        return calculatedWindowRect

    }
    
}

