//
//  SecondFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class SecondFourthCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = params.lastAction,
            let lastSubAction = last.subAction,
            last.action == .secondFourth
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        let calc: SimpleCalc
        switch lastSubAction {
        case .centerLeftFourth:
            calc = WindowCalculationFactory.lastThreeFourthsCalculation.landscapeRect
        case .centerTopFourth:
            calc = WindowCalculationFactory.lastThreeFourthsCalculation.portraitRect
        case .rightThreeFourths:
            calc = WindowCalculationFactory.centerHalfCalculation.landscapeRect
        case .bottomThreeFourths:
            calc = WindowCalculationFactory.centerHalfCalculation.portraitRect
        default:
            calc = orientationBasedRect
        }
        
        return calc(visibleFrameOfScreen)
    }
        
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        rect.origin.x = visibleFrameOfScreen.minX + rect.width
        return RectResult(rect, subAction: .centerLeftFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - (rect.height * 2.0)
        return RectResult(rect, subAction: .centerTopFourth)
    }
    
}
