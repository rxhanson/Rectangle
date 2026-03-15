//
//  SixteenthsRepeated.swift
//  Rectangle
//
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

protocol SixteenthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

extension SixteenthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {

        if direction == .left {
            switch subAction {
            case .topLeftSixteenth:
                return WindowCalculationFactory.bottomRightSixteenthCalculation.orientationBasedRect
            case .topCenterLeftSixteenth:
                return WindowCalculationFactory.topLeftSixteenthCalculation.orientationBasedRect
            case .topCenterRightSixteenth:
                return WindowCalculationFactory.topCenterLeftSixteenthCalculation.orientationBasedRect
            case .topRightSixteenth:
                return WindowCalculationFactory.topCenterRightSixteenthCalculation.orientationBasedRect
            case .upperMiddleLeftSixteenth:
                return WindowCalculationFactory.topRightSixteenthCalculation.orientationBasedRect
            case .upperMiddleCenterLeftSixteenth:
                return WindowCalculationFactory.upperMiddleLeftSixteenthCalculation.orientationBasedRect
            case .upperMiddleCenterRightSixteenth:
                return WindowCalculationFactory.upperMiddleCenterLeftSixteenthCalculation.orientationBasedRect
            case .upperMiddleRightSixteenth:
                return WindowCalculationFactory.upperMiddleCenterRightSixteenthCalculation.orientationBasedRect
            case .lowerMiddleLeftSixteenth:
                return WindowCalculationFactory.upperMiddleRightSixteenthCalculation.orientationBasedRect
            case .lowerMiddleCenterLeftSixteenth:
                return WindowCalculationFactory.lowerMiddleLeftSixteenthCalculation.orientationBasedRect
            case .lowerMiddleCenterRightSixteenth:
                return WindowCalculationFactory.lowerMiddleCenterLeftSixteenthCalculation.orientationBasedRect
            case .lowerMiddleRightSixteenth:
                return WindowCalculationFactory.lowerMiddleCenterRightSixteenthCalculation.orientationBasedRect
            case .bottomLeftSixteenth:
                return WindowCalculationFactory.lowerMiddleRightSixteenthCalculation.orientationBasedRect
            case .bottomCenterLeftSixteenth:
                return WindowCalculationFactory.bottomLeftSixteenthCalculation.orientationBasedRect
            case .bottomCenterRightSixteenth:
                return WindowCalculationFactory.bottomCenterLeftSixteenthCalculation.orientationBasedRect
            case .bottomRightSixteenth:
                return WindowCalculationFactory.bottomCenterRightSixteenthCalculation.orientationBasedRect
            default: break
            }
        }

        else if direction == .right {
            switch subAction {
            case .topLeftSixteenth:
                return WindowCalculationFactory.topCenterLeftSixteenthCalculation.orientationBasedRect
            case .topCenterLeftSixteenth:
                return WindowCalculationFactory.topCenterRightSixteenthCalculation.orientationBasedRect
            case .topCenterRightSixteenth:
                return WindowCalculationFactory.topRightSixteenthCalculation.orientationBasedRect
            case .topRightSixteenth:
                return WindowCalculationFactory.upperMiddleLeftSixteenthCalculation.orientationBasedRect
            case .upperMiddleLeftSixteenth:
                return WindowCalculationFactory.upperMiddleCenterLeftSixteenthCalculation.orientationBasedRect
            case .upperMiddleCenterLeftSixteenth:
                return WindowCalculationFactory.upperMiddleCenterRightSixteenthCalculation.orientationBasedRect
            case .upperMiddleCenterRightSixteenth:
                return WindowCalculationFactory.upperMiddleRightSixteenthCalculation.orientationBasedRect
            case .upperMiddleRightSixteenth:
                return WindowCalculationFactory.lowerMiddleLeftSixteenthCalculation.orientationBasedRect
            case .lowerMiddleLeftSixteenth:
                return WindowCalculationFactory.lowerMiddleCenterLeftSixteenthCalculation.orientationBasedRect
            case .lowerMiddleCenterLeftSixteenth:
                return WindowCalculationFactory.lowerMiddleCenterRightSixteenthCalculation.orientationBasedRect
            case .lowerMiddleCenterRightSixteenth:
                return WindowCalculationFactory.lowerMiddleRightSixteenthCalculation.orientationBasedRect
            case .lowerMiddleRightSixteenth:
                return WindowCalculationFactory.bottomLeftSixteenthCalculation.orientationBasedRect
            case .bottomLeftSixteenth:
                return WindowCalculationFactory.bottomCenterLeftSixteenthCalculation.orientationBasedRect
            case .bottomCenterLeftSixteenth:
                return WindowCalculationFactory.bottomCenterRightSixteenthCalculation.orientationBasedRect
            case .bottomCenterRightSixteenth:
                return WindowCalculationFactory.bottomRightSixteenthCalculation.orientationBasedRect
            case .bottomRightSixteenth:
                return WindowCalculationFactory.topLeftSixteenthCalculation.orientationBasedRect
            default: break
            }
        }

        return nil
    }
}
