/// NextPrevDisplayCalculation.swift

import Cocoa

class NextPrevDisplayCalculation: WindowCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let usableScreens = params.usableScreens
        
        guard usableScreens.numScreens > 1 else { return nil }

        var screen: NSScreen?
        
        if params.action == .nextDisplay {
            screen = usableScreens.adjacentScreens?.next
        } else if params.action == .previousDisplay {
            screen = usableScreens.adjacentScreens?.prev
        }

        guard let screen else { return nil }
        
        let rectParams = params.asRectParams(visibleFrame: screen.adjustedVisibleFrame(params.ignoreTodo))
        
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
            
            return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: lastAction.action)
        }
        
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
                return performBasicCalculation(params: params, rectParams: newCalculationParams, screen: screen)
            }
            
            return WindowCalculationResult(rect: transferredRect.rect, screen: screen, resultingAction: params.action)
            
        } else if Defaults.attemptMatchOnNextPrevDisplay.userEnabled {
            // Issue #1723: opt-in ON but no replayable lastAction (e.g. a manually positioned
            // window). Map the window proportionally from the source screen to the destination
            // screen so it keeps its relative spot instead of jumping to the center.
            let mappedRect = NextPrevDisplayCalculation.relativePositionedRect(window: rectParams.window.rect,
                                                                               source: sourceFrame,
                                                                               destination: rectParams.visibleFrameOfScreen)
            return WindowCalculationResult(rect: mappedRect, screen: screen, resultingAction: params.action)
        }
        
        return performBasicCalculation(params: params, rectParams: rectParams, screen: screen)
    }
    
    private func performBasicCalculation(params: WindowCalculationParameters, rectParams: RectCalculationParameters, screen: NSScreen) -> WindowCalculationResult {
        let rectResult = calculateRect(rectParams)
        let action = rectResult.resultingAction ?? params.action
        return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: action)
    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        if params.lastAction?.action == .maximize && !Defaults.autoMaximize.userDisabled {
            let rectResult = WindowCalculationFactory.maximizeCalculation.calculateRect(params)
            return RectResult(rectResult.rect, resultingAction: .maximize)
        }
        
        return WindowCalculationFactory.centerCalculation.calculateRect(params)
    }

    /// Proportionally map `window` from the coordinate space of `source` to `destination`,
    /// preserving its relative position and size as fractions of the source frame, then clamp the
    /// result inside `destination` so a near-full-size window can never overflow. Shared by the
    /// next/previous-display and specific-display moves when `attemptMatchOnNextPrevDisplay` is on
    /// but there is no Rectangle snap action to replay (issue #1723).
    static func relativePositionedRect(window: CGRect, source: CGRect, destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return window }

        let originXFrac = (window.minX - source.minX) / source.width
        let originYFrac = (window.minY - source.minY) / source.height
        let widthFrac = window.width / source.width
        let heightFrac = window.height / source.height

        var rect = CGRect(x: destination.minX + originXFrac * destination.width,
                          y: destination.minY + originYFrac * destination.height,
                          width: widthFrac * destination.width,
                          height: heightFrac * destination.height)

        if rect.maxX > destination.maxX {
            rect.origin.x = destination.maxX - rect.width
        }
        if rect.minX < destination.minX {
            rect.origin.x = destination.minX
        }
        if rect.maxY > destination.maxY {
            rect.origin.y = destination.maxY - rect.height
        }
        if rect.minY < destination.minY {
            rect.origin.y = destination.minY
        }

        return rect
    }
}
