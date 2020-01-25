//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstThirdCalculation: WindowCalculation, RepeatedExecutionsCalculation {
    
    private var centerThirdCalculation: CenterThirdCalculation?
    private var lastThirdCalculation: LastThirdCalculation?
    
    init(repeatable: Bool = true) {
        if repeatable && Defaults.subsequentExecutionMode.value != .none {
            centerThirdCalculation = CenterThirdCalculation()
            lastThirdCalculation = LastThirdCalculation(repeatable: false)
        }
    }
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        if Defaults.subsequentExecutionMode.value == .none
            || lastAction == nil {
            return calculateFirstRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return calculateRepeatedRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func calculateFirstRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {

        return isLandscape(visibleFrameOfScreen)
            ? RectResult(leftThird(visibleFrameOfScreen), subAction: .leftThird)
            : RectResult(topThird(visibleFrameOfScreen), subAction: .topThird)
    }
    
    func calculateSecondRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return centerThirdCalculation?.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        ?? calculateFirstRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func calculateThirdRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return lastThirdCalculation?.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        ?? calculateFirstRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    private func leftThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        return oneThirdRect
    }
    
    private func topThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        oneThirdRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - oneThirdRect.height
        return oneThirdRect
    }
    
}
