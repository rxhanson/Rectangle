//
//  LeftHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class LeftRightHalfCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {
        
        if action == .leftHalf {
            return calculateLeft(windowRect, screen: usableScreens.currentScreen, usableScreens: usableScreens)
        } else if action == .rightHalf {
            return calculateRight(windowRect, screen: usableScreens.currentScreen, usableScreens: usableScreens)
        }
        
        return nil
    }
    
    func calculateLeft(_ windowRect: CGRect, screen: NSScreen, usableScreens: UsableScreens) -> WindowCalculationResult? {
        
        var oneHalfRect = screen.visibleFrame
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        
        if abs(windowRect.midY - oneHalfRect.midY) > 1.0 {
            return WindowCalculationResult(rect: oneHalfRect, screen: screen)
        }
        
        if Defaults.subsequentExecutionMode.value == .resize {
            
            var twoThirdsRect = oneHalfRect
            twoThirdsRect.size.width = floor(screen.visibleFrame.width * 2 / 3.0)
            
            if rectCenteredWithinRect(oneHalfRect, windowRect) {
                return WindowCalculationResult(rect: twoThirdsRect, screen: screen)
            }
            
            if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                var oneThirdRect = oneHalfRect
                oneThirdRect.size.width = floor(screen.visibleFrame.width / 3.0)
                return WindowCalculationResult(rect: oneThirdRect, screen: screen)
            }
            
        } else if Defaults.subsequentExecutionMode.value == .acrossMonitor {
            
            if rectCenteredWithinRect(oneHalfRect, windowRect) {
                if let prevScreen = usableScreens.adjacentScreens?.prev {
                    return calculateRight(windowRect, screen: prevScreen, usableScreens: usableScreens)
                } else {
                    return nil
                }
            }
        }
        
        return WindowCalculationResult(rect: oneHalfRect, screen: screen)
    }
    
    
    func calculateRight(_ windowRect: CGRect, screen: NSScreen, usableScreens: UsableScreens) -> WindowCalculationResult? {
        
        var oneHalfRect = screen.visibleFrame
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        oneHalfRect.origin.x += oneHalfRect.size.width
        
        if abs(windowRect.midY - oneHalfRect.midY) > 1.0 {
            return WindowCalculationResult(rect: oneHalfRect, screen: screen)
        }
        
        if Defaults.subsequentExecutionMode.value == .resize {
            
            var twoThirdsRect = screen.visibleFrame
            twoThirdsRect.size.width = floor(screen.visibleFrame.width * 2 / 3.0)
            twoThirdsRect.origin.x = screen.visibleFrame.minX + screen.visibleFrame.width - twoThirdsRect.width
            
            if rectCenteredWithinRect(oneHalfRect, windowRect) {
                return WindowCalculationResult(rect: twoThirdsRect, screen: screen)
            }
            
            if rectCenteredWithinRect(twoThirdsRect, windowRect) {
                var oneThirdRect = screen.visibleFrame
                oneThirdRect.size.width = floor(screen.visibleFrame.width / 3.0)
                oneThirdRect.origin.x = screen.visibleFrame.origin.x + screen.visibleFrame.width - oneThirdRect.width
                return WindowCalculationResult(rect: oneThirdRect, screen: screen)
            }
            
        } else if Defaults.subsequentExecutionMode.value == .acrossMonitor {
            
            if rectCenteredWithinRect(oneHalfRect, windowRect) {
                if let nextScreen = usableScreens.adjacentScreens?.next {
                    return calculateLeft(windowRect, screen: nextScreen, usableScreens: usableScreens)
                } else {
                    return nil
                }
            }
            
        }
        
        return WindowCalculationResult(rect: oneHalfRect, screen: screen)
    }

    // unused
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        return nil
    }
}
