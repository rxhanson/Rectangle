//
//  MoveLeftRightCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 7/26/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

// Applicable options:
// Defaults.subsequentExecutionMode.traversesDisplays (if enabled, resizing will be limited to a single 50%)
// Defaults.centeredDirectionalMove.enabled (independent)
// Defaults.resizeOnDirectionalMove.enabled

class MoveLeftRightCalculation: WindowCalculation, RepeatedExecutionsCalculation {
    
    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        
        if !Defaults.subsequentExecutionMode.traversesDisplays {
            return super.calculate(params)
        }
        
        var rectResult = calculateRect(params.asRectParams())
        var screen = params.usableScreens.currentScreen
        var action = params.action
        
        if isRepeatedCommand(params) {
                
            if action == .moveLeft {
                if let prevScreen = params.usableScreens.adjacentScreens?.prev {
                    screen = prevScreen
                }
                action = .moveRight
            } else {
                if let nextScreen = params.usableScreens.adjacentScreens?.next {
                    screen = nextScreen
                }
                action = .moveLeft
            }
            
            rectResult = calculateRect(params.asRectParams(visibleFrame: screen.adjustedVisibleFrame, differentAction: action))
        
        }
        
        
        return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: action)

    }
    
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        var calculatedWindowRect: CGRect
        
        print("Defaults.subsequentExecutionMode.traversesDisplays", Defaults.subsequentExecutionMode.traversesDisplays)
        print("Defaults.resizeOnDirectionalMove.enabled", Defaults.resizeOnDirectionalMove.enabled)
        if !Defaults.subsequentExecutionMode.traversesDisplays && Defaults.resizeOnDirectionalMove.enabled {
            calculatedWindowRect = calculateRepeatedRect(params).rect
        } else if Defaults.resizeOnDirectionalMove.enabled {
            calculatedWindowRect = calculateGenericRect(params, fraction: 1 / 2.0).rect
        } else {
            calculatedWindowRect = calculateGenericRect(params).rect
        }
        
        if Defaults.centeredDirectionalMove.enabled != false {
            calculatedWindowRect.origin.y = round((visibleFrameOfScreen.height - calculatedWindowRect.height) / 2.0) + visibleFrameOfScreen.minY
        }
        
        if params.window.rect.height >= visibleFrameOfScreen.height {
            calculatedWindowRect.size.height = visibleFrameOfScreen.height
            calculatedWindowRect.origin.y = visibleFrameOfScreen.minY
        }
        
        return RectResult(calculatedWindowRect)

    }
    
    func calculateFirstRect(_ params: RectCalculationParameters) -> RectResult {
        return calculateGenericRect(params, fraction: 1 / 2.0)
    }
    
    func calculateSecondRect(_ params: RectCalculationParameters) -> RectResult {
        return calculateGenericRect(params, fraction: 2 / 3.0)
    }
    
    func calculateThirdRect(_ params: RectCalculationParameters) -> RectResult {
        return calculateGenericRect(params, fraction: 1 / 3.0)
    }
    
    func calculateGenericRect(_ params: RectCalculationParameters, fraction: Float? = nil) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        
        var rect = params.window.rect
        if let requestedFraction = fraction {
            rect.size.width = floor(visibleFrameOfScreen.width * CGFloat(requestedFraction))
        }
        
        if params.action == .moveRight {
            rect.origin.x = visibleFrameOfScreen.maxX - rect.width
        } else {
            rect.origin.x = visibleFrameOfScreen.minX
        }
        
        return RectResult(rect)
    }
    
}

