//
//  NinthsRepeated.swift
//  Rectangle
//
//  Created by Daniel Schultz on 1/2/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

protocol NinthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

extension NinthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {
        
        if direction == .left {
            switch subAction {
            case .topLeftNinth:
                return WindowCalculationFactory.bottomRightNinthCalculation.orientationBasedRect
            case .topCenterNinth:
                return WindowCalculationFactory.topLeftNinthCalculation.orientationBasedRect
            case .topRightNinth:
                return WindowCalculationFactory.topCenterNinthCalculation.orientationBasedRect
            case .middleLeftNinth:
                return WindowCalculationFactory.topRightNinthCalculation.orientationBasedRect
            case .middleCenterNinth:
                return WindowCalculationFactory.middleLeftNinthCalculation.orientationBasedRect
            case .middleRightNinth:
                return WindowCalculationFactory.middleCenterNinthCalculation.orientationBasedRect
            case .bottomLeftNinth:
                return WindowCalculationFactory.middleRightNinthCalculation.orientationBasedRect
            case .bottomCenterNinth:
                return WindowCalculationFactory.bottomLeftNinthCalculation.orientationBasedRect
            case .bottomRightNinth:
                return WindowCalculationFactory.bottomCenterNinthCalculation.orientationBasedRect
            default: break
            }
        }
        
        else if direction == .right {
            switch subAction {
            case .topLeftNinth:
                return WindowCalculationFactory.topCenterNinthCalculation.orientationBasedRect
            case .topCenterNinth:
                return WindowCalculationFactory.topRightNinthCalculation.orientationBasedRect
            case .topRightNinth:
                return WindowCalculationFactory.middleLeftNinthCalculation.orientationBasedRect
            case .middleLeftNinth:
                return WindowCalculationFactory.middleCenterNinthCalculation.orientationBasedRect
            case .middleCenterNinth:
                return WindowCalculationFactory.middleRightNinthCalculation.orientationBasedRect
            case .middleRightNinth:
                return WindowCalculationFactory.bottomLeftNinthCalculation.orientationBasedRect
            case .bottomLeftNinth:
                return WindowCalculationFactory.bottomCenterNinthCalculation.orientationBasedRect
            case .bottomCenterNinth:
                return WindowCalculationFactory.bottomRightNinthCalculation.orientationBasedRect
            case .bottomRightNinth:
                return WindowCalculationFactory.topLeftNinthCalculation.orientationBasedRect
            default: break
            }
        }
        
        return nil
    }
}
