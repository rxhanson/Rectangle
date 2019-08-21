//
//  ChangeSizeCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class ChangeSizeCalculation: WindowCalculation {
    
    func calculateRect(_ windowRect: CGRect, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect? {
        let sizeOffset: CGFloat = action == .smaller ? -30.0 : 30.0
        
        var resizedWindowRect = windowRect
        resizedWindowRect.size.width = resizedWindowRect.width + sizeOffset
        resizedWindowRect.origin.x = resizedWindowRect.origin.x - floor(sizeOffset / 2.0)
        resizedWindowRect = adjustedWindowRectAgainstLeftAndRightEdgesOfScreen(originalWindowRect: windowRect,
                                                                               resizedWindowRect: resizedWindowRect,
                                                                               visibleFrameOfScreen: visibleFrameOfScreen)
        if resizedWindowRect.width >= visibleFrameOfScreen.width {
            resizedWindowRect.size.width = visibleFrameOfScreen.width
        }
        resizedWindowRect.size.height = resizedWindowRect.height + sizeOffset
        resizedWindowRect.origin.y = resizedWindowRect.origin.y - floor(sizeOffset / 2.0)
        resizedWindowRect = adjustedWindowRectAgainstTopAndBottomEdgesOfScreen(originalWindowRect: windowRect,
                                                                               resizedWindowRect: resizedWindowRect,
                                                                               visibleFrameOfScreen: visibleFrameOfScreen)
        if resizedWindowRect.height >= visibleFrameOfScreen.height {
            resizedWindowRect.size.height = visibleFrameOfScreen.height
            resizedWindowRect.origin.y = windowRect.origin.y
        }
        if againstAllEdgesOfScreen(windowRect: windowRect, visibleFrameOfScreen: visibleFrameOfScreen) && (sizeOffset < 0) {
            resizedWindowRect.size.width = windowRect.width + sizeOffset
            resizedWindowRect.origin.x = windowRect.origin.x - floor(sizeOffset / 2.0)
            resizedWindowRect.size.height = windowRect.height + sizeOffset
            resizedWindowRect.origin.y = windowRect.origin.y - floor(sizeOffset / 2.0)
        }
        if resizedWindowRectIsTooSmall(windowRect: resizedWindowRect, visibleFrameOfScreen: visibleFrameOfScreen) {
            resizedWindowRect = windowRect
        }
        return resizedWindowRect
    }
    
    private func againstEdgeOfScreen(_ gap: CGFloat) -> Bool {
        return abs(gap) <= 5.0
    }
    
    private func againstTheLeftEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.origin.x - visibleFrameOfScreen.origin.x)
    }
    
    private func againstTheRightEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.maxX - visibleFrameOfScreen.maxX)
    }
    
    private func againstTheTopEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.maxY - visibleFrameOfScreen.maxY)
    }
    
    private func againstTheBottomEdgeOfScreen(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstEdgeOfScreen(windowRect.minY - visibleFrameOfScreen.minY)
    }
    
    private func againstAllEdgesOfScreen(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool {
        return (againstTheLeftEdgeOfScreen(windowRect, visibleFrameOfScreen)
            && againstTheRightEdgeOfScreen(windowRect, visibleFrameOfScreen)
            && againstTheTopEdgeOfScreen(windowRect, visibleFrameOfScreen)
            && againstTheBottomEdgeOfScreen(windowRect, visibleFrameOfScreen))
    }
    
    private func adjustedWindowRectAgainstLeftAndRightEdgesOfScreen(originalWindowRect: CGRect, resizedWindowRect: CGRect, visibleFrameOfScreen: CGRect) -> CGRect {
        var adjustedWindowRect = resizedWindowRect
        if againstTheRightEdgeOfScreen(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.x = visibleFrameOfScreen.maxX - adjustedWindowRect.width
            if againstTheLeftEdgeOfScreen(originalWindowRect, visibleFrameOfScreen) {
                adjustedWindowRect.size.width = visibleFrameOfScreen.width
            }
        }
        if againstTheLeftEdgeOfScreen(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.x = visibleFrameOfScreen.minX
        }
        return adjustedWindowRect
    }
    
    private func adjustedWindowRectAgainstTopAndBottomEdgesOfScreen(originalWindowRect: CGRect, resizedWindowRect: CGRect, visibleFrameOfScreen: CGRect) -> CGRect{
        var adjustedWindowRect = resizedWindowRect
        if againstTheTopEdgeOfScreen(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.y = visibleFrameOfScreen.maxY - adjustedWindowRect.height
            if againstTheBottomEdgeOfScreen(originalWindowRect, visibleFrameOfScreen) {
                adjustedWindowRect.size.height = visibleFrameOfScreen.height
            }
        }
        if againstTheBottomEdgeOfScreen(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.y = visibleFrameOfScreen.minY
        }
        return adjustedWindowRect
    }
    
    private func resizedWindowRectIsTooSmall(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool {
        let minimumWindowRectWidth = floor(visibleFrameOfScreen.width / 4.0)
        let minimumWindowRectHeight = floor(visibleFrameOfScreen.height / 4.0)
        return (windowRect.width <= minimumWindowRectWidth) || (windowRect.height <= minimumWindowRectHeight)
    }
    
}
