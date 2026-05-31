/// MaximizeHeightCalculation.swift

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
