//
//  RightThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class LastThirdCalculation: WindowCalculation {
    
    private var firstThirdCalculation: FirstThirdCalculation?
    private var centerThirdCalculation: CenterThirdCalculation?
    
    init(repeatable: Bool = true) {
        if repeatable && Defaults.subsequentExecutionMode.value != .none {
            firstThirdCalculation = FirstThirdCalculation(repeatable: false)
            centerThirdCalculation = CenterThirdCalculation()
        }
    }
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction, let lastSubAction = last.subAction else {
                return lastThirdRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        var calculation: WindowCalculation?
        
        if last.action == .lastThird {
            switch lastSubAction {
            case .bottomThird, .rightThird:
                calculation = centerThirdCalculation
            case .centerHorizontalThird, .centerVerticalThird:
                calculation = firstThirdCalculation
            default:
                break
            }
        } else if last.action == .firstThird {
            switch lastSubAction {
            case .bottomThird, .rightThird:
                calculation = centerThirdCalculation
            default:
                break
            }
        }
        
        if let calculation = calculation {
            return calculation.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return lastThirdRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }

    func lastThirdRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(rightThird(visibleFrameOfScreen), subAction: .rightThird)
            : RectResult(bottomThird(visibleFrameOfScreen), subAction: .bottomThird)
    }
    
    private func rightThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        oneThirdRect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - oneThirdRect.width
        return oneThirdRect
    }
    
    private func bottomThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        return oneThirdRect
    }
}
