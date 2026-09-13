/// WindowMover.swift

import Foundation

protocol WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters)
}

/// Repositions a window that may not fill its snap zone. Pure geometry, no side effects.
///
/// Leading-corner alignment keeps the requested origin. Other modes anchor to selected
/// screen edges or center on unfilled axes. Edge names follow `CGRect.sharedEdges`:
/// `.top` means maxY and `.bottom` means minY, even in AX space where Y grows downward.
/// All frames must use the same (screen-flipped / AX) coordinate space.
enum ClampedWindowAligner {

    /// A window may come back a hair smaller than its zone without being clamped in any
    /// meaningful sense: macOS shortens an AX size change that grows a window onto the Dock
    /// edge by a point. Realigning that shortfall moves the gap off the Dock edge, where it
    /// was invisible, onto an opposite edge where it is not, so leave the axis alone instead.
    static let alignmentTolerance: CGFloat = 1.0

    static func aligned(window: CGRect, inZone zone: CGRect, initialRect: CGRect,
                        screenFrame: CGRect, alignment: EdgeAlignment) -> CGRect {
        let sharedEdges: Edge
        switch alignment {
        case .edgesAndCorners:
            sharedEdges = initialRect.sharedEdges(withRect: screenFrame)
        case .corners:
            let edges = initialRect.sharedEdges(withRect: screenFrame)
            sharedEdges = edges.isCorner ? edges : .none
        case .leadingCorner:
            return CGRect(origin: zone.origin, size: window.size)
        case .centered:
            sharedEdges = .none
        }

        var result = window

        if abs(window.width - zone.width) > alignmentTolerance {
            if sharedEdges.contains(.left), !sharedEdges.contains(.right) {
                result.origin.x = zone.minX
            } else if sharedEdges.contains(.right), !sharedEdges.contains(.left) {
                result.origin.x = zone.maxX - window.width
            } else {
                result.origin.x = round((zone.width - window.width) / 2.0) + zone.minX
            }
        }

        if abs(window.height - zone.height) > alignmentTolerance {
            if sharedEdges.contains(.top), !sharedEdges.contains(.bottom) {
                result.origin.y = zone.maxY - window.height
            } else if sharedEdges.contains(.bottom), !sharedEdges.contains(.top) {
                result.origin.y = zone.minY
            } else {
                result.origin.y = round((zone.height - window.height) / 2.0) + zone.minY
            }
        }

        return result
    }
}

/// Repositions the app-accepted frame after `StandardWindowMover` requests a resize.
/// Leading-corner mode retains the requested origin rather than centering or edge-aligning
/// within unused space. The app-accepted size is preserved in every mode.
class EdgeAlignmentWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        guard resultParameters.action.resizes else { return }

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

enum EdgeAlignment: Int {
    case edgesAndCorners = 1
    case corners = 2
    case centered = 3
    case leadingCorner = 4
}
