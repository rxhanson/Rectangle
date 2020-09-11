//
//  WindowCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

protocol Calculation {
    
    func calculate(_ window: Window, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult?
    
    func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult
}

class WindowCalculation: Calculation {
    
    func calculate(_ window: Window, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {
        
        let rectResult = calculateRect(window, lastAction: lastAction, visibleFrameOfScreen: usableScreens.visibleFrameOfCurrentScreen, action: action)
        
        if rectResult.rect.isNull {
            return nil
        }
        
        return WindowCalculationResult(rect: rectResult.rect, screen: usableScreens.currentScreen, resultingAction: action, resultingSubAction: rectResult.subAction)
    }

    func calculateRect(_ window: Window, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> RectResult {
        return RectResult(CGRect.null)
    }
    
    func rectCenteredWithinRect(_ rect1: CGRect, _ rect2: CGRect) -> Bool {
        let centeredMidX = abs(rect2.midX - rect1.midX) <= 1.0
        let centeredMidY = abs(rect2.midY - rect1.midY) <= 1.0
        return rect1.contains(rect2) && centeredMidX && centeredMidY
    }
    
    func rectFitsWithinRect(rect1: CGRect, rect2: CGRect) -> Bool {
        return (rect1.width <= rect2.width) && (rect1.height <= rect2.height)
    }
    
    func isLandscape(_ rect: CGRect) -> Bool {
        return rect.width > rect.height
    }
    
}

struct Window {
    let id: Int
    let rect: CGRect
}

struct RectResult {
    let rect: CGRect
    let subAction: SubWindowAction?
    
    init(_ rect: CGRect, subAction: SubWindowAction? = nil) {
        self.rect = rect
        self.subAction = subAction
    }
}

struct WindowCalculationResult {
    var rect: CGRect
    let screen: NSScreen
    let resultingAction: WindowAction
    let resultingSubAction: SubWindowAction?
    
    init(rect: CGRect, screen: NSScreen, resultingAction: WindowAction,  resultingSubAction: SubWindowAction? = nil) {
        self.rect = rect
        self.screen = screen
        self.resultingAction = resultingAction
        self.resultingSubAction = resultingSubAction
    }
}

class WindowCalculationFactory {
    
    let leftHalfCalculation = LeftRightHalfCalculation()
    let rightHalfCalculation = LeftRightHalfCalculation()
    let bottomHalfCalculation = BottomHalfCalculation()
    let topHalfCalculation = TopHalfCalculation()
    let centerCalculation = CenterCalculation()
    let nextPrevDisplayCalculation = NextPrevDisplayCalculation()
    let maximizeCalculation = MaximizeCalculation()
    let changeSizeCalculation = ChangeSizeCalculation()
    let lowerLeftCalculation = LowerLeftCalculation()
    let lowerRightCalculation = LowerRightCalculation()
    let upperLeftCalculation = UpperLeftCalculation()
    let upperRightCalculation = UpperRightCalculation()
    let maxHeightCalculation = MaximizeHeightCalculation()
    let firstThirdCalculation = FirstThirdCalculation()
    let firstTwoThirdsCalculation = FirstTwoThirdsCalculation()
    let centerThirdCalculation = CenterThirdCalculation()
    let lastTwoThirdsCalculation = LastTwoThirdsCalculation()
    let lastThirdCalculation = LastThirdCalculation()
    let moveLeftRightCalculation = MoveLeftRightCalculation()
    let moveUpCalculation = MoveUpCalculation()
    let moveDownCalculation = MoveDownCalculation()
    let almostMaximizeCalculation = AlmostMaximizeCalculation()
    
    func calculation(for action: WindowAction) -> WindowCalculation? {
        
        switch action {
        case .leftHalf: return leftHalfCalculation
        case .rightHalf: return rightHalfCalculation
        case .maximize: return maximizeCalculation
        case .maximizeHeight: return maxHeightCalculation
        case .previousDisplay: return nextPrevDisplayCalculation
        case .nextDisplay: return nextPrevDisplayCalculation
        case .larger: return changeSizeCalculation
        case .smaller: return changeSizeCalculation
        case .bottomHalf: return bottomHalfCalculation
        case .topHalf: return topHalfCalculation
        case .center: return centerCalculation
        case .bottomLeft: return lowerLeftCalculation
        case .bottomRight: return lowerRightCalculation
        case .topLeft: return upperLeftCalculation
        case .topRight: return upperRightCalculation
        case .firstThird: return firstThirdCalculation
        case .firstTwoThirds: return firstTwoThirdsCalculation
        case .centerThird: return centerThirdCalculation
        case .lastTwoThirds: return lastTwoThirdsCalculation
        case .lastThird: return lastThirdCalculation
        case .moveLeft: return moveLeftRightCalculation
        case .moveRight: return moveLeftRightCalculation
        case .moveUp: return moveUpCalculation
        case .moveDown: return moveDownCalculation
        case .almostMaximize: return almostMaximizeCalculation
        default: return nil
        }
    }
    
}
