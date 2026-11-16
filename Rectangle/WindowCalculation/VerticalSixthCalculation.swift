/// VerticalSixthCalculation.swift

import Foundation

/// A vertical sixth is one sixth of the screen, sliced along the display's long axis: a full height
/// column on a landscape display, a full width row on a portrait one.
///
/// Repeating the same chord cycles the window through the three placements available inside that
/// sixth: the whole sixth, then the half of it nearest the leading edge (top of a column, left of a
/// row), then the trailing half, then the whole sixth again.
class VerticalSixthCalculation: WindowCalculation, OrientationAware {

    private let baseOrdinal: Int

    init(ordinal: Int) {
        baseOrdinal = ordinal
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        guard Defaults.subsequentExecutionMode.value != .none,
              let lastAction = params.lastAction,
              lastAction.action == params.action,
              let previous = lastAction.subAction?.verticalSixthPlacement
        else {
            return rect(ordinal: baseOrdinal, placement: .wholeSixth, in: visibleFrameOfScreen)
        }

        if Defaults.verticalSixthsWalkAcrossScreen.userEnabled {
            return walkedRect(params: params, previousOrdinal: previous.ordinal, in: visibleFrameOfScreen)
        }

        return rect(ordinal: previous.ordinal,
                    placement: previous.placement.next,
                    in: visibleFrameOfScreen)
    }

    /// Behind the hidden `verticalSixthsWalkAcrossScreen` flag: repeating the first or last chord
    /// steps through all six positions instead of halving within one sixth.
    private func walkedRect(params: RectCalculationParameters,
                            previousOrdinal: Int,
                            in visibleFrameOfScreen: CGRect) -> RectResult {
        let ordinal: Int
        switch params.action {
        case .firstVerticalSixth:
            ordinal = (previousOrdinal + 1) % 6
        case .lastVerticalSixth:
            ordinal = (previousOrdinal + 5) % 6
        default:
            ordinal = baseOrdinal
        }
        return rect(ordinal: ordinal, placement: .wholeSixth, in: visibleFrameOfScreen)
    }

    private func rect(ordinal: Int, placement: VerticalSixthPlacement, in visibleFrameOfScreen: CGRect) -> RectResult {
        visibleFrameOfScreen.isLandscape
            ? columnRect(ordinal: ordinal, placement: placement, in: visibleFrameOfScreen)
            : rowRect(ordinal: ordinal, placement: placement, in: visibleFrameOfScreen)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        columnRect(ordinal: baseOrdinal, placement: .wholeSixth, in: visibleFrameOfScreen)
    }

    private func columnRect(ordinal: Int, placement: VerticalSixthPlacement, in visibleFrameOfScreen: CGRect) -> RectResult {
        let left = floor(visibleFrameOfScreen.width * CGFloat(ordinal) / 6.0)
        let right = floor(visibleFrameOfScreen.width * CGFloat(ordinal + 1) / 6.0)
        var column = CGRect(x: visibleFrameOfScreen.minX + left,
                            y: visibleFrameOfScreen.minY,
                            width: right - left,
                            height: visibleFrameOfScreen.height)

        if placement != .wholeSixth {
            let halfHeight = floor(column.height / 2.0)
            column.origin.y = placement == .leadingHalf ? column.maxY - halfHeight : column.minY
            column.size.height = halfHeight
        }

        return RectResult(column, subAction: .verticalSixth(ordinal: ordinal,
                                                            placement: placement,
                                                            landscape: true))
    }

    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        rowRect(ordinal: baseOrdinal, placement: .wholeSixth, in: visibleFrameOfScreen)
    }

    private func rowRect(ordinal: Int, placement: VerticalSixthPlacement, in visibleFrameOfScreen: CGRect) -> RectResult {
        let topOffset = floor(visibleFrameOfScreen.height * CGFloat(ordinal) / 6.0)
        let bottomOffset = floor(visibleFrameOfScreen.height * CGFloat(ordinal + 1) / 6.0)
        var row = CGRect(x: visibleFrameOfScreen.minX,
                         y: visibleFrameOfScreen.maxY - bottomOffset,
                         width: visibleFrameOfScreen.width,
                         height: bottomOffset - topOffset)

        if placement != .wholeSixth {
            let halfWidth = floor(row.width / 2.0)
            row.origin.x = placement == .leadingHalf ? row.minX : row.maxX - halfWidth
            row.size.width = halfWidth
        }

        return RectResult(row, subAction: .verticalSixth(ordinal: ordinal,
                                                         placement: placement,
                                                         landscape: false))
    }

}

fileprivate enum VerticalSixthPlacement: Hashable {
    case wholeSixth
    case leadingHalf
    case trailingHalf

    var next: VerticalSixthPlacement {
        switch self {
        case .wholeSixth: return .leadingHalf
        case .leadingHalf: return .trailingHalf
        case .trailingHalf: return .wholeSixth
        }
    }
}

/// The sub actions are the only record of which sixth a window was placed in, and of how far
/// through the cycle it is, so both directions are read from the same tables.
private let verticalSixthSubActionTables: [(placement: VerticalSixthPlacement, landscape: Bool, subActions: [SubWindowAction])] = [
    (.wholeSixth, true, [.firstVerticalSixthLandscape, .secondVerticalSixthLandscape, .thirdVerticalSixthLandscape,
                         .fourthVerticalSixthLandscape, .fifthVerticalSixthLandscape, .lastVerticalSixthLandscape]),
    (.leadingHalf, true, [.firstVerticalSixthTopLandscape, .secondVerticalSixthTopLandscape, .thirdVerticalSixthTopLandscape,
                          .fourthVerticalSixthTopLandscape, .fifthVerticalSixthTopLandscape, .lastVerticalSixthTopLandscape]),
    (.trailingHalf, true, [.firstVerticalSixthBottomLandscape, .secondVerticalSixthBottomLandscape, .thirdVerticalSixthBottomLandscape,
                           .fourthVerticalSixthBottomLandscape, .fifthVerticalSixthBottomLandscape, .lastVerticalSixthBottomLandscape]),
    (.wholeSixth, false, [.firstVerticalSixthPortrait, .secondVerticalSixthPortrait, .thirdVerticalSixthPortrait,
                          .fourthVerticalSixthPortrait, .fifthVerticalSixthPortrait, .lastVerticalSixthPortrait]),
    (.leadingHalf, false, [.firstVerticalSixthLeftPortrait, .secondVerticalSixthLeftPortrait, .thirdVerticalSixthLeftPortrait,
                           .fourthVerticalSixthLeftPortrait, .fifthVerticalSixthLeftPortrait, .lastVerticalSixthLeftPortrait]),
    (.trailingHalf, false, [.firstVerticalSixthRightPortrait, .secondVerticalSixthRightPortrait, .thirdVerticalSixthRightPortrait,
                            .fourthVerticalSixthRightPortrait, .fifthVerticalSixthRightPortrait, .lastVerticalSixthRightPortrait])
]

private extension SubWindowAction {

    static func verticalSixth(ordinal: Int, placement: VerticalSixthPlacement, landscape: Bool) -> SubWindowAction {
        verticalSixthSubActionTables.first { $0.placement == placement && $0.landscape == landscape }!.subActions[ordinal]
    }

    var verticalSixthPlacement: (ordinal: Int, placement: VerticalSixthPlacement)? {
        for table in verticalSixthSubActionTables {
            if let ordinal = table.subActions.firstIndex(of: self) {
                return (ordinal, table.placement)
            }
        }
        return nil
    }
}
