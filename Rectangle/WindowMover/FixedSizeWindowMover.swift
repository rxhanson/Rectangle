/// FixedSizeWindowMover.swift

import Foundation

/// Handle windows that are a fixed size. Align or center them according to `moveFixedSizeToEdge`.
class FixedSizeWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        if currentWindowRect.isNull { return }

        var adjusted = ClampedWindowAligner.aligned(
            window: currentWindowRect,
            inZone: rect.screenFlipped,
            initialRect: resultParameters.calcResult.initialRect.screenFlipped,
            screenFrame: resultParameters.visibleFrameOfScreen.screenFlipped,
            alignment: Defaults.moveFixedSizeToEdge.value
        )

        let bounds = resultParameters.visibleFrameOfScreen.screenFlipped
        // An oversized window cannot fit both edges; leave its final correction to the bounds mover.
        if adjusted.width <= bounds.width, adjusted.height <= bounds.height,
           !resultParameters.action.allowedToExtendOutsideCurrentScreenArea || NSScreen.screensHaveSeparateSpaces {
            adjusted = WindowFrameBounds.constrained(adjusted, to: bounds, gap: CGFloat(Defaults.gapSize.value))
        }
        if adjusted.origin != currentWindowRect.origin {
            windowElement.setImmediateFrame(adjusted, from: currentWindowRect, sizeFirst: false)
        }
    }
}
