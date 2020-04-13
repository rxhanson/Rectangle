//
//  BottomHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomHalfCalculation: WindowCalculation, RepeatedExecutionsCalculation {

    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {

        if lastAction == nil || !Defaults.subsequentExecutionMode.resizes {
            return calculateFirstRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return calculateRepeatedRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    
    func calculateFirstRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.height = floor(oneHalfRect.height / 2.0)
        
        return RectResult(oneHalfRect)
    }
    
    func calculateSecondRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.height = floor(visibleFrameOfScreen.height * 2 / 3.0)
        return RectResult(twoThirdsRect)
    }
    
    func calculateThirdRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        return RectResult(oneThirdRect)
    }
}
