//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstFourthCalculation: WindowCalculation {
    
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
                return firstFourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
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
        
        return firstFourthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func firstFourthRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(leftFourth(visibleFrameOfScreen), subAction: .leftThird)
            : RectResult(topFourth(visibleFrameOfScreen), subAction: .topThird)
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
