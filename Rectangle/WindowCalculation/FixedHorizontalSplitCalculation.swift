/// FixedHorizontalSplitCalculation.swift

import Foundation

final class FixedHorizontalSplitCalculation: WindowCalculation {

    private let side: HalfSplitSide
    private let fraction: Float

    init(side: HalfSplitSide, fraction: Float) {
        self.side = side
        self.fraction = fraction
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        RectResult(HalfSplitFrameCalculation.horizontalRect(in: params.visibleFrameOfScreen,
                                                            side: side,
                                                            fraction: fraction))
    }
}
