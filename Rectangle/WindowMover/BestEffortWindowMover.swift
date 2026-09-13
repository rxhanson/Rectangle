/// BestEffortWindowMover.swift

import Foundation

enum WindowFrameBounds {
    static func constrained(_ frame: CGRect, to screenFrame: CGRect, gap: CGFloat) -> CGRect {
        guard !frame.isNull, !frame.isInfinite, !screenFrame.isNull, !screenFrame.isInfinite else { return frame }
        var result = frame
        if result.minX < screenFrame.minX {
            result.origin.x = screenFrame.minX
        } else if result.maxX > screenFrame.maxX {
            result.origin.x = screenFrame.maxX - result.width - gap
        }

        // Window coordinates grow downwards; preserve the normal mover's bottom-first correction.
        if result.maxY > screenFrame.maxY {
            result.origin.y = screenFrame.maxY - result.height
        } else if result.minY < screenFrame.minY {
            result.origin.y = screenFrame.minY + gap
        }
        return result
    }
}

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
        
        let adjustedWindowRect = WindowFrameBounds.constrained(currentWindowRect,
                                                               to: visibleFrameOfScreen.screenFlipped,
                                                               gap: CGFloat(Defaults.gapSize.value))
        if !currentWindowRect.equalTo(adjustedWindowRect) {
            windowElement.setFrame(adjustedWindowRect)
        }
    }
}
