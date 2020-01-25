//
//  MaximizeHeightCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MaximizeHeightCalculation: WindowCalculation {
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        var maxHeightRect = window.rect
        maxHeightRect.origin.y = visibleFrameOfScreen.minY
        maxHeightRect.size.height = visibleFrameOfScreen.height
        return RectResult(maxHeightRect)
    }
    
}
