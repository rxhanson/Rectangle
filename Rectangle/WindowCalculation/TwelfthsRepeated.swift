//
//  TwelfthsRepeated.swift
//  Rectangle
//
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

protocol TwelfthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

extension TwelfthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {

        if direction == .left {
            switch subAction {
            case .topLeftTwelfth:
                return WindowCalculationFactory.bottomRightTwelfthCalculation.orientationBasedRect
            case .topCenterLeftTwelfth:
                return WindowCalculationFactory.topLeftTwelfthCalculation.orientationBasedRect
            case .topCenterRightTwelfth:
                return WindowCalculationFactory.topCenterLeftTwelfthCalculation.orientationBasedRect
            case .topRightTwelfth:
                return WindowCalculationFactory.topCenterRightTwelfthCalculation.orientationBasedRect
            case .middleLeftTwelfth:
                return WindowCalculationFactory.topRightTwelfthCalculation.orientationBasedRect
            case .middleCenterLeftTwelfth:
                return WindowCalculationFactory.middleLeftTwelfthCalculation.orientationBasedRect
            case .middleCenterRightTwelfth:
                return WindowCalculationFactory.middleCenterLeftTwelfthCalculation.orientationBasedRect
            case .middleRightTwelfth:
                return WindowCalculationFactory.middleCenterRightTwelfthCalculation.orientationBasedRect
            case .bottomLeftTwelfth:
                return WindowCalculationFactory.middleRightTwelfthCalculation.orientationBasedRect
            case .bottomCenterLeftTwelfth:
                return WindowCalculationFactory.bottomLeftTwelfthCalculation.orientationBasedRect
            case .bottomCenterRightTwelfth:
                return WindowCalculationFactory.bottomCenterLeftTwelfthCalculation.orientationBasedRect
            case .bottomRightTwelfth:
                return WindowCalculationFactory.bottomCenterRightTwelfthCalculation.orientationBasedRect
            default: break
            }
        }

        else if direction == .right {
            switch subAction {
            case .topLeftTwelfth:
                return WindowCalculationFactory.topCenterLeftTwelfthCalculation.orientationBasedRect
            case .topCenterLeftTwelfth:
                return WindowCalculationFactory.topCenterRightTwelfthCalculation.orientationBasedRect
            case .topCenterRightTwelfth:
                return WindowCalculationFactory.topRightTwelfthCalculation.orientationBasedRect
            case .topRightTwelfth:
                return WindowCalculationFactory.middleLeftTwelfthCalculation.orientationBasedRect
            case .middleLeftTwelfth:
                return WindowCalculationFactory.middleCenterLeftTwelfthCalculation.orientationBasedRect
            case .middleCenterLeftTwelfth:
                return WindowCalculationFactory.middleCenterRightTwelfthCalculation.orientationBasedRect
            case .middleCenterRightTwelfth:
                return WindowCalculationFactory.middleRightTwelfthCalculation.orientationBasedRect
            case .middleRightTwelfth:
                return WindowCalculationFactory.bottomLeftTwelfthCalculation.orientationBasedRect
            case .bottomLeftTwelfth:
                return WindowCalculationFactory.bottomCenterLeftTwelfthCalculation.orientationBasedRect
            case .bottomCenterLeftTwelfth:
                return WindowCalculationFactory.bottomCenterRightTwelfthCalculation.orientationBasedRect
            case .bottomCenterRightTwelfth:
                return WindowCalculationFactory.bottomRightTwelfthCalculation.orientationBasedRect
            case .bottomRightTwelfth:
                return WindowCalculationFactory.topLeftTwelfthCalculation.orientationBasedRect
            default: break
            }
        }

        return nil
    }
}
