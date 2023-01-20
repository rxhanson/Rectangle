//
//  AlmostMaximizeCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class CenterHalfCalculation: WindowCalculation, OrientationAware, RepeatedExecutionsInThirdsCalculation {
    
    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        return visibleFrameOfScreen.isLandscape
            ? landscapeRect(visibleFrameOfScreen, fraction: fraction)
            : portraitRect(visibleFrameOfScreen, fraction: fraction)
    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        if (params.lastAction != nil && Defaults.subsequentExecutionMode.resizes) || Defaults.centerHalfCycles.userEnabled {
            return calculateRepeatedRect(params)
        }
        
        return orientationBasedRect(params.visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect, fraction: Float) -> RectResult {
        var rect = visibleFrameOfScreen
        
        // Resize
        rect.size.height = visibleFrameOfScreen.height
        rect.size.width = round(visibleFrameOfScreen.width * CGFloat(fraction))
        
        // Center
        rect.origin.x = round((visibleFrameOfScreen.width - rect.width) / 2.0) + visibleFrameOfScreen.minX
        rect.origin.y = round((visibleFrameOfScreen.height - rect.height) / 2.0) + visibleFrameOfScreen.minY
        
        return RectResult(rect, subAction: .centerVerticalHalf)
    }

    func portraitRect(_ visibleFrameOfScreen: CGRect, fraction: Float) -> RectResult {
        var rect = visibleFrameOfScreen
        
        // Resize
        rect.size.width = visibleFrameOfScreen.width
        rect.size.height = round(visibleFrameOfScreen.height * CGFloat(fraction))
        
        // Center
        rect.origin.x = round((visibleFrameOfScreen.width - rect.width) / 2.0) + visibleFrameOfScreen.minX
        rect.origin.y = round((visibleFrameOfScreen.height - rect.height) / 2.0) + visibleFrameOfScreen.minY
        
        return RectResult(rect, subAction: .centerHorizontalHalf)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        return landscapeRect(visibleFrameOfScreen, fraction: 0.5)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        return portraitRect(visibleFrameOfScreen, fraction: 0.5)
    }

}

