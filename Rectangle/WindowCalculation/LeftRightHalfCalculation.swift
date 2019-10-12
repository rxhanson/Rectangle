//
//  LeftHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class LeftRightHalfCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {
        
        if action == .leftHalf {
            return calculateLeft(windowRect, lastAction: lastAction, screen: usableScreens.currentScreen, usableScreens: usableScreens)
        } else if action == .rightHalf {
            return calculateRight(windowRect, lastAction: lastAction, screen: usableScreens.currentScreen, usableScreens: usableScreens)
        }
        
        return nil
    }
    
    func calculateLeft(_ windowRect: CGRect, lastAction: RectangleAction?, screen: NSScreen, usableScreens: UsableScreens) -> WindowCalculationResult? {
        
        var oneHalfRect = screen.visibleFrame
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        
        if Defaults.subsequentExecutionMode.value == .acrossMonitor {
            
            if let lastAction = lastAction, lastAction.action == .leftHalf {
                let normalizedLastRect = AccessibilityElement.normalizeCoordinatesOf(lastAction.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)
                if normalizedLastRect == windowRect {
                    if let prevScreen = usableScreens.adjacentScreens?.prev {
                        return calculateRight(windowRect, lastAction: lastAction, screen: prevScreen, usableScreens: usableScreens)
                    }
                }
            }
            
        } else if Defaults.subsequentExecutionMode.value == .resize {
            
            if abs(windowRect.midY - oneHalfRect.midY) > 1.0 {
                return WindowCalculationResult(rect: oneHalfRect, screen: screen, resultingAction: .leftHalf)
            }
            
            var twoThirdsRect = oneHalfRect
            twoThirdsRect.size.width = floor(screen.visibleFrame.width * 2 / 3.0)
            
            if rectCenteredWithinRect(oneHalfRect, windowRect) {
                return WindowCalculationResult(rect: twoThirdsRect, screen: screen, resultingAction: .leftHalf)
            }
            
            if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                var oneThirdRect = oneHalfRect
                oneThirdRect.size.width = floor(screen.visibleFrame.width / 3.0)
                return WindowCalculationResult(rect: oneThirdRect, screen: screen, resultingAction: .leftHalf)
            }
            
        }
        
        return WindowCalculationResult(rect: oneHalfRect, screen: screen, resultingAction: .leftHalf)
    }
    
    
    func calculateRight(_ windowRect: CGRect, lastAction: RectangleAction?, screen: NSScreen, usableScreens: UsableScreens) -> WindowCalculationResult? {
        
        var oneHalfRect = screen.visibleFrame
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        oneHalfRect.origin.x += oneHalfRect.size.width
        
        if Defaults.subsequentExecutionMode.value == .acrossMonitor {
            
            if let lastAction = lastAction, lastAction.action == .rightHalf {
                let normalizedLastRect = AccessibilityElement.normalizeCoordinatesOf(lastAction.rect, frameOfScreen: usableScreens.frameOfCurrentScreen)
                if normalizedLastRect == windowRect {
                    if let nextScreen = usableScreens.adjacentScreens?.next {
                        return calculateLeft(windowRect, lastAction: lastAction, screen: nextScreen, usableScreens: usableScreens)
                    }
                }
            }

            
        } else if Defaults.subsequentExecutionMode.value == .resize {
            
            if abs(windowRect.midY - oneHalfRect.midY) > 1.0 {
                return WindowCalculationResult(rect: oneHalfRect, screen: screen, resultingAction: .rightHalf)
            }
            
            var twoThirdsRect = screen.visibleFrame
            twoThirdsRect.size.width = floor(screen.visibleFrame.width * 2 / 3.0)
            twoThirdsRect.origin.x = screen.visibleFrame.minX + screen.visibleFrame.width - twoThirdsRect.width
            
            if rectCenteredWithinRect(oneHalfRect, windowRect) {
                return WindowCalculationResult(rect: twoThirdsRect, screen: screen, resultingAction: .rightHalf)
            }
            
            if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                var oneThirdRect = screen.visibleFrame
                oneThirdRect.size.width = floor(screen.visibleFrame.width / 3.0)
                oneThirdRect.origin.x = screen.visibleFrame.origin.x + screen.visibleFrame.width - oneThirdRect.width
                return WindowCalculationResult(rect: oneThirdRect, screen: screen, resultingAction: .rightHalf)
            }
        }
        
        return WindowCalculationResult(rect: oneHalfRect, screen: screen, resultingAction: .rightHalf)
    }

    // Used to draw box for snapping
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        switch action {
        case .leftHalf:
            var oneHalfRect = visibleFrameOfScreen
            oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
            return oneHalfRect
        case .rightHalf:
            var oneHalfRect = visibleFrameOfScreen
            oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
            oneHalfRect.origin.x += oneHalfRect.size.width
            return oneHalfRect
        default:
            return nil
        }
    }
}
