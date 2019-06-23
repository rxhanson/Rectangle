//
//  WindowCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

protocol WindowCalculation {
    func calculate(_ windowRect: CGRect, visibleFrameOfSourceScreen: CGRect, visibleFrameOfDestinationScreen: CGRect, action: WindowAction) -> CGRect?
}

extension WindowCalculation {

    func rectCenteredWithinRect(_ rect1: CGRect, _ rect2: CGRect) -> Bool {
        let centeredMidX = abs(rect2.midX - rect1.midX) <= 1.0
        let centeredMidY = abs(rect2.midY - rect1.midY) <= 1.0
        return rect1.contains(rect2) && centeredMidX && centeredMidY
    }
    
    func rectFitsWithinRect(rect1: CGRect, rect2: CGRect) -> Bool {
        return (rect1.width <= rect2.width) && (rect1.height <= rect2.height)
    }
    
}

class WindowCalculationFactory {
    
    let leftHalfCalculation = LeftHalfCalculation()
    let rightHalfCalculation = RightHalfCalculation()
    let bottomHalfCalculation = BottomHalfCalculation()
    let topHalfCalculation = TopHalfCalculation()
    let centerCalculation = CenterCalculation()
    let maximizeCalculation = MaximizeCalculation()
    let changeSizeCalculation = ChangeSizeCalculation()
    let lowerLeftCalculation = LowerLeftCalculation()
    let lowerRightCalculation = LowerRightCalculation()
    let upperLeftCalculation = UpperLeftCalculation()
    let upperRightCalculation = UpperRightCalculation()
    let nextPrevThirdsCalculation = NextPrevThirdsCalculation()
    let maxHeightCalculation = MaximizeHeightCalculation()
    
    func calculation(for action: WindowAction) -> WindowCalculation {
        switch action {
        case .leftHalf: return leftHalfCalculation
        case .rightHalf: return rightHalfCalculation
        case .maximize: return maximizeCalculation
        case .maximizeHeight: return maxHeightCalculation
        case .previousDisplay: return centerCalculation
        case .nextDisplay: return centerCalculation
        case .undo: return maximizeCalculation
        case .redo: return maximizeCalculation
        case .larger: return changeSizeCalculation
        case .smaller: return changeSizeCalculation
        case .bottomHalf: return bottomHalfCalculation
        case .topHalf: return topHalfCalculation
        case .center: return centerCalculation
        case .lowerLeft: return lowerLeftCalculation
        case .lowerRight: return lowerRightCalculation
        case .upperLeft: return upperLeftCalculation
        case .upperRight: return upperRightCalculation
        case .nextThird: return nextPrevThirdsCalculation
        case .previousThird: return nextPrevThirdsCalculation
        }
    }
    
}
