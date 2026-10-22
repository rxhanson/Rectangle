/// OrientationAware.swift

import Foundation

typealias SimpleCalc = (_ visibleFrameOfScreen: CGRect) -> RectResult

protocol OrientationAware {
    
    func landscapeRect(_ visibleFrameOfScreen: CGRect) -> RectResult
    func portraitRect(_ visibleFrameOfScreen: CGRect) -> RectResult
    func orientationBasedRect(_ visibleFrameOfScreen: CGRect) -> RectResult
    
}

extension OrientationAware {
    func orientationBasedRect(_ visibleFrameOfScreen: CGRect) -> RectResult {
        return visibleFrameOfScreen.isLandscape
            ? landscapeRect(visibleFrameOfScreen)
            : portraitRect(visibleFrameOfScreen)
    }
}


extension OrientationAware where Self: WindowCalculation {
    /// With "move to adjacent display" as the repeated command, repeating an edge action sends the
    /// window to the opposite edge of the neighbouring display, as the left and right halves do.
    func calculateAcrossDisplays(_ params: WindowCalculationParameters,
                                 toNext: Bool,
                                 oppositeAction: WindowAction,
                                 opposite: OrientationAware) -> WindowCalculationResult? {
        guard Defaults.subsequentExecutionMode.value == .acrossMonitor,
              isRepeatedCommand(params),
              let adjacentScreens = params.usableScreens.adjacentScreens
        else { return nil }

        let screen = toNext ? adjacentScreens.next : adjacentScreens.prev
        let rectResult = opposite.orientationBasedRect(screen.adjustedVisibleFrame(params.ignoreTodo))
        return WindowCalculationResult(rect: rectResult.rect, screen: screen, resultingAction: oppositeAction, resultingSubAction: rectResult.subAction)
    }
}
