//
//  RightTodoCalculation.swift
//  Rectangle
//
//  Copyright © 2023 Ryan Hanson. All rights reserved.
//

import Foundation

final class RightTodoCalculation: WindowCalculation {
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        var calculatedWindowRect = visibleFrameOfScreen
        let sidebarWidth = TodoManager.getSidebarWidth(visibleFrameWidth: visibleFrameOfScreen.width)
        
        calculatedWindowRect.origin.x = visibleFrameOfScreen.maxX - sidebarWidth
        calculatedWindowRect.size.width = sidebarWidth

        return RectResult(calculatedWindowRect, subAction: .rightTodo)
    }
}
