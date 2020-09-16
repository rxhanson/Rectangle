//
//  LastFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class LastFourthCalculation: WindowCalculation {
    
//    private var firstThirdCalculation: FirstThirdCalculation?
//    private var centerThirdCalculation: CenterThirdCalculation?
//
//    init(repeatable: Bool = true) {
//        if repeatable && Defaults.subsequentExecutionMode.value != .none {
//            firstThirdCalculation = FirstThirdCalculation(repeatable: false)
//            centerThirdCalculation = CenterThirdCalculation()
//        }
//    }
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction, let lastSubAction = last.subAction else {
                return lastFourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
//        var calculation: WindowCalculation?
//
//        if last.action == .lastThird {
//            switch lastSubAction {
//            case .bottomThird, .rightThird:
//                calculation = centerThirdCalculation
//            case .centerHorizontalThird, .centerVerticalThird:
//                calculation = firstThirdCalculation
//            default:
//                break
//            }
//        } else if last.action == .firstThird {
//            switch lastSubAction {
//            case .bottomThird, .rightThird:
//                calculation = centerThirdCalculation
//            default:
//                break
//            }
//        }
//
//        if let calculation = calculation {
//            return calculation.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
//        }
        
        return lastFourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }

    func lastFourthRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(rightFourth(visibleFrameOfScreen), subAction: .rightThird)
            : RectResult(bottomFourth(visibleFrameOfScreen), subAction: .bottomThird)
    }
    
    private func rightFourth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        rect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - rect.width
        return rect
    }
    
    private func bottomFourth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        return rect
    }
}
