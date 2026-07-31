/// ChangeWindowDimensionCalculation.swift

import Foundation

protocol ChangeWindowDimensionCalculation {
    func resizedWindowRectIsTooSmall(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool;
}

extension ChangeWindowDimensionCalculation {
    private func minimumWindowWidth() -> CGFloat {
        minimumWindowFraction(Defaults.minimumWindowWidth)
    }

    private func minimumWindowHeight() -> CGFloat {
        minimumWindowFraction(Defaults.minimumWindowHeight)
    }

    private func minimumWindowFraction(_ preference: FloatDefault) -> CGFloat {
        let value = preference.value
        return (!value.isFinite || value < 0 || value > 1)
            ? 0.25
            : CGFloat(value)
    }
    
    func resizedWindowRectIsTooSmall(windowRect: CGRect, visibleFrameOfScreen: CGRect) -> Bool {
        let minimumWindowRectWidth = max(1, floor(visibleFrameOfScreen.width * minimumWindowWidth()))
        let minimumWindowRectHeight = max(1, floor(visibleFrameOfScreen.height * minimumWindowHeight()))
        return (windowRect.size.width < minimumWindowRectWidth)
            || (windowRect.size.height < minimumWindowRectHeight)
    }
}
