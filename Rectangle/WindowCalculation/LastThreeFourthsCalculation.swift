//
//  LastThreeFourthsCalculation.swift
//  Rectangle
//
//  Created by Björn Orri Sæmundsson on 26.06.21.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//

import Foundation

class LastThreeFourthsCalculation: WindowCalculation, OrientationAware {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        guard Defaults.subsequentExecutionMode.value != .none,
            let last = params.lastAction, let lastSubAction = last.subAction else {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        if lastSubAction == .rightThreeFourths || lastSubAction == .bottomThreeFourths {
            return WindowCalculationFactory.firstThreeFourthsCalculation.orientationBasedRect(visibleFrameOfScreen)
        }
        
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width * 3 / 4.0)
        rect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width - rect.width
        return RectResult(rect, subAction: .rightThreeFourths)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height * 3 / 4.0)
        return RectResult(rect, subAction: .bottomThreeFourths)
    }
}
