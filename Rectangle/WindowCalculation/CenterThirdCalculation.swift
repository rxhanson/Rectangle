/// CenterThirdCalculation.swift

import Foundation

class CenterThirdCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        let thirdWidth = floor(visibleFrameOfScreen.width / 3.0)
        rect.origin.x = visibleFrameOfScreen.minX + thirdWidth
        rect.origin.y = visibleFrameOfScreen.minY
        rect.size.width = visibleFrameOfScreen.width - thirdWidth * 2
        rect.size.height = visibleFrameOfScreen.height
        return RectResult(rect, subAction: .centerVerticalThird)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        let thirdHeight = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.x = visibleFrameOfScreen.minX
        rect.origin.y = visibleFrameOfScreen.minY + thirdHeight
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = visibleFrameOfScreen.height - thirdHeight * 2
        return RectResult(rect, subAction: .centerHorizontalThird)
    }
}

