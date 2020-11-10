//
//  BottomHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomHalfCalculation: WindowCalculation, RepeatedExecutionsCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        if params.lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(params)
        }
        
        return calculateRepeatedRect(params)
    }
    
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.height = floor(oneHalfRect.height / 2.0)
        
        return RectResult(oneHalfRect)
    }
    
    func calculateSecondRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
        return RectResult(twoThirdsRect)
    }
    
    func calculateThirdRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        return RectResult(oneThirdRect)
    }
}
