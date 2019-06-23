//
//  CenterCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        if rectFitsWithinRect(rect1: windowRect, rect2: visibleFrameOfDestinationScreen) {
            var calculatedWindowRect = windowRect
            calculatedWindowRect.origin.x = round((visibleFrameOfDestinationScreen.width - windowRect.width) / 2.0) + visibleFrameOfDestinationScreen.origin.x
            calculatedWindowRect.origin.y = round((visibleFrameOfDestinationScreen.height - windowRect.height) / 2.0) + visibleFrameOfDestinationScreen.origin.y
            return calculatedWindowRect
        } else {
            return visibleFrameOfDestinationScreen
        }
    }
    
}
