//
//  EighthsRepeated.swift
//  Rectangle
//
//  Created by Johannes Trussell Rasch on 2022-02-18.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

protocol EighthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

extension EighthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {
        
        if direction == .left {
            switch subAction {
            case .topLeftEighth:
                return WindowCalculationFactory.bottomRightEighthCalculation.orientationBasedRect
            case .topCenterLeftEighth:
                return WindowCalculationFactory.topLeftEighthCalculation.orientationBasedRect
            case .topCenterRightEighth:
                return WindowCalculationFactory.topCenterLeftEighthCalculation.orientationBasedRect
            case .topRightEighth:
                return WindowCalculationFactory.topCenterRightEighthCalculation.orientationBasedRect
            case .bottomLeftEighth:
                return WindowCalculationFactory.topRightEighthCalculation.orientationBasedRect
            case .bottomCenterLeftEighth:
                return WindowCalculationFactory.bottomLeftEighthCalculation.orientationBasedRect
            case .bottomCenterRightEighth:
                return WindowCalculationFactory.bottomCenterLeftEighthCalculation.orientationBasedRect
            case .bottomRightEighth:
                return WindowCalculationFactory.bottomCenterRightEighthCalculation.orientationBasedRect
            default: break
            }
        }
        
        else if direction == .right {
            switch subAction {
            case .topLeftEighth:
                return WindowCalculationFactory.topCenterLeftEighthCalculation.orientationBasedRect
            case .topCenterLeftEighth:
                return WindowCalculationFactory.topCenterRightEighthCalculation.orientationBasedRect
            case .topCenterRightEighth:
                return WindowCalculationFactory.topRightEighthCalculation.orientationBasedRect
            case .topRightEighth:
                return WindowCalculationFactory.bottomLeftEighthCalculation.orientationBasedRect
            case .bottomLeftEighth:
                return WindowCalculationFactory.bottomCenterLeftEighthCalculation.orientationBasedRect
            case .bottomCenterLeftEighth:
                return WindowCalculationFactory.bottomCenterRightEighthCalculation.orientationBasedRect
            case .bottomCenterRightEighth:
                return WindowCalculationFactory.bottomRightEighthCalculation.orientationBasedRect
            case .bottomRightEighth:
                return WindowCalculationFactory.topLeftEighthCalculation.orientationBasedRect
            default: break
            }
        }
        
        return nil
    }
}
