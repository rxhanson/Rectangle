//
//  ThirdFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class ThirdFourthCalculation: WindowCalculation, OrientationAware {
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        let visibleFrameOfScreen = params.visibleFrameOfScreen
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = params.lastAction,
            let lastSubAction = last.subAction,
            last.action == .thirdFourth
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        let calc: SimpleCalc
        switch lastSubAction {
        case .centerRightFourth:
            calc = WindowCalculationFactory.firstThreeFourthsCalculation.landscapeRect
        case .centerBottomFourth:
            calc = WindowCalculationFactory.firstThreeFourthsCalculation.portraitRect
        case .leftThreeFourths:
            calc = WindowCalculationFactory.centerHalfCalculation.landscapeRect
        case .topThreeFourths:
            calc = WindowCalculationFactory.centerHalfCalculation.portraitRect
        default:
            calc = orientationBasedRect
        }
        
        return calc(visibleFrameOfScreen)
    }
        
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = (((visibleFrameOfScreen.width / 3.0) * 1.4) / 2) + visibleFrameOfScreen.minX
        rect.size.height = visibleFrameOfScreen.height
        rect.origin.x = visibleFrameOfScreen.minX + floor(visibleFrameOfScreen.width / 3.0) - floor((visibleFrameOfScreen.width / 3.0) * 0.2) + rect.size.width
        rect.origin.y = visibleFrameOfScreen.minY
        return RectResult(rect, subAction: .centerRightFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - (rect.height * 3.0)
        return RectResult(rect, subAction: .centerBottomFourth)
    }
}
