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

        calculatedWindowRect.origin.x = visibleFrameOfScreen.maxX - Defaults.todoSidebarWidth.cgFloat
        calculatedWindowRect.size.width = Defaults.todoSidebarWidth.cgFloat

        return RectResult(calculatedWindowRect, subAction: .rightTodo)
    }
}
