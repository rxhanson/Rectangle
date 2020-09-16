//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstFourthCalculation: WindowCalculation {

    private var secondFourthCalculation = SecondFourthCalculation()
    private var thirdFourthCalculation = ThirdFourthCalculation()
    private var lastFourthCalculation = LastFourthCalculation()

    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            action == .firstFourth,
            let last = lastAction,
            last.action == .firstFourth,
            let lastSubAction = last.subAction
        else {
            return firstFourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        var calculation: WindowCalculation?
        switch lastSubAction {
        case .topFourth, .leftFourth:
            calculation = secondFourthCalculation
        case .centerTopFourth, .centerLeftFourth:
            calculation = thirdFourthCalculation
        case .centerBottomFourth, .centerRightFourth:
            calculation = lastFourthCalculation
        default:
            break
        }

        if let calculation = calculation {
            return calculation.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return firstFourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func firstFourthRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(leftFourth(visibleFrameOfScreen), subAction: .leftFourth)
            : RectResult(topFourth(visibleFrameOfScreen), subAction: .topFourth)
    }
    
    private func leftFourth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        return rect
    }
    
    private func topFourth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - rect.height
        return rect
    }
    
}
