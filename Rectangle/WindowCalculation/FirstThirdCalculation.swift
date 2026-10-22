/// FirstThirdCalculation.swift

import Foundation

class FirstThirdCalculation: WindowCalculation, OrientationAware {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        calculateAcrossDisplays(params, toNext: false, oppositeAction: .lastThird, opposite: WindowCalculationFactory.lastThirdCalculation)
            ?? super.calculate(params)
    }

    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        guard Defaults.subsequentExecutionMode.cyclesThirdsAndFourths(hasAdjacentScreen: params.hasAdjacentScreen),
            let last = params.lastAction, let lastSubAction = last.subAction else {
            return orientationBasedRect(visibleFrameOfScreen)
        }
        
        var calculation: WindowCalculation?
        
        if last.action == .firstThird {
            switch lastSubAction {
            case .topThird, .leftThird:
                calculation = WindowCalculationFactory.centerThirdCalculation
            case .centerHorizontalThird, .centerVerticalThird:
                calculation = WindowCalculationFactory.lastThirdCalculation
            default:
                break
            }
        } else if last.action == .lastThird {
            switch lastSubAction {
            case .topThird, .leftThird:
                calculation = WindowCalculationFactory.centerThirdCalculation
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
        rect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        return RectResult(rect, subAction: .leftThird)
    }
    
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        var rect = visibleFrameOfScreen
        rect.size.height = floor(visibleFrameOfScreen.height / 3.0)
        rect.origin.y = visibleFrameOfScreen.minY + visibleFrameOfScreen.height - rect.height
        return RectResult(rect, subAction: .topThird)
    }

}
