//
//  EightsRepeated.swift
//  Rectangle
//
//  Created by Johannes Trussell Rasch on 2022-02-18.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

protocol EightsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

extension EightsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {
        
        if direction == .left {
            switch subAction {
            case .topLeftEight:
                return WindowCalculationFactory.bottomRightEightCalculation.orientationBasedRect
            case .topCenterLeftEight:
                return WindowCalculationFactory.topLeftEightCalculation.orientationBasedRect
            case .topCenterRightEight:
                return WindowCalculationFactory.topCenterLeftEightCalculation.orientationBasedRect
            case .topRightEight:
                return WindowCalculationFactory.topCenterRightEightCalculation.orientationBasedRect
            case .bottomLeftEight:
                return WindowCalculationFactory.topRightEightCalculation.orientationBasedRect
            case .bottomCenterLeftEight:
                return WindowCalculationFactory.bottomLeftEightCalculation.orientationBasedRect
            case .bottomCenterRightEight:
                return WindowCalculationFactory.bottomCenterLeftEightCalculation.orientationBasedRect
            case .bottomRightEight:
                return WindowCalculationFactory.bottomCenterRightEightCalculation.orientationBasedRect
            default: break
            }
        }
        
        else if direction == .right {
            switch subAction {
            case .topLeftEight:
                return WindowCalculationFactory.topCenterLeftEightCalculation.orientationBasedRect
            case .topCenterLeftEight:
                return WindowCalculationFactory.topCenterRightEightCalculation.orientationBasedRect
            case .topCenterRightEight:
                return WindowCalculationFactory.topRightEightCalculation.orientationBasedRect
            case .topRightEight:
                return WindowCalculationFactory.bottomLeftEightCalculation.orientationBasedRect
            case .bottomLeftEight:
                return WindowCalculationFactory.bottomCenterLeftEightCalculation.orientationBasedRect
            case .bottomCenterLeftEight:
                return WindowCalculationFactory.bottomCenterRightEightCalculation.orientationBasedRect
            case .bottomCenterRightEight:
                return WindowCalculationFactory.bottomRightEightCalculation.orientationBasedRect
            case .bottomRightEight:
                return WindowCalculationFactory.topLeftEightCalculation.orientationBasedRect
            default: break
            }
        }
        
        return nil
    }
}
