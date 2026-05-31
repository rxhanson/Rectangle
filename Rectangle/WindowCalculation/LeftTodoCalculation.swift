/// LeftTodoCalculation.swift

import Foundation

final class LeftTodoCalculation: WindowCalculation {
    override func calculateRect(_ params: RectCalculationParameters) -> RectResult {
        let visibleFrameOfScreen = params.visibleFrameOfScreen
        var calculatedWindowRect = visibleFrameOfScreen
        let sidebarWidth = TodoManager.getSidebarWidth(visibleFrameWidth: visibleFrameOfScreen.width)

        calculatedWindowRect.size.width = sidebarWidth

        return RectResult(calculatedWindowRect, subAction: .leftTodo)
    }
}
