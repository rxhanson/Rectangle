/// FixedSizeWindowMover.swift

import Foundation

/// Handle windows that are a fixed size. With `moveFixedSizeToEdge` enabled, anchor them
/// to the snap zone's screen edges; otherwise center them in the zone (legacy behavior).
class FixedSizeWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        if currentWindowRect.isNull { return }

        let sharedEdges: Edge = Defaults.moveFixedSizeToEdge.userEnabled
            ? resultParameters.calcResult.initialRect.screenFlipped
                .sharedEdges(withRect: resultParameters.visibleFrameOfScreen.screenFlipped)
            : .none // no shared edges -> aligner centers, matching legacy behavior

        let adjusted = ClampedWindowAligner.aligned(window: currentWindowRect,
                                                    inZone: rect.screenFlipped,
                                                    sharedEdges: sharedEdges)

        if !adjusted.equalTo(currentWindowRect) {
            windowElement.setFrame(adjusted)
        }
    }
}
