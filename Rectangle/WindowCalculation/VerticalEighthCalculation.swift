/// VerticalEighthCalculation.swift

import Foundation

class VerticalEighthCalculation: WindowCalculation, OrientationAware {

    private let baseOrdinal: Int

    init(ordinal: Int) {
        baseOrdinal = ordinal
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let ordinal = resolvedOrdinal(params)
        if ordinal == baseOrdinal {
            return orientationBasedRect(params.visibleFrameOfScreen)
        }
        return VerticalEighthCalculation(ordinal: ordinal).orientationBasedRect(params.visibleFrameOfScreen)
    }

    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        let left = floor(visibleFrameOfScreen.width * CGFloat(baseOrdinal) / 8.0)
        let right = floor(visibleFrameOfScreen.width * CGFloat(baseOrdinal + 1) / 8.0)
        let rect = CGRect(x: visibleFrameOfScreen.minX + left,
                          y: visibleFrameOfScreen.minY,
                          width: right - left,
                          height: visibleFrameOfScreen.height)
        return RectResult(rect, subAction: landscapeSubAction)
    }

    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        let topOffset = floor(visibleFrameOfScreen.height * CGFloat(baseOrdinal) / 8.0)
        let bottomOffset = floor(visibleFrameOfScreen.height * CGFloat(baseOrdinal + 1) / 8.0)
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
              let previousOrdinal = lastAction.subAction?.verticalEighthOrdinal
        else {
            return baseOrdinal
        }

        switch params.action {
        case .firstVerticalEighth:
            return (previousOrdinal + 1) % 8
        case .lastVerticalEighth:
            return (previousOrdinal + 7) % 8
        default:
            return baseOrdinal
        }
    }

    private var landscapeSubAction: SubWindowAction {
        switch baseOrdinal {
        case 0: return .firstVerticalEighthLandscape
        case 1: return .secondVerticalEighthLandscape
        case 2: return .thirdVerticalEighthLandscape
        case 3: return .fourthVerticalEighthLandscape
        case 4: return .fifthVerticalEighthLandscape
        case 5: return .sixthVerticalEighthLandscape
        case 6: return .seventhVerticalEighthLandscape
        default: return .lastVerticalEighthLandscape
        }
    }

    private var portraitSubAction: SubWindowAction {
        switch baseOrdinal {
        case 0: return .firstVerticalEighthPortrait
        case 1: return .secondVerticalEighthPortrait
        case 2: return .thirdVerticalEighthPortrait
        case 3: return .fourthVerticalEighthPortrait
        case 4: return .fifthVerticalEighthPortrait
        case 5: return .sixthVerticalEighthPortrait
        case 6: return .seventhVerticalEighthPortrait
        default: return .lastVerticalEighthPortrait
        }
    }
}

private extension SubWindowAction {
    var verticalEighthOrdinal: Int? {
        switch self {
        case .firstVerticalEighthLandscape, .firstVerticalEighthPortrait: return 0
        case .secondVerticalEighthLandscape, .secondVerticalEighthPortrait: return 1
        case .thirdVerticalEighthLandscape, .thirdVerticalEighthPortrait: return 2
        case .fourthVerticalEighthLandscape, .fourthVerticalEighthPortrait: return 3
        case .fifthVerticalEighthLandscape, .fifthVerticalEighthPortrait: return 4
        case .sixthVerticalEighthLandscape, .sixthVerticalEighthPortrait: return 5
        case .seventhVerticalEighthLandscape, .seventhVerticalEighthPortrait: return 6
        case .lastVerticalEighthLandscape, .lastVerticalEighthPortrait: return 7
        default: return nil
        }
    }
}
