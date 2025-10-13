//
//  ChangeSizeCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class ChangeSizeCalculation: WindowCalculation, ChangeWindowDimensionCalculation {

    let screenEdgeGapSize: CGFloat
    let sizeOffsetAbs: CGFloat
    let curtainChangeSize = Defaults.curtainChangeSize.enabled != false

    var widthOffsetAbs: CGFloat {
        CGFloat(Defaults.widthStepSize.value)
    }

    override init() {
        let windowGapSize = Defaults.gapSize.value
        screenEdgeGapSize = (windowGapSize <= 0) ? 5.0 : CGFloat(windowGapSize)

        let defaultSizeOffset = Defaults.sizeOffset.value
        sizeOffsetAbs = (defaultSizeOffset <= 0)
            ? 30.0
            : CGFloat(defaultSizeOffset)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {

        let sizeOffset: CGFloat
        switch params.action {
            case .larger, .largerHeight:
                sizeOffset = sizeOffsetAbs
            case .smaller, .smallerHeight:
                sizeOffset = -sizeOffsetAbs
            case .largerWidth:
                sizeOffset = widthOffsetAbs
            case .smallerWidth:
                sizeOffset = -widthOffsetAbs
            default:
                sizeOffset = 0
        }

        let visibleFrameOfScreen = params.visibleFrameOfScreen
        let window = params.window

        // Calculate Width

        var resizedWindowRect = window.rect

        if [.larger, .smaller, .largerWidth, .smallerWidth].contains(params.action) {
            resizedWindowRect.size.width = resizedWindowRect.width + sizeOffset
            resizedWindowRect.origin.x = resizedWindowRect.minX - floor(sizeOffset / 2.0)

            if curtainChangeSize {
                resizedWindowRect = againstLeftAndRightScreenEdges(
                    originalWindowRect: window.rect,
                    resizedWindowRect: resizedWindowRect,
                    visibleFrameOfScreen: visibleFrameOfScreen
                )
            }

            if resizedWindowRect.width >= visibleFrameOfScreen.width {
                resizedWindowRect.size.width = visibleFrameOfScreen.width
            }
        }

        // Calculate Height

        if [.larger, .smaller, .largerHeight, .smallerHeight].contains(params.action) {
            resizedWindowRect.size.height = resizedWindowRect.height + sizeOffset
            resizedWindowRect.origin.y = resizedWindowRect.minY - floor(sizeOffset / 2.0)

            if curtainChangeSize, params.action != .smallerHeight {
                resizedWindowRect = againstTopAndBottomScreenEdges(
                    originalWindowRect: window.rect,
                    resizedWindowRect: resizedWindowRect,
                    visibleFrameOfScreen: visibleFrameOfScreen
                )
            }

            if resizedWindowRect.height >= visibleFrameOfScreen.height {
                resizedWindowRect.size.height = visibleFrameOfScreen.height
                resizedWindowRect.origin.y = params.window.rect.minY
            }
        }


        if againstAllScreenEdges(windowRect: window.rect, visibleFrameOfScreen: visibleFrameOfScreen) && (sizeOffset < 0) {
            resizedWindowRect.size.width = params.window.rect.width + sizeOffset
            resizedWindowRect.origin.x = params.window.rect.origin.x - floor(sizeOffset / 2.0)
            resizedWindowRect.size.height = params.window.rect.height + sizeOffset
            resizedWindowRect.origin.y = params.window.rect.origin.y - floor(sizeOffset / 2.0)
        }
        
        if [.smaller, .smallerWidth, .smallerHeight].contains(params.action), resizedWindowRectIsTooSmall(windowRect: resizedWindowRect, visibleFrameOfScreen: visibleFrameOfScreen) {
            resizedWindowRect = window.rect
        }

        return RectResult(resizedWindowRect)
    }

    private func againstScreenEdge(_ gap: CGFloat) -> Bool {
        return abs(gap) <= screenEdgeGapSize
    }

    private func againstLeftScreenEdge(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstScreenEdge(windowRect.minX - visibleFrameOfScreen.minX)
    }

    private func againstRightScreenEdge(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstScreenEdge(windowRect.maxX - visibleFrameOfScreen.maxX)
    }

    private func againstTopScreenEdge(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstScreenEdge(windowRect.maxY - visibleFrameOfScreen.maxY)
    }

    private func againstBottomScreenEdge(_ windowRect: CGRect, _ visibleFrameOfScreen: CGRect) -> Bool {
        return againstScreenEdge(windowRect.minY - visibleFrameOfScreen.minY)
    }

    private func againstAllScreenEdges(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool {
        return (againstLeftScreenEdge(windowRect, visibleFrameOfScreen)
            && againstRightScreenEdge(windowRect, visibleFrameOfScreen)
            && againstTopScreenEdge(windowRect, visibleFrameOfScreen)
            && againstBottomScreenEdge(windowRect, visibleFrameOfScreen))
    }

    private func againstLeftAndRightScreenEdges(originalWindowRect: CGRect, resizedWindowRect: CGRect, visibleFrameOfScreen: CGRect) -> CGRect {
        var adjustedWindowRect = resizedWindowRect
        if againstRightScreenEdge(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.x = visibleFrameOfScreen.maxX - adjustedWindowRect.width - CGFloat(Defaults.gapSize.value)
            if againstLeftScreenEdge(originalWindowRect, visibleFrameOfScreen) {
                adjustedWindowRect.size.width = visibleFrameOfScreen.width - (CGFloat(Defaults.gapSize.value) * 2)
            }
        }
        if againstLeftScreenEdge(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.x = visibleFrameOfScreen.minX + CGFloat(Defaults.gapSize.value)
        }
        return adjustedWindowRect
    }

    private func againstTopAndBottomScreenEdges(originalWindowRect: CGRect, resizedWindowRect: CGRect, visibleFrameOfScreen: CGRect) -> CGRect{
        var adjustedWindowRect = resizedWindowRect
        if againstTopScreenEdge(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.y = visibleFrameOfScreen.maxY - adjustedWindowRect.height - CGFloat(Defaults.gapSize.value)
            if againstBottomScreenEdge(originalWindowRect, visibleFrameOfScreen) {
                adjustedWindowRect.size.height = visibleFrameOfScreen.height - (CGFloat(Defaults.gapSize.value) * 2)
            }
        }
        if againstBottomScreenEdge(originalWindowRect, visibleFrameOfScreen) {
            adjustedWindowRect.origin.y = visibleFrameOfScreen.minY + CGFloat(Defaults.gapSize.value)
        }
        return adjustedWindowRect
    }

}
