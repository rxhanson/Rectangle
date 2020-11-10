//
//  MaximizeHeightCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class MaximizeHeightCalculation: WindowCalculation {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        var maxHeightRect = params.window.rect
        maxHeightRect.origin.y = visibleFrameOfScreen.minY
        maxHeightRect.size.height = visibleFrameOfScreen.height
        return RectResult(maxHeightRect)
    }
    
}
