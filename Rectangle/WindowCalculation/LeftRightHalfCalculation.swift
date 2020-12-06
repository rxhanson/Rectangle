//
//  LeftHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class LeftRightHalfCalculation: WindowCalculation, RepeatedExecutionsCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        
        let usableScreens = params.usableScreens
        
        switch Defaults.subsequentExecutionMode.value {
            
        case .acrossMonitor, .acrossAndResize:
            if params.action == .leftHalf {
                return calculateLeftAcrossDisplays(params, screen: usableScreens.currentScreen)
            } else if params.action == .rightHalf {
                return calculateRightAcrossDisplays(params, screen: usableScreens.currentScreen)
            }
            return nil
        case .resize:
            let screen = usableScreens.currentScreen
            let rectResult: RectResult = calculateRepeatedRect(params.asRectParams())
            return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: params.action)
        case .none:
            let screen = usableScreens.currentScreen
            let oneHalfRect = calculateFirstRect(params.asRectParams())
            return WindowCalculationResult(rect: oneHalfRect.rect, screen: screen, resultingAction: params.action)
        }
        
    }

    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var oneHalfRect = visibleFrameOfScreen
        oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
        if params.action == .rightHalf {
            oneHalfRect.origin.x += oneHalfRect.size.width
        }
        return RectResult(oneHalfRect)
    }

    func calculateSecondRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var twoThirdsRect = visibleFrameOfScreen
        twoThirdsRect.size.width = floor(visibleFrameOfScreen.width * 2 / 3.0)
        if params.action == .rightHalf {
            twoThirdsRect.origin.x = visibleFrameOfScreen.minX + visibleFrameOfScreen.width - twoThirdsRect.width
        }
        return RectResult(twoThirdsRect)
    }

    func calculateThirdRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var oneThirdRect = visibleFrameOfScreen
        oneThirdRect.size.width = floor(visibleFrameOfScreen.width / 3.0)
        if params.action == .rightHalf {
            oneThirdRect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.width - oneThirdRect.width
        }
        return RectResult(oneThirdRect)
    }

    func calculateLeftAcrossDisplays(_ params: WindowCalculationParameters, screen: NSScreen) -> WindowCalculationResult? {
                
        if isRepeatedCommand(params) {
            if let prevScreen = params.usableScreens.adjacentScreens?.prev {
                return calculateRightAcrossDisplays(params, screen: prevScreen)
            }
        }
        
        let oneHalfRect = calculateFirstRect(params.asRectParams(visibleFrame: screen.adjustedVisibleFrame, differentAction: .leftHalf))
        return WindowCalculationResult(rect: oneHalfRect.rect, screen: screen, resultingAction: .leftHalf)
    }
    
    
    func calculateRightAcrossDisplays(_ params: WindowCalculationParameters, screen: NSScreen) -> WindowCalculationResult? {
        
        if isRepeatedCommand(params) {
            if let nextScreen = params.usableScreens.adjacentScreens?.next {
                return calculateLeftAcrossDisplays(params, screen: nextScreen)
            }
        }
        
        let oneHalfRect = calculateFirstRect(params.asRectParams(visibleFrame: screen.adjustedVisibleFrame, differentAction: .rightHalf))
        return WindowCalculationResult(rect: oneHalfRect.rect, screen: screen, resultingAction: .rightHalf)
    }

    // Used to draw box for snapping
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        if params.action == .leftHalf {
            var oneHalfRect = params.visibleFrameOfScreen
            oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
            return RectResult(oneHalfRect)
        } else {
            var oneHalfRect = params.visibleFrameOfScreen
            oneHalfRect.size.width = floor(oneHalfRect.width / 2.0)
            oneHalfRect.origin.x += oneHalfRect.size.width
            return RectResult(oneHalfRect)
        }
    }
}
