//
//  QuartersRepeated.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Foundation

protocol QuartersRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

extension QuartersRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {

        if direction == .left {
            switch subAction {
            case .topLeftQuarter:
                return WindowCalculationFactory.lowerRightCalculation.quarterRect
            case .topRightQuarter:
                return WindowCalculationFactory.upperLeftCalculation.quarterRect
            case .bottomLeftQuarter:
                return WindowCalculationFactory.upperRightCalculation.quarterRect
            case .bottomRightQuarter:
                return WindowCalculationFactory.lowerLeftCalculation.quarterRect
            default: break
            }
        }

        else if direction == .right {
            switch subAction {
            case .topLeftQuarter:
                return WindowCalculationFactory.upperRightCalculation.quarterRect
            case .topRightQuarter:
                return WindowCalculationFactory.lowerLeftCalculation.quarterRect
            case .bottomLeftQuarter:
                return WindowCalculationFactory.lowerRightCalculation.quarterRect
            case .bottomRightQuarter:
                return WindowCalculationFactory.upperLeftCalculation.quarterRect
            default: break
            }
        }

        return nil
    }
}
