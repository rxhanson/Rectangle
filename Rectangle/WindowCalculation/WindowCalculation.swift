//
//  WindowCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

protocol WindowCalculation {
    
    func calculate(_ windowRect: CGRect, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult?
    
    func calculateRect(_ windowRect: CGRect, lastAction: RectangleAction?, visibleFrameOfScreen: CGRect, action: WindowAction) -> CGRect?
}

extension WindowCalculation {
    
    func calculate(_ windowRect: CGRect, lastAction: RectangleAction?, usableScreens: UsableScreens, action: WindowAction) -> WindowCalculationResult? {
        
            if let rect = calculateRect(windowRect, lastAction: lastAction, visibleFrameOfScreen: usableScreens.currentScreen.visibleFrame, action: action) {
            
            return WindowCalculationResult(rect: rect, screen: usableScreens.currentScreen, resultingAction: action)
        }
        
        return nil
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
    
    func applyUselessGaps(_ rect: CGRect, sharedEdges: Edge = .none) -> CGRect {
        let uselessGapSize = CGFloat(Defaults.uselessGaps.value)
        var withGaps = rect.insetBy(dx: uselessGapSize, dy: uselessGapSize)

        if (sharedEdges.contains(.left)) {
            withGaps = CGRect(
                x: withGaps.origin.x - (uselessGapSize / 2),
                y: withGaps.origin.y,
                width: withGaps.width + (uselessGapSize / 2),
                height: withGaps.height
            )
        }

        if (sharedEdges.contains(.right)) {
            withGaps = CGRect(
                x: withGaps.origin.x,
                y: withGaps.origin.y,
                width: withGaps.width + (uselessGapSize / 2),
                height: withGaps.height
            )
        }

        if (sharedEdges.contains(.top)) {
            withGaps = CGRect(
                x: withGaps.origin.x,
                y: withGaps.origin.y - (uselessGapSize / 2),
                width: withGaps.width,
                height: withGaps.height + (uselessGapSize / 2)
            )
        }

        if (sharedEdges.contains(.bottom)) {
            withGaps = CGRect(
                x: withGaps.origin.x,
                y: withGaps.origin.y,
                width: withGaps.width,
                height: withGaps.height + (uselessGapSize / 2)
            )
        }

        return withGaps
    }

}

struct Edge: OptionSet {
    let rawValue: Int

    static let left = Edge(rawValue: 1 << 0)
    static let right = Edge(rawValue: 1 << 1)
    static let top = Edge(rawValue: 1 << 2)
    static let bottom = Edge(rawValue: 1 << 3)

    static let all: Edge = [.left, .right, .top, .bottom]
    static let none: Edge = []
}

struct WindowCalculationResult {
    let rect: CGRect
    let screen: NSScreen
    let resultingAction: WindowAction
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
