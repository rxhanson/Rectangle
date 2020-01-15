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
    
    override func calculate(_ windowRect: CGRect, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {
        
        guard usableScreens.numScreens > 1 else { return nil }

        var screen: NSScreen?
        
        if action == .nextDisplay {
            screen = usableScreens.adjacentScreens?.next
        } else if action == .previousDisplay {
            screen = usableScreens.adjacentScreens?.prev
        }

        if let screen = screen {
            let rectResult = calculateRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: NSRectToCGRect(screen.visibleFrame), action: action)
            return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: action)
        }
        
        return nil
    }
    
    override func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        
        return centerCalculation.calculateRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: visibleFrameOfScreen, action: action)
    }
}
