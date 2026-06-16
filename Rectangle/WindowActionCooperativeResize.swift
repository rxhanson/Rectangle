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

    func isCompatibleRepeatedResizeAction(with other: WindowAction?) -> Bool {
        guard let other else { return false }
        return cooperativeResizeSide == other.cooperativeResizeSide
            && cooperativeResizeAxis == other.cooperativeResizeAxis
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
