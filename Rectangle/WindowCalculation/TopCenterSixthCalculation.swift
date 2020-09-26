//
//  TopCenterSixthCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/16/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class TopCenterSixthCalculation: WindowCalculation, OrientationAware {
    
    private let topRightTwoSixths = TopRightTwoSixthsCalculation()
    private let topLeftTwoSixths = TopLeftTwoSixthsCalculation()
    
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        guard Defaults.subsequentExecutionMode.value != .none,
            let last = lastAction,
            let lastSubAction = last.subAction,
            action == .topCenterSixth
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        let calc: SimpleCalc
        switch lastSubAction{
        case .topCenterSixthLandscape, .leftCenterSixthPortrait:
            calc = topRightTwoSixths.orientationBasedRect
        case .topRightTwoSixthsLandscape, .topRightTwoSixthsPortrait:
            calc = topLeftTwoSixths.orientationBasedRect
        default: calc = orientationBasedRect
        }
        
        return calc(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.minX + rect.width
        rect.origin.y = visibleFrameOfScreen.minY + rect.height
        return RectResult(rect, subAction: .topCenterSixthLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY + rect.height
        return RectResult(rect, subAction: .leftCenterSixthPortrait)
    }
}

class TopRightTwoSixthsCalculation: WindowCalculation, OrientationAware {

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 2.0 / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.x = visibleFrameOfScreen.maxX - rect.width
        rect.origin.y = visibleFrameOfScreen.minY + rect.height
        return RectResult(rect, subAction: .topRightTwoSixthsLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height * 2.0 / 3.0)
        return RectResult(rect, subAction: .topRightTwoSixthsPortrait)
    }
}

class TopLeftTwoSixthsCalculation: WindowCalculation, OrientationAware {

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 2.0 / 3.0)
        rect.size.height = floor(visibleFrameOfScreen.height / 2.0)
        rect.origin.y = visibleFrameOfScreen.minY + rect.height
        return RectResult(rect, subAction: .topLeftTwoSixthsLandscape)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 2.0)
        rect.size.height = floor(visibleFrameOfScreen.height * 2.0 / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY + rect.height
        return RectResult(rect, subAction: .topLeftTwoSixthsPortrait)
    }
}
