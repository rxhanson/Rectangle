//
//  LastFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class LastFourthCalculation: WindowCalculation, OrientationAware {

    private var firstFourthCalculation: FirstFourthCalculation?
    private var secondFourthCalculation: SecondFourthCalculation?
    private var thirdFourthCalculation: ThirdFourthCalculation?
    
    init(repeatable: Bool = true) {
        if repeatable && Defaults.subsequentExecutionMode.value != .none {
            firstFourthCalculation = FirstFourthCalculation(repeatable: false)
            secondFourthCalculation = SecondFourthCalculation()
            thirdFourthCalculation = ThirdFourthCalculation()
        }
    }
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction, let lastSubAction = last.subAction else {
                return orientationBasedRect(visibleFrameOfScreen)
        }
        
        var calculation: WindowCalculation?
        if last.action == .lastFourth {
            switch lastSubAction {
            case .bottomFourth, .rightFourth:
                calculation = thirdFourthCalculation
            case .centerBottomFourth, .centerRightFourth:
                calculation = secondFourthCalculation
            case .centerTopFourth, .centerLeftFourth:
                calculation = firstFourthCalculation
            default:
                break
            }
        } else if last.action == .firstFourth {
            switch lastSubAction {
            case .bottomFourth, .rightFourth:
                calculation = thirdFourthCalculation
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
        rect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - rect.width
        return RectResult(rect, subAction: .rightFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        return RectResult(rect, subAction: .bottomFourth)
    }
}
