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
        guard let currentWindowRect: CGRect = frontmostWindowElement?.frame else { return }
        
        var adjustedWindowRect: CGRect = currentWindowRect
        
        if adjustedWindowRect.minX < visibleFrameOfScreen.minX {
            
            adjustedWindowRect.origin.x = visibleFrameOfScreen.minX
            
        } else if adjustedWindowRect.minX + adjustedWindowRect.width > visibleFrameOfScreen.minX + visibleFrameOfScreen.width {
            
            adjustedWindowRect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width - (adjustedWindowRect.width) - CGFloat(Defaults.gapSize.value)
        }
        
        adjustedWindowRect = adjustedWindowRect.screenFlipped
        if adjustedWindowRect.minY < visibleFrameOfScreen.minY {
            
            adjustedWindowRect.origin.y = visibleFrameOfScreen.minY
            
        } else if adjustedWindowRect.minY + adjustedWindowRect.height > visibleFrameOfScreen.minY + visibleFrameOfScreen.height {
            
            adjustedWindowRect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - (adjustedWindowRect.height) - CGFloat(Defaults.gapSize.value)
        }
        
        adjustedWindowRect = adjustedWindowRect.screenFlipped
        if !currentWindowRect.equalTo(adjustedWindowRect) {
            frontmostWindowElement?.setFrame(adjustedWindowRect)
        }
    }
}
