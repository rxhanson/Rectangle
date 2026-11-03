/// FirstFourthCalculation.swift

import Foundation

class FirstFourthCalculation: WindowCalculation, OrientationAware {

    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        calculateAcrossDisplays(params, toNext: false, oppositeAction: .lastFourth, opposite: WindowCalculationFactory.lastFourthCalculation)
            ?? super.calculate(params)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        guard Defaults.subsequentExecutionMode.cyclesThirdsAndFourths(hasAdjacentScreen: params.hasAdjacentScreen),
              params.action == .firstFourth,
              let last = params.lastAction,
              let lastSubAction = last.subAction
        else {
            return orientationBasedRect(visibleFrameOfScreen)
        }

        var calculation: WindowCalculation?
        if last.action == .firstFourth {
            switch lastSubAction {
            case .topFourth, .leftFourth:
                calculation = WindowCalculationFactory.secondFourthCalculation
            case .centerTopFourth, .centerLeftFourth:
                calculation = WindowCalculationFactory.thirdFourthCalculation
            case .centerBottomFourth, .centerRightFourth:
                calculation = WindowCalculationFactory.lastFourthCalculation
            default:
                break
            }
        } else if last.action == .lastFourth {
            switch lastSubAction {
            case .leftFourth, .topFourth:
                calculation = WindowCalculationFactory.secondFourthCalculation
            default:
                break
            }
        }

        if let calculation = calculation {
            return calculation.calculateRect(params)
        }
        
        return orientationBasedRect(visibleFrameOfScreen)
    }
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.width = floor(visibleFrameOfScreen.width / 4.0)
        return RectResult(rect, subAction: .leftFourth)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 4.0)
        rect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.height - rect.height
        return RectResult(rect, subAction: .topFourth)
    }
    
}
