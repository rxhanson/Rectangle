//
//  NextPrevDisplayCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/19/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class NextPrevDisplayCalculation: WindowCalculation {
    
    let centerCalculation = CenterCalculation()
    
    func calculate(_ windowRect: CGRect, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {

        var screen: NSScreen?
        
        if action == .nextDisplay {
            screen = usableScreens.adjacentScreens?.next
        } else if action == .previousDisplay {
            screen = usableScreens.adjacentScreens?.prev
        }

        if let screen = screen {
            if let rect = calculateRect(windowRect, visibleFrameOfScreen: NSRectToCGRect(screen.visibleFrame), action: action) {
                return WindowCalculationResult(rect: rect, screen: screen, resultingAction: action)
            }
        }
        
        return nil
    }
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        
        return centerCalculation.calculateRect(windowRect, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
}
