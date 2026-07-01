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

    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        guard params.action.isCompatibleRepeatedResizeAction(with: params.lastAction?.action) else {
            return calculateFirstRect(params)
        }

        let sortedPositions = sortedCycleSizes()
        guard !sortedPositions.isEmpty else {
            return calculateFirstRect(params)
        }

        let currentIndex = sortedPositions.firstIndex { cycleSize in
            calculateRect(for: cycleSize, params: params).rect.equalTo(params.window.rect)
        }

        if let currentIndex {
            let nextIndex = (currentIndex + 1) % sortedPositions.count
            return calculateRect(for: sortedPositions[nextIndex], params: params)
        }

        guard let count = params.lastAction?.count else {
            return calculateFirstRect(params)
        }

        return calculateRect(for: sortedPositions[cycleIndex(forExecutionCount: count, in: sortedPositions)], params: params)
    }

    func calculateRepeatedSideRect(_ params: RectCalculationParameters) -> RectResult {
        guard params.action.isCompatibleRepeatedResizeAction(with: params.lastAction?.action) else {
            return calculateFirstRect(params)
        }

        let sortedPositions = sortedCycleSizes()
        guard !sortedPositions.isEmpty else {
            return calculateFirstRect(params)
        }

        guard let count = params.lastAction?.count else {
            return calculateFirstRect(params)
        }

        var position = cycleIndex(forExecutionCount: count, in: sortedPositions)
        for _ in sortedPositions.indices {
            let result = calculateRect(for: sortedPositions[position], params: params)
            if !result.rect.equalTo(params.window.rect) {
                return result
            }
            position = (position + 1) % sortedPositions.count
        }

        return calculateFirstRect(params)
    }
    
}
