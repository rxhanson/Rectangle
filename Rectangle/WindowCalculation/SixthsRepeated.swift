//
//  SixthsRepeated.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/26/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

protocol SixthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc?
}

enum Direction {
    case left, right
}

extension SixthsRepeated {
    func nextCalculation(subAction: SubWindowAction, direction: Direction) -> SimpleCalc? {
        
        if direction == .left {
            switch subAction {
            case .topLeftSixthLandscape:
                return WindowCalculationFactory.bottomRightSixthCalculation.orientationBasedRect
            case .topCenterSixthLandscape:
                return WindowCalculationFactory.topLeftSixthCalculation.orientationBasedRect
            case .topRightSixthLandscape:
                return WindowCalculationFactory.topCenterSixthCalculation.orientationBasedRect
            case .bottomLeftSixthLandscape:
                return WindowCalculationFactory.topRightSixthCalculation.orientationBasedRect
            case .bottomCenterSixthLandscape:
                return WindowCalculationFactory.bottomLeftSixthCalculation.orientationBasedRect
            case .bottomRightSixthLandscape:
                return WindowCalculationFactory.bottomCenterSixthCalculation.orientationBasedRect
                
            case .topLeftSixthPortrait:
                return WindowCalculationFactory.bottomRightSixthCalculation.orientationBasedRect
            case .topRightSixthPortrait:
                return WindowCalculationFactory.topLeftSixthCalculation.orientationBasedRect
            case .leftCenterSixthPortrait:
                return WindowCalculationFactory.topRightSixthCalculation.orientationBasedRect
            case .rightCenterSixthPortrait:
                return WindowCalculationFactory.topCenterSixthCalculation.orientationBasedRect
            case .bottomLeftSixthPortrait:
                return WindowCalculationFactory.bottomCenterSixthCalculation.orientationBasedRect
            case .bottomRightSixthPortrait:
                return WindowCalculationFactory.bottomLeftSixthCalculation.orientationBasedRect
            default: break
            }
        }
        
        else if direction == .right {
            switch subAction {
            case .topLeftSixthLandscape:
                return WindowCalculationFactory.topCenterSixthCalculation.orientationBasedRect
            case .topCenterSixthLandscape:
                return WindowCalculationFactory.topRightSixthCalculation.orientationBasedRect
            case .topRightSixthLandscape:
                return WindowCalculationFactory.bottomLeftSixthCalculation.orientationBasedRect
            case .bottomLeftSixthLandscape:
                return WindowCalculationFactory.bottomCenterSixthCalculation.orientationBasedRect
            case .bottomCenterSixthLandscape:
                return WindowCalculationFactory.bottomRightSixthCalculation.orientationBasedRect
            case .bottomRightSixthLandscape:
                return WindowCalculationFactory.topLeftSixthCalculation.orientationBasedRect
                
            case .topLeftSixthPortrait:
                return WindowCalculationFactory.topRightSixthCalculation.orientationBasedRect
            case .topRightSixthPortrait:
                return WindowCalculationFactory.topCenterSixthCalculation.orientationBasedRect
            case .leftCenterSixthPortrait:
                return WindowCalculationFactory.bottomCenterSixthCalculation.orientationBasedRect
            case .rightCenterSixthPortrait:
                return WindowCalculationFactory.bottomLeftSixthCalculation.orientationBasedRect
            case .bottomLeftSixthPortrait:
                return WindowCalculationFactory.bottomRightSixthCalculation.orientationBasedRect
            case .bottomRightSixthPortrait:
                return WindowCalculationFactory.topLeftSixthCalculation.orientationBasedRect
            default: break
            }
        }
        
        return nil
    }
}
