//
//  HalfOrDoubleDimensionCalculation.swift
//  Rectangle
//
//  Created by Isaac Young on 23/04/24.
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

class HalfOrDoubleDimensionCalculation: WindowCalculation, ChangeWindowDimensionCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let window = params.window

        let resizedWindowRect = resized(window.rect, with: params.action)
        
        var resizedAndMovedWindowRect = repositionedIfRequired(original: window.rect, resized: resizedWindowRect, after: params.action)

        let visibleFrameOfScreen = params.visibleFrameOfScreen
        if isSizeReducing(params.action), resizedWindowRectIsTooSmall(windowRect: resizedAndMovedWindowRect, visibleFrameOfScreen: visibleFrameOfScreen) {
            resizedAndMovedWindowRect = window.rect
        }
        return RectResult(resizedAndMovedWindowRect)
    }
    
    private func isSizeReducing(_ action: WindowAction) -> Bool {
        switch (action) {
        case .halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight:
            return true
        default:
            return false
        }
    }
    
    private func resized(_ windowRect: CGRect, with action: WindowAction) -> CGRect {
        var resized = windowRect
        switch (action) {
        case .halveHeightUp, .halveHeightDown:
            resized.size.height = resized.height * 0.5
        case .halveWidthLeft, .halveWidthRight:
            resized.size.width = resized.width * 0.5
        case .doubleHeightUp, .doubleHeightDown:
            resized.size.height = resized.height * 2.0
        case .doubleWidthLeft, .doubleWidthRight:
            resized.size.width = resized.width * 2.0
        default:
            break
        }
        return resized
    }
    
    private func repositionedIfRequired(original originalWindowRect: CGRect, resized resizedWindowRect: CGRect, after action: WindowAction) -> CGRect {
        switch (action) {
        case .halveHeightUp:
            return resizedWindowRect.offsetBy(dx: 0, dy: resizedWindowRect.height)
        case .halveWidthRight:
            return resizedWindowRect.offsetBy(dx: resizedWindowRect.width, dy: 0)
        case .doubleHeightDown:
            return resizedWindowRect.offsetBy(dx: 0, dy: -originalWindowRect.height)
        case .doubleWidthLeft:
            return resizedWindowRect.offsetBy(dx: -originalWindowRect.width, dy: 0)
        default:
            return resizedWindowRect
        }
    }
}
