/// CenterTwoThirdsCalculation.swift

import Foundation

class CenterTwoThirdsCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        let width = floor(visibleFrameOfScreen.width / 3.0) * 2
        rect.origin.x = visibleFrameOfScreen.minX + floor((visibleFrameOfScreen.width - width) / 2)
        rect.origin.y = visibleFrameOfScreen.minY
        rect.size.width = width
        rect.size.height = visibleFrameOfScreen.height
        return RectResult(rect, subAction: .centerVerticalThird)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        let height = floor(visibleFrameOfScreen.height / 3.0) * 2
        rect.origin.x = visibleFrameOfScreen.minX
        rect.origin.y = visibleFrameOfScreen.minY + floor((visibleFrameOfScreen.height - height) / 2)
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = height
        return RectResult(rect, subAction: .centerHorizontalThird)
    }
}

