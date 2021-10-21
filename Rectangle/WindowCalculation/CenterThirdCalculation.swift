//
//  HorizCenterThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterThirdCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX + floor(visibleFrameOfScreen.width / 3.0) - floor((visibleFrameOfScreen.width / 3.0) * 0.2)
        rect.origin.y = visibleFrameOfScreen.minY
        rect.size.width = ((visibleFrameOfScreen.width / 3.0) * 1.4)
        rect.size.height = visibleFrameOfScreen.height
        return RectResult(rect, subAction: .centerVerticalThird)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX
        rect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 3.0)
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = visibleFrameOfScreen.height / 3.0
        return RectResult(rect, subAction: .centerHorizontalThird)
    }
}

