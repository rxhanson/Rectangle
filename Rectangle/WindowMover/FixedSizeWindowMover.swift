/// FixedSizeWindowMover.swift

import Foundation

/// Handle windows that are a fixed size. Align or center them according to `moveFixedSizeToEdge`.
class FixedSizeWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        if currentWindowRect.isNull { return }

        let sharedEdges = Defaults.moveFixedSizeToEdge.value.alignmentEdges(
            for: resultParameters.calcResult.initialRect.screenFlipped,
            in: resultParameters.visibleFrameOfScreen.screenFlipped
        )

        let adjusted = ClampedWindowAligner.aligned(window: currentWindowRect,
                                                    inZone: rect.screenFlipped,
                                                    sharedEdges: sharedEdges)

        if !adjusted.equalTo(currentWindowRect) {
            windowElement.setFrame(adjusted)
        }
    }
}
