//
//  RightThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LastThirdCalculation: WindowCalculation, RepeatedExecutionsCalculation {
    
    private var firstThirdCalculation: FirstThirdCalculation?
    private var centerThirdCalculation: CenterThirdCalculation?
    
    init(repeatable: Bool = true) {
        if repeatable && Defaults.subsequentExecutionMode.value != .none {
            firstThirdCalculation = FirstThirdCalculation(repeatable: false)
            centerThirdCalculation = CenterThirdCalculation()
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
            ? RectResult(rightThird(visibleFrameOfScreen), subAction: .rightThird)
            : RectResult(bottomThird(visibleFrameOfScreen), subAction: .bottomThird)
    }
    
    func calculateSecondRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return centerThirdCalculation?.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        ?? calculateFirstRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func calculateThirdRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return firstThirdCalculation?.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        ?? calculateFirstRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    private func rightThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        oneThirdRect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - oneThirdRect.width
        return oneThirdRect
    }
    
    private func bottomThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        return oneThirdRect
    }
}
