//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstFourthCalculation: WindowCalculation, OrientationAware {

    private var secondFourthCalculation: SecondFourthCalculation?
    private var thirdFourthCalculation: ThirdFourthCalculation?
    private var lastFourthCalculation: LastFourthCalculation?
    
    init(repeatable: Bool = true) {
        if repeatable && Defaults.subsequentExecutionMode.value != .none {
            secondFourthCalculation = SecondFourthCalculation()
            thirdFourthCalculation = ThirdFourthCalculation()
            lastFourthCalculation = LastFourthCalculation(repeatable: false)
        }
    }

    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            action == .firstFourth,
            let last = lastAction,
            let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        var calculation: WindowCalculation?
        if last.action == .firstFourth {
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
        } else if last.action == .lastFourth {
            switch lastSubAction {
            case .leftFourth, .topFourth:
                calculation = secondFourthCalculation
            default:
                break
            }
        }

        if let calculation = calculation {
            return calculation.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        return RectResult(rect, subAction: .leftFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - rect.height
        return RectResult(rect, subAction: .topFourth)
    }
    
}
