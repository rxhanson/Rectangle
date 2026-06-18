/// FixedSizeWindowMover.swift

import Foundation

/// Handle windows that are a fixed size. With `moveFixedSizeToEdge` enabled, anchor them
/// to the snap zone's screen edges; otherwise center them in the zone (legacy behavior).
class FixedSizeWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        let currentWindowRect: CGRect = windowElement.frame
        if currentWindowRect.isNull { return }

        let initialFlippedRect = resultParameters.calcResult.initialRect.screenFlipped
        let screenFrame = resultParameters.visibleFrameOfScreen.screenFlipped
        let sharedEdges: Edge = getAlignmentEdges(initialNormalizedRect: initialFlippedRect, normalizedScreenFrame: screenFrame)

        let adjusted = ClampedWindowAligner.aligned(window: currentWindowRect,
                                                    inZone: rect.screenFlipped,
                                                    sharedEdges: sharedEdges)

        if !adjusted.equalTo(currentWindowRect) {
            windowElement.setFrame(adjusted)
        }
    }
    
    private func getAlignmentEdges(initialNormalizedRect rect: CGRect, normalizedScreenFrame: CGRect) -> Edge {
        let alignment = Defaults.moveFixedSizeToEdge.value
        
        switch alignment {
        case .edgesAndCorners:
            return rect.sharedEdges(withRect: normalizedScreenFrame)
        case .corners:
            let sharedEdges = rect.sharedEdges(withRect: normalizedScreenFrame)
            return sharedEdges.isCorner ? sharedEdges : .none
        case .centered:
            return .none
        }
    }
    
}
