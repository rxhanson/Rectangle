/// VerticalEighthCalculation.swift

import Foundation

class VerticalEighthCalculation: WindowCalculation {

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let column: CGFloat
        switch params.action {
        case .firstVerticalEighth: column = 0
        case .secondVerticalEighth: column = 1
        case .thirdVerticalEighth: column = 2
        case .fourthVerticalEighth: column = 3
        case .fifthVerticalEighth: column = 4
        case .sixthVerticalEighth: column = 5
        case .seventhVerticalEighth: column = 6
        case .lastVerticalEighth: column = 7
        default: return RectResult(.null)
        }

        let visibleFrameOfScreen = params.visibleFrameOfScreen
        let left = floor(visibleFrameOfScreen.width * column / 8.0)
        let right = floor(visibleFrameOfScreen.width * (column + 1) / 8.0)
        var rect = visibleFrameOfScreen
        rect.origin.x += left
        rect.size.width = right - left
        return RectResult(rect)
    }
}
