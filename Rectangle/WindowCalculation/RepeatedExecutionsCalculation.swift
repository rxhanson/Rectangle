/// RepeatedExecutionsCalculation.swift

import Foundation

protocol RepeatedExecutionsCalculation {
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult
    
    func calculateRect(for cycleDivision: CycleSize, params: RectCalculationParameters) -> RectResult

}

extension RepeatedExecutionsCalculation {
    
    func sortedCycleSizes() -> [CycleSize] {
        CycleSize.sortedSelectedSizes()
    }
    
    func calculateRepeatedRect(_ params: RectCalculationParameters) -> RectResult {

        if Defaults.cooperativeCornerResize.enabled {
            return CooperativeResizeCycle.nextRect(for: self, params: params)
        }

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
}

extension CornerCycleExpansionCalculation {
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        RectResult(cornerRect(params,
                              horizontalFraction: horizontalSplitFraction(params),
                              verticalFraction: verticalSplitFraction(params)))
    }
    
    func calculateRect(for cycleDivision: CycleSize, params: RectCalculationParameters) -> RectResult {
        calculateFractionalRect(params, fraction: cycleDivision.fraction)
    }
    
    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        let normalRect = calculateFirstRect(params).rect

        switch Defaults.cornerCycleExpansionAxis.value {
        case .horizontal:
            let cycledRect = cornerRect(params,
                                        horizontalFraction: fraction,
                                        verticalFraction: verticalSplitFraction(params))
            return RectResult(CGRect(x: cycledRect.origin.x,
                                     y: normalRect.origin.y,
                                     width: cycledRect.width,
                                     height: normalRect.height))
        case .vertical:
            let cycledRect = cornerRect(params,
                                        horizontalFraction: horizontalSplitFraction(params),
                                        verticalFraction: fraction)
            return RectResult(CGRect(x: normalRect.origin.x,
                                     y: cycledRect.origin.y,
                                     width: normalRect.width,
                                     height: cycledRect.height))
        }
    }
    
    func horizontalSplitFraction(_ params: RectCalculationParameters) -> Float {
        let ratio = ActiveSideSplitRatios.shared.horizontalRatio(for: params.visibleFrameOfScreen)
        return horizontalSide == .trailing ? 1.0 - ratio : ratio
    }

    func verticalSplitFraction(_ params: RectCalculationParameters) -> Float {
        let ratio = ActiveSideSplitRatios.shared.verticalRatio(for: params.visibleFrameOfScreen)
        return verticalSide == .trailing ? 1.0 - ratio : ratio
    }

    func cornerRect(_ params: RectCalculationParameters, horizontalFraction: Float, verticalFraction: Float) -> CGRect {
        HalfSplitFrameCalculation.cornerRect(in: params.visibleFrameOfScreen,
                                             horizontalSide: horizontalSide,
                                             verticalSide: verticalSide,
                                             horizontalFraction: horizontalFraction,
                                             verticalFraction: verticalFraction)
    }
}
