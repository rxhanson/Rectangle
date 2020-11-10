//
//  MoveLeftRightCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class MoveLeftRightCalculation: WindowCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let usableScreens = params.usableScreens
        if params.action == .moveLeft {
            return calculateLeft(params, screen: usableScreens.currentScreen)
        } else if params.action == .moveRight {
            return calculateRight(params, screen: usableScreens.currentScreen)
        }
        
        return nil
    }
    
    func calculateLeft(_ params: WindowCalculationParameters, screen: NSScreen) -> WindowCalculationResult? {
        
        if Defaults.subsequentExecutionMode.traversesDisplays {
            let usableScreens = params.usableScreens
            if let lastAction = params.lastAction, lastAction.action == .moveLeft {
                let normalizedLastRect = AccessibilityElement.normalizeCoordinatesOf(lastAction.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)
                if normalizedLastRect == params.window.rect {
                    if let prevScreen = usableScreens.adjacentScreens?.prev {
                        return calculateRight(params, screen: prevScreen)
                    }
                }
            }
        }

        var calculatedWindowRect = params.window.rect
        calculatedWindowRect.origin.x = screen.adjustedVisibleFrame.minX
        
        if params.window.rect.height >= screen.adjustedVisibleFrame.height {
            calculatedWindowRect.size.height = screen.adjustedVisibleFrame.height
            calculatedWindowRect.origin.y = screen.adjustedVisibleFrame.minY
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.y = round((screen.adjustedVisibleFrame.height - params.window.rect.height) / 2.0) + screen.adjustedVisibleFrame.minY
        }
        return WindowCalculationResult(rect: calculatedWindowRect, screen: screen, resultingAction: .moveLeft)
        
    }
    
    
    func calculateRight(_ params: WindowCalculationParameters, screen: NSScreen) -> WindowCalculationResult? {
        
        if Defaults.subsequentExecutionMode.traversesDisplays {
            let usableScreens = params.usableScreens
            if let lastAction = params.lastAction, lastAction.action == .moveRight {
                let normalizedLastRect = AccessibilityElement.normalizeCoordinatesOf(lastAction.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)
                if normalizedLastRect == params.window.rect {
                    if let nextScreen = usableScreens.adjacentScreens?.next {
                        return calculateLeft(params, screen: nextScreen)
                    }
                }
            }
        }
        
        var calculatedWindowRect = params.window.rect
        calculatedWindowRect.origin.x = screen.adjustedVisibleFrame.maxX - params.window.rect.width
        
        if params.window.rect.height >= screen.adjustedVisibleFrame.height {
            calculatedWindowRect.size.height = screen.adjustedVisibleFrame.height
            calculatedWindowRect.origin.y = screen.adjustedVisibleFrame.minY
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.y = round((screen.adjustedVisibleFrame.height - params.window.rect.height) / 2.0) + screen.adjustedVisibleFrame.minY
        }
        return WindowCalculationResult(rect: calculatedWindowRect, screen: screen, resultingAction: .moveRight)

    }
    
    // unused
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        return RectResult(CGRect.null)
    }
    
}

