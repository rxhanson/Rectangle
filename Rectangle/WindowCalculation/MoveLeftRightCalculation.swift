//
//  MoveLeftRightCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class MoveLeftRightCalculation: WindowCalculation {
    
    override func calculate(_ window: Window, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {
        
        if action == .moveLeft {
            return calculateLeft(window, lastAction: lastAction, screen: usableScreens.currentScreen, usableScreens: usableScreens)
        } else if action == .moveRight {
            return calculateRight(window, lastAction: lastAction, screen: usableScreens.currentScreen, usableScreens: usableScreens)
        }
        
        return nil
    }
    
    func calculateLeft(_ window: Window, lastAction: RectangleAction?, screen: NSScreen, usableScreens: UsableScreens) -> WindowCalculationResult? {
        
        if Defaults.subsequentExecutionMode.traversesDisplays {
            
            if let lastAction = lastAction, lastAction.action == .moveLeft {
                let normalizedLastRect = AccessibilityElement.normalizeCoordinatesOf(lastAction.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)
                if normalizedLastRect == window.rect {
                    if let prevScreen = usableScreens.adjacentScreens?.prev {
                        return calculateRight(window, lastAction: lastAction, screen: prevScreen, usableScreens: usableScreens)
                    }
                }
            }
        }

        var calculatedWindowRect = window.rect
        calculatedWindowRect.origin.x = screen.adjustedVisibleFrame.minX
        
        if window.rect.height >= screen.adjustedVisibleFrame.height {
            calculatedWindowRect.size.height = screen.adjustedVisibleFrame.height
            calculatedWindowRect.origin.y = screen.adjustedVisibleFrame.minY
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.y = round((screen.adjustedVisibleFrame.height - window.rect.height) / 2.0) + screen.adjustedVisibleFrame.minY
        }
        return WindowCalculationResult(rect: calculatedWindowRect, screen: screen, resultingAction: .moveLeft)
        
    }
    
    
    func calculateRight(_ window: Window, lastAction: RectangleAction?, screen: NSScreen, usableScreens: UsableScreens) -> WindowCalculationResult? {
        
        if Defaults.subsequentExecutionMode.traversesDisplays {
            
            if let lastAction = lastAction, lastAction.action == .moveRight {
                let normalizedLastRect = AccessibilityElement.normalizeCoordinatesOf(lastAction.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)
                if normalizedLastRect == window.rect {
                    if let nextScreen = usableScreens.adjacentScreens?.next {
                        return calculateLeft(window, lastAction: lastAction, screen: nextScreen, usableScreens: usableScreens)
                    }
                }
            }
        }
        
        var calculatedWindowRect = window.rect
        calculatedWindowRect.origin.x = screen.adjustedVisibleFrame.maxX - window.rect.width
        
        if window.rect.height >= screen.adjustedVisibleFrame.height {
            calculatedWindowRect.size.height = screen.adjustedVisibleFrame.height
            calculatedWindowRect.origin.y = screen.adjustedVisibleFrame.minY
        } else if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.y = round((screen.adjustedVisibleFrame.height - window.rect.height) / 2.0) + screen.adjustedVisibleFrame.minY
        }
        return WindowCalculationResult(rect: calculatedWindowRect, screen: screen, resultingAction: .moveRight)

    }
    
    // unused
    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return RectResult(CGRect.null)
    }
    
}

