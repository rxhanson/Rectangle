//
//  LeftThirdCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class FirstThirdCalculation: WindowCalculation {
    
    private var centerThirdCalculation: CenterThirdCalculation?
    private var lastThirdCalculation: LastThirdCalculation?
    
    init(repeatable: Bool = true) {
        if repeatable && Defaults.subsequentExecutionMode.value != .none {
            centerThirdCalculation = CenterThirdCalculation()
            lastThirdCalculation = LastThirdCalculation(repeatable: false)
        }
    }
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction, let lastSubAction = last.subAction else {
                return firstThirdRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        var calculation: WindowCalculation?
        
        if last.action == .firstThird {
            switch lastSubAction {
            case .topThird, .leftThird:
                calculation = centerThirdCalculation
            case .centerHorizontalThird, .centerVerticalThird:
                calculation = lastThirdCalculation
            default:
                break
            }
        } else if last.action == .lastThird {
            switch lastSubAction {
            case .topThird, .leftThird:
                calculation = centerThirdCalculation
            default:
                break
            }
        }
        
        if let calculation = calculation {
            return calculation.calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
        }
        
        return firstThirdRect(window, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
    
    func firstThirdRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return isLandscape(visibleFrameOfScreen)
            ? RectResult(leftThird(visibleFrameOfScreen), subAction: .leftThird)
            : RectResult(topThird(visibleFrameOfScreen), subAction: .topThird)
    }
    
    private func leftThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        return oneThirdRect
    }
    
    private func topThird(_ visibleFrameOfScreen: CGRect) -> CGRect {
        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        oneThirdRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - oneThirdRect.height
        return oneThirdRect
    }
    
}
