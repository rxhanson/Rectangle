//
//  WindowCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

protocol Calculation {
    
    func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult?
    
    func calculateRect(_ params: RectCalculationParameters) -> RectResult
}

class WindowCalculation: Calculation {
    
     func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        
        let rectResult = calculateRect(params.asRectParams())
        
        if rectResult.rect.isNull {
            return nil
        }
        
        return WindowCalculationResult(rect: rectResult.rect, screen: params.usableScreens.currentScreen, resultingAction: params.action, resultingSubAction: rectResult.subAction)
    }

    func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        RectResult(.null)
    }
    
    func rectCenteredWithinRect(_ rect1: CGRect, _ rect2: CGRect) -> Bool {
        let centeredMidX = abs(rect2.midX - rect1.midX) <= 1.0
        let centeredMidY = abs(rect2.midY - rect1.midY) <= 1.0
        return rect1.contains(rect2) && centeredMidX && centeredMidY
    }
    
    func rectFitsWithinRect(rect1: CGRect, rect2: CGRect) -> Bool {
        (rect1.width <= rect2.width) && (rect1.height <= rect2.height)
    }
    
    func isRepeatedCommand(_ params: WindowCalculationParameters) -> Bool {
        if let lastAction = params.lastAction, lastAction.action == params.action {
            let normalizedLastRect = lastAction.rect.screenFlipped
            return normalizedLastRect == params.window.rect
        }
        return false
    }
    
}

struct Window {
    let id: CGWindowID
    let rect: CGRect
}

struct WindowCalculationParameters {
    let window: Window
    let usableScreens: UsableScreens
    let action: WindowAction
    let lastAction: RectangleAction?
    
    func asRectParams(visibleFrame: CGRect? = nil, differentAction: WindowAction? = nil) -> RectCalculationParameters {
        RectCalculationParameters(window: window,
                                  visibleFrameOfScreen: visibleFrame ?? usableScreens.visibleFrameOfCurrentScreen,
                                  action: differentAction ?? action,
                                  lastAction: lastAction)
    }
    
    func withDifferentAction(_ differentAction: WindowAction) -> WindowCalculationParameters {
        .init(window: window,
              usableScreens: usableScreens,
              action: differentAction,
              lastAction: lastAction)
    }
}

struct RectCalculationParameters {
    let window: Window
    let visibleFrameOfScreen: CGRect
    let action: WindowAction
    let lastAction: RectangleAction?
}

struct RectResult {
    let rect: CGRect
    let resultingAction: WindowAction?
    let subAction: SubWindowAction?
    
    init(_ rect: CGRect, resultingAction: WindowAction? = nil, subAction: SubWindowAction? = nil) {
        self.rect = rect
        self.resultingAction = resultingAction
        self.subAction = subAction
    }
}

struct WindowCalculationResult {
    var rect: CGRect
    let screen: NSScreen
    let resultingAction: WindowAction
    let resultingSubAction: SubWindowAction?
    let resultingScreenFrame: CGRect

    init(rect: CGRect,
         screen: NSScreen,
         resultingAction: WindowAction,
         resultingSubAction: SubWindowAction? = nil,
         resultingScreenFrame: CGRect? = nil) {
        
        self.rect = rect
        self.screen = screen
        self.resultingAction = resultingAction
        self.resultingSubAction = resultingSubAction
        self.resultingScreenFrame = resultingScreenFrame ?? screen.adjustedVisibleFrame
    }
}

class WindowCalculationFactory {
    
    static let leftHalfCalculation = LeftRightHalfCalculation()
    static let rightHalfCalculation = LeftRightHalfCalculation()
    static let centerHalfCalculation = CenterHalfCalculation()
    static let bottomHalfCalculation = BottomHalfCalculation()
    static let topHalfCalculation = TopHalfCalculation()
    static let centerCalculation = CenterCalculation()
    static let nextPrevDisplayCalculation = NextPrevDisplayCalculation()
    static let maximizeCalculation = MaximizeCalculation()
    static let changeSizeCalculation = ChangeSizeCalculation()
    static let lowerLeftCalculation = LowerLeftCalculation()
    static let lowerRightCalculation = LowerRightCalculation()
    static let upperLeftCalculation = UpperLeftCalculation()
    static let upperRightCalculation = UpperRightCalculation()
    static let maxHeightCalculation = MaximizeHeightCalculation()
    static let firstThirdCalculation = FirstThirdCalculation()
    static let firstTwoThirdsCalculation = FirstTwoThirdsCalculation()
    static let centerThirdCalculation = CenterThirdCalculation()
    static let lastTwoThirdsCalculation = LastTwoThirdsCalculation()
    static let lastThirdCalculation = LastThirdCalculation()
    static let moveLeftRightCalculation = MoveLeftRightCalculation()
    static let moveUpCalculation = MoveUpDownCalculation()
    static let moveDownCalculation = MoveUpDownCalculation()
    static let almostMaximizeCalculation = AlmostMaximizeCalculation()
    static let firstFourthCalculation = FirstFourthCalculation()
    static let secondFourthCalculation = SecondFourthCalculation()
    static let thirdFourthCalculation = ThirdFourthCalculation()
    static let lastFourthCalculation = LastFourthCalculation()
    static let firstThreeFourthsCalculation = FirstThreeFourthsCalculation()
    static let lastThreeFourthsCalculation = LastThreeFourthsCalculation()
    static let topLeftSixthCalculation = TopLeftSixthCalculation()
    static let topCenterSixthCalculation = TopCenterSixthCalculation()
    static let topRightSixthCalculation = TopRightSixthCalculation()
    static let bottomLeftSixthCalculation = BottomLeftSixthCalculation()
    static let bottomCenterSixthCalculation = BottomCenterSixthCalculation()
    static let bottomRightSixthCalculation = BottomRightSixthCalculation()
    static let topLeftNinthCalculation = TopLeftNinthCalculation()
    static let topCenterNinthCalculation = TopCenterNinthCalculation()
    static let topRightNinthCalculation = TopRightNinthCalculation()
    static let middleLeftNinthCalculation = MiddleLeftNinthCalculation()
    static let middleCenterNinthCalculation = MiddleCenterNinthCalculation()
    static let middleRightNinthCalculation = MiddleRightNinthCalculation()
    static let bottomLeftNinthCalculation = BottomLeftNinthCalculation()
    static let bottomCenterNinthCalculation = BottomCenterNinthCalculation()
    static let bottomRightNinthCalculation = BottomRightNinthCalculation()
    static let topLeftThirdCalculation = TopLeftThirdCalculation()
    static let topRightThirdCalculation = TopRightThirdCalculation()
    static let bottomLeftThirdCalculation = BottomLeftThirdCalculation()
    static let bottomRightThirdCalculation = BottomRightThirdCalculation()
    static let topLeftEighthCalculation = TopLeftEighthCalculation()
    static let topCenterLeftEighthCalculation = TopCenterLeftEighthCalculation()
    static let topCenterRightEighthCalculation = TopCenterRightEighthCalculation()
    static let topRightEighthCalculation = TopRightEighthCalculation()
    static let bottomLeftEighthCalculation = BottomLeftEighthCalculation()
    static let bottomCenterLeftEighthCalculation = BottomCenterLeftEighthCalculation()
    static let bottomCenterRightEighthCalculation = BottomCenterRightEighthCalculation()
    static let bottomRightEighthCalculation = BottomRightEighthCalculation()
    static let specifiedCalculation = SpecifiedCalculation()

    static let calculationsByAction: [WindowAction: WindowCalculation] = [
     .leftHalf: leftHalfCalculation,
     .rightHalf: rightHalfCalculation,
     .maximize: maximizeCalculation,
     .maximizeHeight: maxHeightCalculation,
     .previousDisplay: nextPrevDisplayCalculation,
     .nextDisplay: nextPrevDisplayCalculation,
     .larger: changeSizeCalculation,
     .smaller: changeSizeCalculation,
     .bottomHalf: bottomHalfCalculation,
     .topHalf: topHalfCalculation,
     .center: centerCalculation,
     .bottomLeft: lowerLeftCalculation,
     .bottomRight: lowerRightCalculation,
     .topLeft: upperLeftCalculation,
     .topRight: upperRightCalculation,
     .firstThird: firstThirdCalculation,
     .firstTwoThirds: firstTwoThirdsCalculation,
     .centerThird: centerThirdCalculation,
     .lastTwoThirds: lastTwoThirdsCalculation,
     .lastThird: lastThirdCalculation,
     .moveLeft: moveLeftRightCalculation,
     .moveRight: moveLeftRightCalculation,
     .moveUp: moveUpCalculation,
     .moveDown: moveDownCalculation,
     .almostMaximize: almostMaximizeCalculation,
     .centerHalf: centerHalfCalculation,
     .firstFourth: firstFourthCalculation,
     .secondFourth: secondFourthCalculation,
     .thirdFourth: thirdFourthCalculation,
     .lastFourth: lastFourthCalculation,
     .firstThreeFourths: firstThreeFourthsCalculation,
     .lastThreeFourths: lastThreeFourthsCalculation,
     .topLeftSixth: topLeftSixthCalculation,
     .topCenterSixth: topCenterSixthCalculation,
     .topRightSixth: topRightSixthCalculation,
     .bottomLeftSixth: bottomLeftSixthCalculation,
     .bottomCenterSixth: bottomCenterSixthCalculation,
     .bottomRightSixth: bottomRightSixthCalculation,
     .topLeftNinth: topLeftNinthCalculation,
     .topCenterNinth: topCenterNinthCalculation,
     .topRightNinth: topRightNinthCalculation,
     .middleLeftNinth: middleLeftNinthCalculation,
     .middleCenterNinth: middleCenterNinthCalculation,
     .middleRightNinth: middleRightNinthCalculation,
     .bottomLeftNinth: bottomLeftNinthCalculation,
     .bottomCenterNinth: bottomCenterNinthCalculation,
     .bottomRightNinth: bottomRightNinthCalculation,
     .topLeftThird: topLeftThirdCalculation,
     .topRightThird: topRightThirdCalculation,
     .bottomLeftThird: bottomLeftThirdCalculation,
     .bottomRightThird: bottomRightThirdCalculation,
     .topLeftEighth: topLeftEighthCalculation,
     .topCenterLeftEighth: topCenterLeftEighthCalculation,
     .topCenterRightEighth: topCenterRightEighthCalculation,
     .topRightEighth: topRightEighthCalculation,
     .bottomLeftEighth: bottomLeftEighthCalculation,
     .bottomCenterLeftEighth: bottomCenterLeftEighthCalculation,
     .bottomCenterRightEighth: bottomCenterRightEighthCalculation,
     .bottomRightEighth: bottomRightEighthCalculation,
     .specified: specifiedCalculation
        //     .restore: nil
    ]
}
