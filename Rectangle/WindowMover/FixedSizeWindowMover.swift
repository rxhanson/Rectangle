/// FixedSizeWindowMover.swift

import Foundation

/// Handle windows that are a fixed size. Align or center them according to `moveFixedSizeToEdge`.
class FixedSizeWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        if currentWindowRect.isNull { return }

        let adjusted = ClampedWindowAligner.aligned(
            window: currentWindowRect,
            inZone: rect.screenFlipped,
            initialRect: resultParameters.calcResult.initialRect.screenFlipped,
            screenFrame: resultParameters.visibleFrameOfScreen.screenFlipped,
            alignment: Defaults.moveFixedSizeToEdge.value
        )

        if !adjusted.equalTo(currentWindowRect) {
            windowElement.setFrame(adjusted)
        }
    }
}
