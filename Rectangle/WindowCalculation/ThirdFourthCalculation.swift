//
//  ThirdFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class ThirdFourthCalculation: WindowCalculation, OrientationAware {
    
    let threeFourthsCalculation = LeftOrTopThreeFourthsCalculation()
    let centerHalfCalculation = CenterHalfCalculation()
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction,
            let lastSubAction = last.subAction,
            last.action == .thirdFourth
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        let calc: SimpleCalc
        switch lastSubAction {
        case .centerRightFourth:
            calc = threeFourthsCalculation.landscapeRect
        case .centerBottomFourth:
            calc = threeFourthsCalculation.portraitRect
        case .leftThreeFourths:
            calc = centerHalfCalculation.landscapeRect
        case .topThreeFourths:
            calc = centerHalfCalculation.portraitRect
        default:
            calc = orientationBasedRect
        }
        
        return calc(visibleFrameOfScreen)
    }
        
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        rect.origin.x = visibleFrameOfScreen.minX + (rect.width * 2)
        return RectResult(rect, subAction: .centerRightFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - (rect.height * 3.0)
        return RectResult(rect, subAction: .centerBottomFourth)
    }
}

class LeftOrTopThreeFourthsCalculation: WindowCalculation, OrientationAware {
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 3.0 / 4.0)
        return RectResult(rect, subAction: .leftThreeFourths)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.width * 3.0 / 4.0)
        rect.origin.y = visibleFrameOfScreen.maxY - rect.height
        return RectResult(rect, subAction: .topThreeFourths)
    }
}
