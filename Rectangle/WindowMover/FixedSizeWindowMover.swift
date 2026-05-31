/// FixedSizeWindowMover.swift

import Foundation

/// Handle windows that are a fixed size, default to centering them in the proposed window area
class FixedSizeWindowMover: WindowMover {
    
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        
        let sharedEdges = resultParameters.calcResult.initialRect.screenFlipped.sharedEdges(withRect: resultParameters.visibleFrameOfScreen.screenFlipped)
        
        if Defaults.moveFixedSizeToEdge.userEnabled, sharedEdges.isCorner {
            matchSharedEdges(rect: rect, currentWindowRect: currentWindowRect, sharedEdges: sharedEdges, windowElement: windowElement)
        } else {
            centerWindowRect(rect: rect, currentWindowRect: currentWindowRect, windowElement: windowElement)
        }
    }

    func matchSharedEdges(rect: CGRect, currentWindowRect: CGRect, sharedEdges: Edge, windowElement: AccessibilityElement) {
        var adjustedWindowRect = currentWindowRect
        let flippedRect = rect.screenFlipped
        
        if sharedEdges.contains(.left) {
            adjustedWindowRect.origin.x = flippedRect.minX
        }
        if sharedEdges.contains(.right) {
            adjustedWindowRect.origin.x = flippedRect.maxX - currentWindowRect.width
        }
        if sharedEdges.contains(.top) {
            adjustedWindowRect.origin.y = flippedRect.maxY - currentWindowRect.height
        }
        if sharedEdges.contains(.bottom) {
            adjustedWindowRect.origin.y = flippedRect.minY
        }
        
        if !adjustedWindowRect.equalTo(currentWindowRect) {
            windowElement.setFrame(adjustedWindowRect)
        }
    }

    func centerWindowRect(rect: CGRect, currentWindowRect: CGRect, windowElement: AccessibilityElement) {

        var adjustedWindowRect: CGRect = currentWindowRect
        let flippedRect = rect.screenFlipped

        if currentWindowRect.size.width != rect.width {
            adjustedWindowRect.origin.x = round((rect.width - currentWindowRect.width) / 2.0) + flippedRect.minX
        }
        
        if currentWindowRect.size.height != rect.height {
            adjustedWindowRect.origin.y = round((rect.height - currentWindowRect.height) / 2.0) + flippedRect.minY
        }
        
        if !adjustedWindowRect.equalTo(currentWindowRect) {
            windowElement.setFrame(adjustedWindowRect)
        }
    }
}
