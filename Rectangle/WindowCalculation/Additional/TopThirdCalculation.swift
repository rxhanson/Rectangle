//
//  TopThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class TopThirdCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var oneThirdRect = visibleFrameOfDestinationScreen
        oneThirdRect.size.height = floor(visibleFrameOfDestinationScreen.height / 3.0)
        oneThirdRect.origin.y = visibleFrameOfDestinationScreen.origin.y + visibleFrameOfDestinationScreen.height - oneThirdRect.height
        return oneThirdRect
    }
    
}

