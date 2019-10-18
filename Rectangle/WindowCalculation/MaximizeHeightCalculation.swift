//
//  MaximizeHeightCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MaximizeHeightCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        var maxHeightRect = windowRect
        maxHeightRect.origin.y = visibleFrameOfScreen.minY
        maxHeightRect.size.height = visibleFrameOfScreen.height
        return maxHeightRect
    }
    
}
