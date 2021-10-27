//
//  LastFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class LastFourthCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = params.lastAction, let lastSubAction = last.subAction else {
                return orientationBasedRect(visibleFrameOfScreen)
        }
        
        var calculation: WindowCalculation?
        if last.action == .lastFourth {
            switch lastSubAction {
            case .bottomFourth, .rightFourth:
                calculation = WindowCalculationFactory.thirdFourthCalculation
            case .centerBottomFourth, .centerRightFourth:
                calculation = WindowCalculationFactory.secondFourthCalculation
            case .centerTopFourth, .centerLeftFourth:
                calculation = WindowCalculationFactory.firstFourthCalculation
            default:
                break
            }
        } else if last.action == .firstFourth {
            switch lastSubAction {
            case .bottomFourth, .rightFourth:
                calculation = WindowCalculationFactory.thirdFourthCalculation
            default:
                break
            }
        }

        if let calculation = calculation {
            return calculation.calculateRect(params)
        }
        
        return orientationBasedRect(visibleFrameOfScreen)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor((visibleFrameOfScreen.width / 4.0) * 1.1)
        rect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - rect.width
        return RectResult(rect, subAction: .rightFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        return RectResult(rect, subAction: .bottomFourth)
    }
}
