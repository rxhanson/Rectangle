//
//  CenterTwoThirdsCalculation.swift
//  Rectangle
//
//  Created by Mikhail Savin on 7/14/25.
//  Copyright © 2025 Mikhail Savin. All rights reserved.
//

import Foundation

class CenterTwoThirdsCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX + floor(visibleFrameOfScreen.width / 3.0) / 2
        rect.origin.y = visibleFrameOfScreen.minY
        rect.size.width = visibleFrameOfScreen.width / 3.0 * 2
        rect.size.height = visibleFrameOfScreen.height
        return RectResult(rect, subAction: .centerVerticalThird)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX
        rect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 3.0) / 2
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = visibleFrameOfScreen.height / 3.0 * 2
        return RectResult(rect, subAction: .centerHorizontalThird)
    }
}

