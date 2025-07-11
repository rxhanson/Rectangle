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
        var calculatedTodoSidebarWidth: CGFloat
        
        if Defaults.todoSidebarWidthUnit.value == .pixels {
            calculatedTodoSidebarWidth = Defaults.todoSidebarWidth.cgFloat
        } else {
            calculatedTodoSidebarWidth = visibleFrameOfScreen.width * (Defaults.todoSidebarWidth.cgFloat * 0.01)
        }

        calculatedWindowRect.origin.x = visibleFrameOfScreen.maxX - calculatedTodoSidebarWidth
        calculatedWindowRect.size.width = calculatedTodoSidebarWidth

        return RectResult(calculatedWindowRect, subAction: .rightTodo)
    }
}
