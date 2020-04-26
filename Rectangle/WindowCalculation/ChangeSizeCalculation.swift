//
//  ChangeSizeCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class ChangeSizeCalculation: WindowCalculation {

    let minimumWindowWidth: CGFloat
    let minimumWindowHeight: CGFloat
    let sizeOffsetAbs: CGFloat

    override init() {
        let defaultHeight = Defaults.minimumWindowHeight.value
        minimumWindowHeight = (defaultHeight <= 0 || defaultHeight > 1)
            ? 0.25
            : CGFloat(defaultHeight)

        let defaultWidth = Defaults.minimumWindowWidth.value
        minimumWindowWidth = (defaultWidth <= 0 || defaultWidth > 1)
            ? 0.25
            : CGFloat(defaultWidth)

        let defaultSizeOffset = Defaults.sizeOffset.value
        sizeOffsetAbs = (defaultSizeOffset <= 0)
            ? 30.0
            : CGFloat(defaultSizeOffset)
    }

    override func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        let sizeOffset: CGFloat = action == .smaller ? -sizeOffsetAbs : sizeOffsetAbs

        var resizedWindowRect = window.rect
        resizedWindowRect.size.width = resizedWindowRect.width + sizeOffset
        resizedWindowRect.origin.x = resizedWindowRect.origin.x - floor(sizeOffset / 2.0)
        resizedWindowRect = adjustedWindowRectAgainstLeftAndRightEdgesOfScreen(originalWindowRect: window.rect,
                                                                               resizedWindowRect: resizedWindowRect,
                                                                               visibleFrameOfScreen: visibleFrameOfScreen)
        if resizedWindowRect.width >= visibleFrameOfScreen.width {
            resizedWindowRect.size.width = visibleFrameOfScreen.width
        }
        resizedWindowRect.size.height = resizedWindowRect.height + sizeOffset
        resizedWindowRect.origin.y = resizedWindowRect.origin.y - floor(sizeOffset / 2.0)
        resizedWindowRect = adjustedWindowRectAgainstTopAndBottomEdgesOfScreen(originalWindowRect: window.rect,
                                                                               resizedWindowRect: resizedWindowRect,
                                                                               visibleFrameOfScreen: visibleFrameOfScreen)
        if resizedWindowRect.height >= visibleFrameOfScreen.height {
            resizedWindowRect.size.height = visibleFrameOfScreen.height
            resizedWindowRect.origin.y = window.rect.origin.y
        }
        if againstAllEdgesOfScreen(windowRect: window.rect, visibleFrameOfScreen: visibleFrameOfScreen) && (sizeOffset < 0) {
            resizedWindowRect.size.width = window.rect.width + sizeOffset
            resizedWindowRect.origin.x = window.rect.origin.x - floor(sizeOffset / 2.0)
            resizedWindowRect.size.height = window.rect.height + sizeOffset
            resizedWindowRect.origin.y = window.rect.origin.y - floor(sizeOffset / 2.0)
        }
        if resizedWindowRectIsTooSmall(windowRect: resizedWindowRect, visibleFrameOfScreen: visibleFrameOfScreen) {
            resizedWindowRect = window.rect
        }
        return RectResult(resizedWindowRect)
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
        let minimumWindowRectWidth = floor(visibleFrameOfScreen.width * minimumWindowWidth)
        let minimumWindowRectHeight = floor(visibleFrameOfScreen.height * minimumWindowHeight)
        return (windowRect.width <= minimumWindowRectWidth) || (windowRect.height <= minimumWindowRectHeight)
    }

}
