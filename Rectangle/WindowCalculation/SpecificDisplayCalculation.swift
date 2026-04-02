//
//  SpecificDisplayCalculation.swift
//  Rectangle
//
//  Created by Lucas on 4/2/26.
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

class SpecificDisplayCalculation: WindowCalculation {

    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let usableScreens = params.usableScreens

        guard usableScreens.numScreens > 1 else { return nil }

        guard let displayIndex = params.action.displayIndex else { return nil }

        let screens = usableScreens.screensOrdered

        guard displayIndex < screens.count else { return nil }

        let targetScreen = screens[displayIndex]

        if targetScreen == usableScreens.currentScreen { return nil }

        let rectParams = params.asRectParams(visibleFrame: targetScreen.adjustedVisibleFrame(params.ignoreTodo))

        if Defaults.attemptMatchOnNextPrevDisplay.userEnabled {
            if let lastAction = params.lastAction,
               let calculation = WindowCalculationFactory.calculationsByAction[lastAction.action] {

                AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: params.window.id)

                let newCalculationParams = RectCalculationParameters(
                    window: rectParams.window,
                    visibleFrameOfScreen: rectParams.visibleFrameOfScreen,
                    action: lastAction.action,
                    lastAction: nil)
                let rectResult = calculation.calculateRect(newCalculationParams)

                return WindowCalculationResult(rect: rectResult.rect, screen: targetScreen, resultingAction: lastAction.action)
            }
        }

        let rectResult = calculateRect(rectParams)
        let resultingAction: WindowAction = rectResult.resultingAction ?? params.action
        return WindowCalculationResult(rect: rectResult.rect, screen: targetScreen, resultingAction: resultingAction)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        return WindowCalculationFactory.centerCalculation.calculateRect(params)
    }
}
