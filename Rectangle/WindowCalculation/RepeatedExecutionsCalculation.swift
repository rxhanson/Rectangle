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
        guard params.action.isCompatibleRepeatedResizeAction(with: params.lastAction?.action) else {
            return calculateFirstRect(params)
        }

        let sortedPositions = sortedCycleSizes()
        guard !sortedPositions.isEmpty else {
            return calculateFirstRect(params)
        }

        let currentIndex = sortedPositions.firstIndex { cycleSize in
            currentFrame(params.window.rect,
                         matchesCycleFrame: calculateRect(for: cycleSize, params: params).rect,
                         params: params)
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

    private func currentFrame(_ currentFrame: CGRect,
                              matchesCycleFrame cycleFrame: CGRect,
                              params: RectCalculationParameters) -> Bool {
        if cycleFrame.equalTo(currentFrame) {
            return true
        }

        let gappedCycleFrame = gapAdjustedCycleFrame(cycleFrame, params: params)
        if gappedCycleFrame.equalTo(currentFrame) {
            return true
        }

        guard params.action.isCooperativeCornerAction else {
            return false
        }

        let axis = Defaults.cornerCycleExpansionAxis.value
        let tolerance = max(CGFloat(4), CGFloat(Defaults.gapSize.value) * 2.0 + 4.0)
        let currentAxisSize = axisSize(currentFrame, axis)
        let expectedAxisSizes = [axisSize(cycleFrame, axis), axisSize(gappedCycleFrame, axis)]
        guard expectedAxisSizes.contains(where: { abs(currentAxisSize - $0) <= tolerance }) else {
            return false
        }

        return [cycleFrame, gappedCycleFrame].contains { expectedFrame in
            matchesFixedEdge(currentFrame, expectedFrame, action: params.action, axis: axis, tolerance: tolerance)
                && matchesPerpendicularSpan(currentFrame, expectedFrame, axis: axis, tolerance: tolerance)
        }
    }

    private func gapAdjustedCycleFrame(_ cycleFrame: CGRect, params: RectCalculationParameters) -> CGRect {
        let gapsApplicable = params.action.gapsApplicable
        guard Defaults.gapSize.value > 0,
              gapsApplicable != .none
        else {
            return cycleFrame
        }

        return GapCalculation.applyGaps(cycleFrame,
                                        dimension: gapsApplicable,
                                        sharedEdges: params.action.gapSharedEdge,
                                        gapSize: Defaults.gapSize.value,
                                        skipTopGap: Defaults.skipGapTopEdge.enabled)
    }

    private func matchesFixedEdge(_ currentFrame: CGRect,
                                  _ expectedFrame: CGRect,
                                  action: WindowAction,
                                  axis: CornerCycleExpansionAxis,
                                  tolerance: CGFloat) -> Bool {
        guard let movedEdge = action.cooperativeResizeMovedEdge else {
            return false
        }

        switch movedEdge {
        case .right, .top:
            return abs(axisMin(currentFrame, axis) - axisMin(expectedFrame, axis)) <= tolerance
        case .left, .bottom:
            return abs(axisMax(currentFrame, axis) - axisMax(expectedFrame, axis)) <= tolerance
        }
    }

    private func matchesPerpendicularSpan(_ currentFrame: CGRect,
                                          _ expectedFrame: CGRect,
                                          axis: CornerCycleExpansionAxis,
                                          tolerance: CGFloat) -> Bool {
        switch axis {
        case .horizontal:
            return abs(currentFrame.minY - expectedFrame.minY) <= tolerance
                && abs(currentFrame.maxY - expectedFrame.maxY) <= tolerance
        case .vertical:
            return abs(currentFrame.minX - expectedFrame.minX) <= tolerance
                && abs(currentFrame.maxX - expectedFrame.maxX) <= tolerance
        }
    }

    private func axisMin(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.minX : frame.minY
    }

    private func axisMax(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.maxX : frame.maxY
    }

    private func axisSize(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.width : frame.height
    }
}
