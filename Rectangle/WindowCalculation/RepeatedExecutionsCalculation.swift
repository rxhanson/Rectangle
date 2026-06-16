/// RepeatedExecutionsCalculation.swift

import Foundation

protocol RepeatedExecutionsCalculation {
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult
    
    func calculateRect(for cycleDivision: CycleSize, params: RectCalculationParameters) -> RectResult

}

extension RepeatedExecutionsCalculation {
    
    func sortedCycleSizes() -> [CycleSize] {
        let useDefaultPositions = !Defaults.cycleSizesIsChanged.enabled
        let positions = useDefaultPositions ? CycleSize.defaultSizes : Defaults.selectedCycleSizes.value
        
        return CycleSize.sortedSizes
            .filter { positions.contains($0) }
    }
    
    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        
        guard let count = params.lastAction?.count,
              params.lastAction?.action == params.action
        else {
            return calculateFirstRect(params)
        }
        
        let sortedPositions = sortedCycleSizes()
        guard !sortedPositions.isEmpty else {
            return calculateFirstRect(params)
        }
                
        let position = cycleIndex(forExecutionCount: count, in: sortedPositions)
        
        return calculateRect(for: sortedPositions[position], params: params)
    }

    func cycleIndex(forExecutionCount count: Int, in sortedPositions: [CycleSize]) -> Int {
        if sortedPositions.contains(.firstSize) {
            return count % sortedPositions.count
        }

        return max(0, count - 1) % sortedPositions.count
    }
    
}

protocol CornerCycleExpansionCalculation: RepeatedExecutionsCalculation {
    var horizontalSide: HalfSplitSide { get }
    var verticalSide: HalfSplitSide { get }
    var horizontalSplitFraction: Float { get }
    var verticalSplitFraction: Float { get }
}

extension CornerCycleExpansionCalculation {
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        RectResult(cornerRect(params.visibleFrameOfScreen,
                              horizontalFraction: horizontalSplitFraction,
                              verticalFraction: verticalSplitFraction))
    }
    
    func calculateRect(for cycleDivision: CycleSize, params: RectCalculationParameters) -> RectResult {
        calculateFractionalRect(params, fraction: cycleDivision.fraction)
    }
    
    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {
        guard params.lastAction?.action == params.action else {
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
    
    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        let normalRect = calculateFirstRect(params).rect

        switch Defaults.cornerCycleExpansionAxis.value {
        case .horizontal:
            let cycledRect = cornerRect(params.visibleFrameOfScreen,
                                        horizontalFraction: fraction,
                                        verticalFraction: verticalSplitFraction)
            return RectResult(CGRect(x: cycledRect.origin.x,
                                     y: normalRect.origin.y,
                                     width: cycledRect.width,
                                     height: normalRect.height))
        case .vertical:
            let cycledRect = cornerRect(params.visibleFrameOfScreen,
                                        horizontalFraction: horizontalSplitFraction,
                                        verticalFraction: fraction)
            return RectResult(CGRect(x: normalRect.origin.x,
                                     y: cycledRect.origin.y,
                                     width: normalRect.width,
                                     height: cycledRect.height))
        }
    }
    
    private func cornerRect(_ visibleFrameOfScreen: CGRect, horizontalFraction: Float, verticalFraction: Float) -> CGRect {
        HalfSplitFrameCalculation.cornerRect(in: visibleFrameOfScreen,
                                             horizontalSide: horizontalSide,
                                             verticalSide: verticalSide,
                                             horizontalFraction: horizontalFraction,
                                             verticalFraction: verticalFraction)
    }
}
