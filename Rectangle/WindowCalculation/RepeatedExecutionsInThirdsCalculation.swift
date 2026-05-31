/// RepeatedExecutionsInThirdsCalculation.swift

import Foundation

protocol RepeatedExecutionsInThirdsCalculation: RepeatedExecutionsCalculation {
    
    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult

}

extension RepeatedExecutionsInThirdsCalculation {
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        return calculateFractionalRect(params, fraction: 1 / 2.0)
    }
    
    func calculateRect(for cycleDivision: CycleSize, params: RectCalculationParameters) -> RectResult {
        let fraction = cycleDivision.fraction
        return calculateFractionalRect(params, fraction: fraction)
    }
    
}
