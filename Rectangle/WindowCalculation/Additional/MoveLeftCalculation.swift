//
//  MoveLeftCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MoveLeftCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var calculatedWindowRect = windowRect
        calculatedWindowRect.origin.x = visibleFrameOfDestinationScreen.minX
        
        if windowRect.height >= visibleFrameOfDestinationScreen.height {
            calculatedWindowRect.size.height = visibleFrameOfDestinationScreen.height
            calculatedWindowRect.origin.y = visibleFrameOfDestinationScreen.minY
        } else {
            calculatedWindowRect.origin.y = round((visibleFrameOfDestinationScreen.height - windowRect.height) / 2.0) + visibleFrameOfDestinationScreen.minY
        }
        return calculatedWindowRect
    }
    
}

