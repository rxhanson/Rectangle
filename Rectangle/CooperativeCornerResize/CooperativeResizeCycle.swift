/// CooperativeResizeCycle.swift

import Foundation

/// Chooses the next cycle size for a repeated action while cooperative resize is on, continuing
/// from where the window actually is rather than only counting executions.
enum CooperativeResizeCycle {

    static func nextRect(for calculation: RepeatedExecutionsCalculation,
                         params: RectCalculationParameters) -> RectResult {
        guard params.action == params.lastAction?.action else {
            return calculation.calculateFirstRect(params)
        }

        let sortedPositions = calculation.sortedCycleSizes()
        guard !sortedPositions.isEmpty else {
            return calculation.calculateFirstRect(params)
        }

        return isHalfAction(params.action)
            ? nextHalfRect(for: calculation, sortedPositions: sortedPositions, params: params)
            : nextRectFromCurrentFrame(for: calculation, sortedPositions: sortedPositions, params: params)
    }

    private static func isHalfAction(_ action: WindowAction) -> Bool {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return true
        default:
            return false
        }
    }

    /// Advances from the cycle size matching the window's current frame.
    private static func nextRectFromCurrentFrame(for calculation: RepeatedExecutionsCalculation,
                                                 sortedPositions: [CycleSize],
                                                 params: RectCalculationParameters) -> RectResult {
        let currentIndex = sortedPositions.firstIndex { cycleSize in
            currentFrame(params.window.rect,
                         matchesCycleFrame: calculation.calculateRect(for: cycleSize, params: params).rect,
                         params: params)
        }

        if let currentIndex {
            let nextIndex = (currentIndex + 1) % sortedPositions.count
            return calculation.calculateRect(for: sortedPositions[nextIndex], params: params)
        }

        guard let count = params.lastAction?.count else {
            return calculation.calculateFirstRect(params)
        }

        return calculation.calculateRect(for: sortedPositions[calculation.cycleIndex(forExecutionCount: count, in: sortedPositions)],
                                         params: params)
    }

    /// Advances by execution count, skipping any size the window is already at.
    private static func nextHalfRect(for calculation: RepeatedExecutionsCalculation,
                                     sortedPositions: [CycleSize],
                                     params: RectCalculationParameters) -> RectResult {
        guard let count = params.lastAction?.count else {
            return calculation.calculateFirstRect(params)
        }

        var position = calculation.cycleIndex(forExecutionCount: count, in: sortedPositions)
        for _ in sortedPositions.indices {
            let result = calculation.calculateRect(for: sortedPositions[position], params: params)
            if !result.rect.equalTo(params.window.rect) {
                return result
            }
            position = (position + 1) % sortedPositions.count
        }

        return calculation.calculateFirstRect(params)
    }

    private static func currentFrame(_ currentFrame: CGRect,
                                     matchesCycleFrame cycleFrame: CGRect,
                                     params: RectCalculationParameters) -> Bool {
        if cycleFrame.equalTo(currentFrame) {
            return true
        }

        guard CooperativeResizeCoordinator.isCornerAction(params.action) else {
            return false
        }

        let gappedCycleFrame = gapAdjustedCycleFrame(cycleFrame, params: params)
        if gappedCycleFrame.equalTo(currentFrame) {
            return true
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

    private static func gapAdjustedCycleFrame(_ cycleFrame: CGRect, params: RectCalculationParameters) -> CGRect {
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

    private static func matchesFixedEdge(_ currentFrame: CGRect,
                                         _ expectedFrame: CGRect,
                                         action: WindowAction,
                                         axis: CornerCycleExpansionAxis,
                                         tolerance: CGFloat) -> Bool {
        guard let movedEdge = CooperativeResizeCoordinator.movedEdge(for: action) else {
            return false
        }

        switch movedEdge {
        case .right, .top:
            return abs(axisMin(currentFrame, axis) - axisMin(expectedFrame, axis)) <= tolerance
        case .left, .bottom:
            return abs(axisMax(currentFrame, axis) - axisMax(expectedFrame, axis)) <= tolerance
        }
    }

    private static func matchesPerpendicularSpan(_ currentFrame: CGRect,
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

    private static func axisMin(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.minX : frame.minY
    }

    private static func axisMax(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.maxX : frame.maxY
    }

    private static func axisSize(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.width : frame.height
    }
}
