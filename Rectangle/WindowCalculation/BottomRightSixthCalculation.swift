//
//  BottomRightSixthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomRightSixthCalculation: WindowCalculation {
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
                return sixthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
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
        
        return sixthRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func sixthRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(landscapeSixth(visibleFrameOfScreen), subAction: .leftThird)
            : RectResult(portraitSixth(visibleFrameOfScreen), subAction: .topThird)
    }
    
    private func landscapeSixth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.origin.x + (rect.width * 2)
        return rect
    }
    
    private func portraitSixth(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.origin.x + (rect.width * 2)
        return rect
    }
}
