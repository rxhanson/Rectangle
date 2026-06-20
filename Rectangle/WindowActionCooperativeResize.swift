/// WindowActionCooperativeResize.swift

import Foundation

extension WindowAction {
    var cooperativeResizeAxis: CornerCycleExpansionAxis? {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return Defaults.cornerCycleExpansionAxis.value
        case .leftHalf, .rightHalf:
            return .horizontal
        case .topHalf, .bottomHalf:
            return .vertical
        default:
            return nil
        }
    }

    var cooperativeResizeMovedEdge: CooperativeCornerResize.MovedEdge? {
        switch cooperativeResizeSide {
        case .left:
            return .right
        case .right:
            return .left
        case .top:
            return .bottom
        case .bottom:
            return .top
        case .none:
            return nil
        }
    }

    func isCompatibleRepeatedResizeAction(with other: WindowAction?) -> Bool {
        guard let other else { return false }
        if isCooperativeCornerAction, other.isCooperativeCornerAction {
            return self == other
        }
        return cooperativeResizeSide == other.cooperativeResizeSide
            && cooperativeResizeAxis == other.cooperativeResizeAxis
    }

    var isCooperativeCornerAction: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        default:
            return false
        }
    }

    private var cooperativeResizeSide: CooperativeResizeSide? {
        switch self {
        case .leftHalf:
            return .left
        case .rightHalf:
            return .right
        case .topHalf:
            return .top
        case .bottomHalf:
            return .bottom
        case .topLeft:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .left : .top
        case .topRight:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .right : .top
        case .bottomLeft:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .left : .bottom
        case .bottomRight:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .right : .bottom
        default:
            return nil
        }
    }
}

private enum CooperativeResizeSide {
    case left, right, top, bottom
}

extension ExecutionSource {
    var allowsCooperativeResize: Bool {
        switch self {
        case .keyboardShortcut, .dragToSnap:
            return true
        case .menuItem, .url, .titleBar:
            return false
        }
    }
}
