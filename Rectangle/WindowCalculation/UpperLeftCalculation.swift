//
//  UpperLeftCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class UpperLeftCalculation: WindowCalculation, RepeatedExecutionsCalculation {

    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {

        if Defaults.subsequentExecutionMode.value == .none
            || lastAction == nil {
            return calculateFirstRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return calculateRepeatedRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func calculateFirstRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneQuarterRect = visibleFrameOfScreen
        oneQuarterRect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        oneQuarterRect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        oneQuarterRect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 2.0) + (visibleFrameOfScreen.height.truncatingRemainder(dividingBy: 2.0))
        return oneQuarterRect
    }
    
    func calculateSecondRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.width = floor(visibleFrameOfScreen.width * 2 / 3.0)
        twoThirdsRect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        twoThirdsRect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 2.0) + (visibleFrameOfScreen.height.truncatingRemainder(dividingBy: 2.0))

        return twoThirdsRect
    }
    
    func calculateThirdRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        oneThirdRect.origin.y = visibleFrameOfScreen.minY + floor(visibleFrameOfScreen.height / 2.0) + (visibleFrameOfScreen.height.truncatingRemainder(dividingBy: 2.0))

        return oneThirdRect
    }
}
