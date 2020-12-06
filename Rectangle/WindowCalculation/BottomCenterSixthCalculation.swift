//
//  BottomCenterCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class BottomCenterSixthCalculation: WindowCalculation, OrientationAware {
    
    private let bottomRightTwoSixths = BottomRightTwoSixthsCalculation()
    private let bottomLeftTwoSixths = BottomLeftTwoSixthsCalculation()
    private let topRightTwoSixths = TopRightTwoSixthsCalculation()
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        guard Defaults.subsequentExecutionMode.value != .none,
              let last = params.lastAction,
              let lastSubAction = last.subAction,
              params.action == .bottomCenterSixth
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        let calc: SimpleCalc
        switch lastSubAction{
        case .bottomCenterSixthLandscape, .rightCenterSixthPortrait:
            calc = bottomRightTwoSixths.orientationBasedRect
        case .bottomRightTwoSixthsLandscape:
            calc = bottomLeftTwoSixths.orientationBasedRect
        case .bottomRightTwoSixthsPortrait:
            calc = topRightTwoSixths.orientationBasedRect
        default: calc = orientationBasedRect
        }
        
        return calc(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.origin.x + rect.width
        return RectResult(rect, subAction: .bottomCenterSixthLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.x = visibleFrameOfScreen.origin.x + rect.width
        rect.origin.y = visibleFrameOfScreen.origin.y + rect.height
        return RectResult(rect, subAction: .rightCenterSixthPortrait)
    }
}

class BottomRightTwoSixthsCalculation: WindowCalculation, OrientationAware {

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 2.0 / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.maxX - rect.width
        return RectResult(rect, subAction: .bottomRightTwoSixthsLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height * 2.0 / 3.0)
        rect.origin.x = visibleFrameOfScreen.maxX - rect.width
        return RectResult(rect, subAction: .bottomRightTwoSixthsPortrait)
    }
}

class BottomLeftTwoSixthsCalculation: WindowCalculation, OrientationAware {

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 2.0 / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        return RectResult(rect, subAction: .bottomLeftTwoSixthsLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height * 2.0 / 3.0)
        return RectResult(rect, subAction: .bottomLeftTwoSixthsPortrait)
    }
}
