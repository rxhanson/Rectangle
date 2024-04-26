//
//  MinimumWindowDimensionAware.swift
//  Rectangle
//
//  Created by Isaac Young on 23/04/24.
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

protocol ChangeWindowDimensionCalculation {
    func resizedWindowRectIsTooSmall(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool;
}

extension ChangeWindowDimensionCalculation {
    private func minimumWindowWidth() -> CGFloat {
        let defaultWidth = Defaults.minimumWindowWidth.value
        return (defaultWidth <= 0 || defaultWidth > 1)
            ? 0.25
            : CGFloat(defaultWidth)
    }
    
    private func minimumWindowHeight() -> CGFloat {
        let defaultHeight = Defaults.minimumWindowHeight.value
        return (defaultHeight <= 0 || defaultHeight > 1)
            ? 0.25
            : CGFloat(defaultHeight)
    }
    
    func resizedWindowRectIsTooSmall(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool {
        let minimumWindowRectWidth = floor(visibleFrameOfScreen.width * minimumWindowWidth())
        let minimumWindowRectHeight = floor(visibleFrameOfScreen.height * minimumWindowHeight())
        return (windowRect.width <= minimumWindowRectWidth) || (windowRect.height <= minimumWindowRectHeight)
    }
}
