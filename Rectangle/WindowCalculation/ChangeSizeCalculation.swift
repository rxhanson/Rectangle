//
//  ChangeSizeCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class ChangeSizeCalculation: WindowCalculation {
    
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect? {
        let sizeOffset: CGFloat = action == .smaller ? -30.0 : 30.0
        
        var resizedWindowRect = windowRect
        resizedWindowRect.size.width = resizedWindowRect.width + sizeOffset
        resizedWindowRect.origin.x = resizedWindowRect.origin.x - floor(sizeOffset / 2.0)
        resizedWindowRect = adjustedWindowRectAgainstLeftAndRightEdgesOfScreen(originalWindowRect: windowRect,
                                                                               resizedWindowRect: resizedWindowRect,
                                                                               visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen)
        if resizedWindowRect.width >= visibleFrameOfDestinationScreen.width {
            resizedWindowRect.size.width = visibleFrameOfDestinationScreen.width
        }
        resizedWindowRect.size.height = resizedWindowRect.height + sizeOffset
        resizedWindowRect.origin.y = resizedWindowRect.origin.y - floor(sizeOffset / 2.0)
        resizedWindowRect = adjustedWindowRectAgainstTopAndBottomEdgesOfScreen(originalWindowRect: windowRect,
                                                                               resizedWindowRect: resizedWindowRect,
                                                                               visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen)
        if resizedWindowRect.height >= visibleFrameOfDestinationScreen.height {
            resizedWindowRect.size.height = visibleFrameOfDestinationScreen.height
            resizedWindowRect.origin.y = windowRect.origin.y
        }
        if againstAllEdgesOfScreen(windowRect: windowRect, visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen) && (sizeOffset < 0) {
            resizedWindowRect.size.width = windowRect.width + sizeOffset
            resizedWindowRect.origin.x = windowRect.origin.x - floor(sizeOffset / 2.0)
            resizedWindowRect.size.height = windowRect.height + sizeOffset
            resizedWindowRect.origin.y = windowRect.origin.y - floor(sizeOffset / 2.0)
        }
        if resizedWindowRectIsTooSmall(windowRect: resizedWindowRect, visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen) {
            resizedWindowRect = windowRect
        }
        return resizedWindowRect
    }
    
    private func againstEdgeOfScreen(_ gap: CGFloat) -> Bool {
        return abs(gap) <= 5.0
    }
    
    private func againstTheLeftEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfDestinationScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.origin.x - visibleFrameOfDestinationScreen.origin.x)
    }
    
    private func againstTheRightEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfDestinationScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.maxX - visibleFrameOfDestinationScreen.maxX)
    }
    
    private func againstTheTopEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfDestinationScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.maxY - visibleFrameOfDestinationScreen.maxY)
    }
    
    private func againstTheBottomEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfDestinationScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.minY - visibleFrameOfDestinationScreen.minY)
    }
    
    private func againstAllEdgesOfScreen(windowRect: CGRect, visibleFrameOfDestinationScreen: CGRect) -> Bool {
        return (againstTheLeftEdgeOfScreen(windowRect, visibleFrameOfDestinationScreen)
            && againstTheRightEdgeOfScreen(windowRect, visibleFrameOfDestinationScreen)
            && againstTheTopEdgeOfScreen(windowRect, visibleFrameOfDestinationScreen)
            && againstTheBottomEdgeOfScreen(windowRect, visibleFrameOfDestinationScreen))
    }
    
    private func adjustedWindowRectAgainstLeftAndRightEdgesOfScreen(originalWindowRect: CGRect, resizedWindowRect: CGRect, visibleFrameOfDestinationScreen: CGRect) -> CGRect {
        var adjustedWindowRect = resizedWindowRect
        if againstTheRightEdgeOfScreen(originalWindowRect, visibleFrameOfDestinationScreen) {
            adjustedWindowRect.origin.x = visibleFrameOfDestinationScreen.maxX - adjustedWindowRect.width
            if againstTheLeftEdgeOfScreen(originalWindowRect, visibleFrameOfDestinationScreen) {
                adjustedWindowRect.size.width = visibleFrameOfDestinationScreen.width
            }
        }
        if againstTheLeftEdgeOfScreen(originalWindowRect, visibleFrameOfDestinationScreen) {
            adjustedWindowRect.origin.x = visibleFrameOfDestinationScreen.minX
        }
        return adjustedWindowRect
    }
    
    private func adjustedWindowRectAgainstTopAndBottomEdgesOfScreen(originalWindowRect: CGRect, resizedWindowRect: CGRect, visibleFrameOfDestinationScreen: CGRect) -> CGRect{
        var adjustedWindowRect = resizedWindowRect
        if againstTheTopEdgeOfScreen(originalWindowRect, visibleFrameOfDestinationScreen) {
            adjustedWindowRect.origin.y = visibleFrameOfDestinationScreen.maxY - adjustedWindowRect.height
            if againstTheBottomEdgeOfScreen(originalWindowRect, visibleFrameOfDestinationScreen) {
                adjustedWindowRect.size.height = visibleFrameOfDestinationScreen.height
            }
        }
        if againstTheBottomEdgeOfScreen(originalWindowRect, visibleFrameOfDestinationScreen) {
            adjustedWindowRect.origin.y = visibleFrameOfDestinationScreen.minY
        }
        return adjustedWindowRect
    }
    
    private func resizedWindowRectIsTooSmall(windowRect: CGRect, visibleFrameOfDestinationScreen: CGRect) -> Bool {
        let minimumWindowRectWidth = floor(visibleFrameOfDestinationScreen.width / 4.0)
        let minimumWindowRectHeight = floor(visibleFrameOfDestinationScreen.height / 4.0)
        return (windowRect.width <= minimumWindowRectWidth) || (windowRect.height <= minimumWindowRectHeight)
    }
    
}
