//
//  SecondFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class SecondFourthCalculation: WindowCalculation, OrientationAware {
    
    let threeFourthsCalculation = RightOrBottomThreeFourthsCalculation()
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        guard Defaults.subsequentExecutionMode.value != .none,
              Defaults.subsequentExecutionMode.value != .cycleMonitor, // Just check for .resizes instead?
            let last = params.lastAction,
            let lastSubAction = last.subAction,
            last.action == .secondFourth
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        let calc: SimpleCalc
        switch lastSubAction {
        case .centerLeftFourth:
            calc = threeFourthsCalculation.landscapeRect
        case .centerTopFourth:
            calc = threeFourthsCalculation.portraitRect
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

class RightOrBottomThreeFourthsCalculation: WindowCalculation, OrientationAware {
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 3.0 / 4.0)
        rect.origin.x = visibleFrameOfScreen.maxX - rect.width
        return RectResult(rect, subAction: .rightThreeFourths)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.width * 3.0 / 4.0)
        return RectResult(rect, subAction: .bottomThreeFourths)
    }
}
