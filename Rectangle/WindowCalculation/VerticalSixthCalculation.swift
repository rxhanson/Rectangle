/// VerticalSixthCalculation.swift

import Foundation

class VerticalSixthCalculation: WindowCalculation, OrientationAware {

    private let baseOrdinal: Int

    init(ordinal: Int) {
        baseOrdinal = ordinal
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let ordinal = resolvedOrdinal(params)
        if ordinal == baseOrdinal {
            return orientationBasedRect(params.visibleFrameOfScreen)
        }
        return VerticalSixthCalculation(ordinal: ordinal).orientationBasedRect(params.visibleFrameOfScreen)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        let left = floor(visibleFrameOfScreen.width * CGFloat(baseOrdinal) / 6.0)
        let right = floor(visibleFrameOfScreen.width * CGFloat(baseOrdinal + 1) / 6.0)
        let rect = CGRect(x: visibleFrameOfScreen.minX + left,
                          y: visibleFrameOfScreen.minY,
                          width: right - left,
                          height: visibleFrameOfScreen.height)
        return RectResult(rect, subAction: landscapeSubAction)
    }

    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        let topOffset = floor(visibleFrameOfScreen.height * CGFloat(baseOrdinal) / 6.0)
        let bottomOffset = floor(visibleFrameOfScreen.height * CGFloat(baseOrdinal + 1) / 6.0)
        let rect = CGRect(x: visibleFrameOfScreen.minX,
                          y: visibleFrameOfScreen.maxY - bottomOffset,
                          width: visibleFrameOfScreen.width,
                          height: bottomOffset - topOffset)
        return RectResult(rect, subAction: portraitSubAction)
    }

    private func resolvedOrdinal(_ params: RectCalculationParameters) -> Int {
        guard Defaults.subsequentExecutionMode.value != .none,
              let lastAction = params.lastAction,
              lastAction.action == params.action,
              let previousOrdinal = lastAction.subAction?.verticalSixthOrdinal
        else {
            return baseOrdinal
        }

        switch params.action {
        case .firstVerticalSixth:
            return (previousOrdinal + 1) % 6
        case .lastVerticalSixth:
            return (previousOrdinal + 5) % 6
        default:
            return baseOrdinal
        }
    }

    private var landscapeSubAction: SubWindowAction {
        switch baseOrdinal {
        case 0: return .firstVerticalSixthLandscape
        case 1: return .secondVerticalSixthLandscape
        case 2: return .thirdVerticalSixthLandscape
        case 3: return .fourthVerticalSixthLandscape
        case 4: return .fifthVerticalSixthLandscape
        default: return .lastVerticalSixthLandscape
        }
    }

    private var portraitSubAction: SubWindowAction {
        switch baseOrdinal {
        case 0: return .firstVerticalSixthPortrait
        case 1: return .secondVerticalSixthPortrait
        case 2: return .thirdVerticalSixthPortrait
        case 3: return .fourthVerticalSixthPortrait
        case 4: return .fifthVerticalSixthPortrait
        default: return .lastVerticalSixthPortrait
        }
    }
}

private extension SubWindowAction {
    var verticalSixthOrdinal: Int? {
        switch self {
        case .firstVerticalSixthLandscape, .firstVerticalSixthPortrait: return 0
        case .secondVerticalSixthLandscape, .secondVerticalSixthPortrait: return 1
        case .thirdVerticalSixthLandscape, .thirdVerticalSixthPortrait: return 2
        case .fourthVerticalSixthLandscape, .fourthVerticalSixthPortrait: return 3
        case .fifthVerticalSixthLandscape, .fifthVerticalSixthPortrait: return 4
        case .lastVerticalSixthLandscape, .lastVerticalSixthPortrait: return 5
        default: return nil
        }
    }
}
