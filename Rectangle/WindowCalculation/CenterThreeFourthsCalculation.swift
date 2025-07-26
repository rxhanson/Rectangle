//
//  CenterThreeFourthsCalculation.swift
//  Rectangle
//
//  Created by Tom Grimwood-Taylor on 26/07/2025.
//  Copyright © 2025 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterThreeFourthsCalculation: WindowCalculation, OrientationAware {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        return orientationBasedRect(visibleFrameOfScreen)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX + floor(visibleFrameOfScreen.width / 4.0) / 2
        rect.origin.y = visibleFrameOfScreen.minY
        rect.size.width = visibleFrameOfScreen.width / 4.0 * 3
        rect.size.height = visibleFrameOfScreen.height
        return RectResult(rect, subAction: .centerVerticalThreeFourths)
    }

    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.origin.x = visibleFrameOfScreen.minX
        rect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 4.0) / 2
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = visibleFrameOfScreen.height / 4.0 * 3
        return RectResult(rect, subAction: .centerHorizontalThreeFourths)
    }
}

