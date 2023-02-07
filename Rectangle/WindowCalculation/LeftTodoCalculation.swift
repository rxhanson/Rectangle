//
//  LeftTodoCalculation.swift
//  Rectangle
//
//  Copyright © 2023 Ryan Hanson. All rights reserved.
//

import Foundation

final class LeftTodoCalculation: WindowCalculation {
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        var calculatedWindowRect = visibleFrameOfScreen

        calculatedWindowRect.size.width = Defaults.todoSidebarWidth.cgFloat

        return RectResult(calculatedWindowRect, subAction: .leftTodo)
    }
}
