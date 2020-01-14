//
//  BestEffortWindowMover.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

/**
 * After a window has been moved and resized, if the window could not be resized small enough to fit the intended size, then some of the window may appear off the screen. The BestEffortWindowMover will move the window so that it fits entirely on the screen.
 */

class BestEffortWindowMover: WindowMover {
    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        guard let currentWindowRect: CGRect = frontmostWindowElement?.rectOfElement() else { return }
        
        var adjustedWindowRect: CGRect = currentWindowRect
        
        if adjustedWindowRect.origin.x < visibleFrameOfScreen.origin.x {
            
            adjustedWindowRect.origin.x = visibleFrameOfScreen.origin.x
            
        } else if adjustedWindowRect.origin.x + adjustedWindowRect.size.width > visibleFrameOfScreen.origin.x + visibleFrameOfScreen.size.width {
            
            adjustedWindowRect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.size.width - (adjustedWindowRect.size.width)
        }
        
        adjustedWindowRect = AccessibilityElement.normalizeCoordinatesOf(adjustedWindowRect , frameOfScreen: frameOfScreen)
        if adjustedWindowRect.origin.y < visibleFrameOfScreen.origin.y {
            
            adjustedWindowRect.origin.y = visibleFrameOfScreen.origin.y
            
        } else if adjustedWindowRect.origin.y + adjustedWindowRect.size.height > visibleFrameOfScreen.origin.y + visibleFrameOfScreen.size.height {
            
            adjustedWindowRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.size.height - (adjustedWindowRect.size.height)
        }
        
        adjustedWindowRect = AccessibilityElement.normalizeCoordinatesOf(adjustedWindowRect, frameOfScreen: frameOfScreen)
        if !currentWindowRect.equalTo(adjustedWindowRect) {
            frontmostWindowElement?.setRectOf(adjustedWindowRect)
        }
    }
}
