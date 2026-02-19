//
//  LeftHalfCalculation.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class LeftRightHalfCalculation: WindowCalculation, RepeatedExecutionsInThirdsCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        
        let usableScreens = params.usableScreens
        
        switch Defaults.subsequentExecutionMode.value {
            
        case .acrossMonitor:
            return calculateAcrossDisplays(params)
        case .acrossAndResize:
            if usableScreens.numScreens == 1 {
                return calculateResize(params)
            }
            return calculateAcrossDisplays(params)
        case .resize:
            return calculateResize(params)
        case .none, .cycleMonitor:
            let screen = usableScreens.currentScreen
            let oneHalfRect = calculateFirstRect(params.asRectParams())
            return WindowCalculationResult(rect: oneHalfRect.rect, screen: screen, resultingAction: params.action)
        }
        
    }
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        let ratio = Defaults.horizontalSplitRatio.value / 100.0
        let fraction = params.action == .rightHalf ? 1.0 - ratio : ratio
        return calculateFractionalRect(params, fraction: fraction)
    }

    func calculateFractionalRect(_ params: RectCalculationParameters, fraction: Float) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen

        var rect = visibleFrameOfScreen

        rect.size.width = floor(visibleFrameOfScreen.width * CGFloat(fraction))
        if params.action == .rightHalf {
            rect.origin.x = visibleFrameOfScreen.maxX - rect.width
        }

        return RectResult(rect)
    }

    func calculateResize(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let screen = params.usableScreens.currentScreen
        let rectResult: RectResult = calculateRepeatedRect(params.asRectParams())
        return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: params.action)
    }
    
    func calculateAcrossDisplays(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let screen = params.usableScreens.currentScreen
        return params.action == .rightHalf
            ? calculateRightAcrossDisplays(params, screen: screen)
            : calculateLeftAcrossDisplays(params, screen: screen)
    }
    
    func calculateLeftAcrossDisplays(_ params: WindowCalculationParameters, screen: NSScreen) -> WindowCalculationResult? {
                
        if isRepeatedCommand(params) {
            if let prevScreen = params.usableScreens.adjacentScreens?.prev {

                if Defaults.subsequentExecutionMode.value == .acrossAndResize && prevScreen == params.usableScreens.screensOrdered.last {
                    return calculateResize(params)
                }

                return calculateRightAcrossDisplays(params.withDifferentAction(.rightHalf), screen: prevScreen)
            }
        }
        
        let oneHalfRect = calculateFirstRect(params.asRectParams(visibleFrame: screen.adjustedVisibleFrame(params.ignoreTodo), differentAction: .leftHalf))
        return WindowCalculationResult(rect: oneHalfRect.rect, screen: screen, resultingAction: .leftHalf)
    }
    
    
    func calculateRightAcrossDisplays(_ params: WindowCalculationParameters, screen: NSScreen) -> WindowCalculationResult? {
        
        if isRepeatedCommand(params) {
            if let nextScreen = params.usableScreens.adjacentScreens?.next {
                
                if Defaults.subsequentExecutionMode.value == .acrossAndResize && nextScreen == params.usableScreens.screensOrdered.first {
                    return calculateResize(params)
                }

                return calculateLeftAcrossDisplays(params.withDifferentAction(.leftHalf), screen: nextScreen)
            }
        }
        
        let oneHalfRect = calculateFirstRect(params.asRectParams(visibleFrame: screen.adjustedVisibleFrame(params.ignoreTodo), differentAction: .rightHalf))
        return WindowCalculationResult(rect: oneHalfRect.rect, screen: screen, resultingAction: .rightHalf)
    }

    // Used to draw box for snapping
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let ratio = CGFloat(Defaults.horizontalSplitRatio.value / 100.0)
        var rect = params.visibleFrameOfScreen
        let leftWidth = floor(rect.width * ratio)
        if params.action == .leftHalf {
            rect.size.width = leftWidth
        } else {
            rect.size.width = rect.width - leftWidth
            rect.origin.x += leftWidth
        }
        return RectResult(rect)
    }
}
