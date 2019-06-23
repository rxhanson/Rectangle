//
//  MaximizeHeightCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MaximizeHeightCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        var maxHeightRect = windowRect
        maxHeightRect.origin.y = visibleFrameOfDestinationScreen.minY
        maxHeightRect.size.height = visibleFrameOfDestinationScreen.maxY
        return maxHeightRect
    }
    
}
