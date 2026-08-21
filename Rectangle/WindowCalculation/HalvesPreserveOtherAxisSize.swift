/// HalvesPreserveOtherAxisSize.swift

import Foundation

/// Makes Left Half, Right Half, Top Half and Bottom Half behave like keyboard tiling on Windows or
/// KDE: each action only changes the axis it belongs to (Left/Right → width, Top/Bottom → height)
/// and keeps the other axis as it is, so that Left Half followed by Top Half lands on the top left
/// quarter, Top Half followed by Left Half does the same, and Bottom Half then takes that window
/// back to Left Half.
///
/// Along its own axis an action docks the window to its edge when the window spans the whole axis,
/// expands the window to the whole axis when it is docked to the opposite edge, and leaves it alone
/// when it is already docked to that edge inside a quarter. Windows that are not tiled at all, and
/// plain halves that get the same action again, behave exactly as without the feature (including
/// cycling sizes or moving across displays on repeated executions).
///
/// Opt-in via the `halvesPreserveOtherAxisSize` default.
enum HalvesPreserveOtherAxisSize {

    /// Where a window sits along one axis of the screen.
    enum AxisState: Equatable {
        /// Spans the whole axis, or has an extent that no half action produces (floating windows).
        case full
        /// Docked to one edge. The rect carries the ungapped extent along that axis.
        case docked(HalfSplitSide, CGRect)
    }

    enum Axis {
        case horizontal, vertical
    }

    /// Slack for windows that can't take an exact frame, e.g. terminals that resize in character cells.
    static let matchingTolerance: CGFloat = 10

    /// The rect a half action produces with the feature enabled, or nil when the action should behave
    /// exactly as it does without the feature: the window is not tiled, or it is a plain half that is
    /// docked to the action's edge already, in which case Rectangle's usual repeated execution applies.
    static func rect(for params: RectCalculationParameters) -> RectResult? {
        guard let (axis, side) = axisAndSide(of: params.action) else { return nil }

        let visibleFrame = params.visibleFrameOfScreen
        var horizontal = axisState(of: params.window.rect, along: .horizontal, in: visibleFrame)
        var vertical = axisState(of: params.window.rect, along: .vertical, in: visibleFrame)
        let own = axis == .horizontal ? horizontal : vertical
        let other = axis == .horizontal ? vertical : horizontal

        let newOwn: AxisState
        switch own {
        case .full:
            // Not tiled along this axis: dock to the edge, unless the window is not tiled at all
            // (then the plain half is exactly what the action does anyway).
            guard other != .full else { return nil }
            newOwn = .docked(side, dockedRect(along: axis, side: side, in: visibleFrame))
        case .docked(let dockedSide, _) where dockedSide == side:
            // Already docked to this edge: a plain half repeats as usual (cycle sizes, move across
            // displays); inside a quarter there is nothing to do.
            guard other != .full else { return nil }
            newOwn = own
        case .docked:
            // Docked to the opposite edge: expand along this axis.
            newOwn = .full
        }

        if axis == .horizontal {
            horizontal = newOwn
        } else {
            vertical = newOwn
        }
        return compose(horizontal: horizontal, vertical: vertical, in: visibleFrame)
    }

    /// The state of `window` along `axis`: docked if its position and extent match (within tolerance)
    /// an edge-docked rect that Rectangle's half actions produce, at the active split ratio or any cycle
    /// size, with or without gaps applied.
    static func axisState(of window: CGRect, along axis: Axis, in visibleFrame: CGRect) -> AxisState {
        guard !window.isNull, !visibleFrame.isNull, visibleFrame.width > 0, visibleFrame.height > 0 else {
            return .full
        }

        let ratio = splitRatio(along: axis, in: visibleFrame)
        let gapSize = Defaults.gapSize.value

        for side in [HalfSplitSide.leading, .trailing] {
            let fractions = [side == .leading ? ratio : 1 - ratio] + CycleSize.allCases.map { $0.fraction }

            for fraction in fractions {
                let docked = dockedRect(along: axis, side: side, fraction: fraction, in: visibleFrame)
                guard extent(of: docked, along: axis) < extent(of: visibleFrame, along: axis) - matchingTolerance else {
                    continue
                }

                var candidates = [docked]
                if gapSize > 0 {
                    candidates.append(GapCalculation.applyGaps(docked,
                                                               dimension: axis == .horizontal ? .horizontal : .vertical,
                                                               sharedEdges: sharedEdge(along: axis, side: side),
                                                               gapSize: gapSize,
                                                               skipTopGap: Defaults.skipGapTopEdge.enabled))
                }

                if candidates.contains(where: { matches(window, $0, along: axis) }) {
                    return .docked(side, docked)
                }
            }
        }

        return .full
    }

    private static func compose(horizontal: AxisState, vertical: AxisState, in visibleFrame: CGRect) -> RectResult {
        var rect = visibleFrame
        if case .docked(_, let column) = horizontal {
            rect.origin.x = column.minX
            rect.size.width = column.width
        }
        if case .docked(_, let row) = vertical {
            rect.origin.y = row.minY
            rect.size.height = row.height
        }

        // Report the action that produces this rect so gaps and history match it.
        switch (horizontal, vertical) {
        case (.full, .full):
            return RectResult(rect, resultingAction: .maximize)
        case (.docked(.leading, _), .full):
            return RectResult(rect, resultingAction: .leftHalf)
        case (.docked(.trailing, _), .full):
            return RectResult(rect, resultingAction: .rightHalf)
        case (.full, .docked(.leading, _)):
            return RectResult(rect, resultingAction: .topHalf)
        case (.full, .docked(.trailing, _)):
            return RectResult(rect, resultingAction: .bottomHalf)
        case (.docked(.leading, _), .docked(.leading, _)):
            return RectResult(rect, resultingAction: .topLeft, subAction: .topLeftQuarter)
        case (.docked(.trailing, _), .docked(.leading, _)):
            return RectResult(rect, resultingAction: .topRight, subAction: .topRightQuarter)
        case (.docked(.leading, _), .docked(.trailing, _)):
            return RectResult(rect, resultingAction: .bottomLeft, subAction: .bottomLeftQuarter)
        case (.docked(.trailing, _), .docked(.trailing, _)):
            return RectResult(rect, resultingAction: .bottomRight, subAction: .bottomRightQuarter)
        }
    }

    private static func axisAndSide(of action: WindowAction) -> (Axis, HalfSplitSide)? {
        switch action {
        case .leftHalf: return (.horizontal, .leading)
        case .rightHalf: return (.horizontal, .trailing)
        case .topHalf: return (.vertical, .leading)
        case .bottomHalf: return (.vertical, .trailing)
        default: return nil
        }
    }

    private static func splitRatio(along axis: Axis, in visibleFrame: CGRect) -> Float {
        axis == .horizontal
            ? ActiveSideSplitRatios.shared.horizontalRatio(for: visibleFrame)
            : ActiveSideSplitRatios.shared.verticalRatio(for: visibleFrame)
    }

    private static func dockedRect(along axis: Axis, side: HalfSplitSide, in visibleFrame: CGRect) -> CGRect {
        let ratio = splitRatio(along: axis, in: visibleFrame)
        return dockedRect(along: axis, side: side, fraction: side == .leading ? ratio : 1 - ratio, in: visibleFrame)
    }

    private static func dockedRect(along axis: Axis, side: HalfSplitSide, fraction: Float, in visibleFrame: CGRect) -> CGRect {
        axis == .horizontal
            ? HalfSplitFrameCalculation.horizontalRect(in: visibleFrame, side: side, fraction: fraction)
            : HalfSplitFrameCalculation.verticalRect(in: visibleFrame, side: side, fraction: fraction)
    }

    private static func sharedEdge(along axis: Axis, side: HalfSplitSide) -> Edge {
        switch (axis, side) {
        case (.horizontal, .leading): return .right
        case (.horizontal, .trailing): return .left
        case (.vertical, .leading): return .bottom
        case (.vertical, .trailing): return .top
        }
    }

    private static func extent(of rect: CGRect, along axis: Axis) -> CGFloat {
        axis == .horizontal ? rect.width : rect.height
    }

    private static func matches(_ window: CGRect, _ candidate: CGRect, along axis: Axis) -> Bool {
        switch axis {
        case .horizontal:
            return abs(window.minX - candidate.minX) <= matchingTolerance
                && abs(window.width - candidate.width) <= matchingTolerance
        case .vertical:
            return abs(window.minY - candidate.minY) <= matchingTolerance
                && abs(window.height - candidate.height) <= matchingTolerance
        }
    }
}
