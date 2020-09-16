//
//  ThirdFourthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class ThirdFourthCalculation: WindowCalculation {
    
//    private var centerThirdCalculation: CenterThirdCalculation?
//    private var lastThirdCalculation: LastThirdCalculation?
//
//    init(repeatable: Bool = true) {
//        if repeatable && Defaults.subsequentExecutionMode.value != .none {
//            centerThirdCalculation = CenterThirdCalculation()
//            lastThirdCalculation = LastThirdCalculation(repeatable: false)
//        }
//    }
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction, let lastSubAction = last.subAction else {
                return fourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
//        var calculation: WindowCalculation?
//
//        if last.action == .firstThird {
//            switch lastSubAction {
//            case .topThird, .leftThird:
//                calculation = centerThirdCalculation
//            case .centerHorizontalThird, .centerVerticalThird:
//                calculation = lastThirdCalculation
//            default:
//                break
//            }
//        } else if last.action == .lastThird {
//            switch lastSubAction {
//            case .topThird, .leftThird:
//                calculation = centerThirdCalculation
//            default:
//                break
//            }
//        }
//
//        if let calculation = calculation {
//            return calculation.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
//        }
        
        return fourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func fourthRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(landscapeFourth(visibleFrameOfScreen), subAction: .leftThird)
            : RectResult(portraitFourth(visibleFrameOfScreen), subAction: .topThird)
    }
    
    private func landscapeFourth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        rect.origin.x = visibleFrameOfScreen.origin.x + (rect.width * 2)
        return rect
    }
    
    private func portraitFourth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - (rect.height * 3.0)
        return rect
    }
    
}
