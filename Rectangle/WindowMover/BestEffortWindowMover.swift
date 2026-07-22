/// BestEffortWindowMover.swift

import Foundation

/**
 * After a window has been moved and resized, if the window could not be resized small enough to fit the intended size, then some of the window may appear off the screen. The BestEffortWindowMover will move the window so that it fits entirely on the screen.
 */

class BestEffortWindowMover: WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let action = resultParameters.action
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        let visibleFrameOfScreen = resultParameters.visibleFrameOfScreen
        
        if action.allowedToExtendOutsideCurrentScreenArea == true && !NSScreen.screensHaveSeparateSpaces { return }
        
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
            windowElement.setFrame(adjustedWindowRect)
        }
    }
}
