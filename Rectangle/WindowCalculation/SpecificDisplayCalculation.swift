/// SpecificDisplayCalculation.swift

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

        if Defaults.attemptMatchOnNextPrevDisplay.userEnabled,
           let lastAction = params.lastAction,
           let calculation = WindowCalculationFactory.calculationsByAction[lastAction.action] {

            if let windowId = params.window.id {
                AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            }

            let newCalculationParams = RectCalculationParameters(
                window: rectParams.window,
                visibleFrameOfScreen: rectParams.visibleFrameOfScreen,
                action: lastAction.action,
                lastAction: nil)
            let rectResult = calculation.calculateRect(newCalculationParams)

            return WindowCalculationResult(rect: rectResult.rect, screen: targetScreen, resultingAction: lastAction.action)
        }

        // Parity with NextPrevDisplayCalculation: display 1/2/3 moves behave like next/prev moves.
        let sourceFrame = params.usableScreens.currentScreen.adjustedVisibleFrame(params.ignoreTodo)

        if !Defaults.centerAcrossDisplays.userEnabled {
            let transferredRect = DisplayTransfer.transferredRect(window: rectParams.window.rect,
                                                                  source: sourceFrame,
                                                                  destination: rectParams.visibleFrameOfScreen)
            
            if transferredRect.sharedEdges == .all {
                // Window is currently deemed as maximized.
                // Follow autoMaximize check to see if it should be maximized on next display.
                let newCalculationParams = RectCalculationParameters(
                    window: rectParams.window,
                    visibleFrameOfScreen: rectParams.visibleFrameOfScreen,
                    action: .maximize,
                    lastAction: RectangleAction(action: .maximize, rect: rectParams.window.rect))
                return performBasicCalculation(params: params, rectParams: newCalculationParams, screen: targetScreen)
            }
            
            return WindowCalculationResult(rect: transferredRect.rect, screen: targetScreen, resultingAction: params.action)
            
        } else if Defaults.attemptMatchOnNextPrevDisplay.userEnabled {
            // Issue #1723: opt-in ON but no replayable lastAction (e.g. a manually positioned
            // window). Map the window proportionally from the source screen to the destination
            // screen so it keeps its relative spot instead of jumping to the center.
            let mappedRect = NextPrevDisplayCalculation.relativePositionedRect(window: rectParams.window.rect,
                                                                               source: sourceFrame,
                                                                               destination: rectParams.visibleFrameOfScreen)
            return WindowCalculationResult(rect: mappedRect, screen: targetScreen, resultingAction: params.action)
        }

        return performBasicCalculation(params: params, rectParams: rectParams, screen: targetScreen)
    }

    private func performBasicCalculation(params: WindowCalculationParameters, rectParams: RectCalculationParameters, screen: NSScreen) -> WindowCalculationResult {
        let rectResult = calculateRect(rectParams)
        let action = rectResult.resultingAction ?? params.action
        return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: action)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        return WindowCalculationFactory.centerCalculation.calculateRect(params)
    }
}
