/// WindowMover.swift

import Foundation

protocol WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters)
}

/// Repositions a window that may not fill its snap zone. Pure geometry, no side effects.
///
/// All frames must use screen-flipped (AX) coordinates. `CGRect.sharedEdges` names
/// maxY `.top` and minY `.bottom`, even though Y grows downward.
enum ClampedWindowAligner {

    /// A window may come back a hair smaller than its zone without being clamped in any
    /// meaningful sense: macOS shortens an AX size change that grows a window onto the Dock
    /// edge by a point. Realigning that shortfall moves the gap off the Dock edge, where it
    /// was invisible, onto an opposite edge where it is not, so leave the axis alone instead.
    static let alignmentTolerance: CGFloat = 1.0

    static func aligned(window: CGRect, inZone zone: CGRect, sharedEdges: Edge) -> CGRect {
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

        return aligned(window: window, inZone: zone, sharedEdges: sharedEdges)
    }
}

/// Repositions windows after `StandardWindowMover` requests a resize,
/// keeping the size the app allows.
class EdgeAlignmentWindowMover: WindowMover {

    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        guard resultParameters.action.resizes else { return }

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

enum EdgeAlignment: Int {
    case edgesAndCorners = 1
    case corners = 2
    case centered = 3
    case leadingCorner = 4
    
    func alignmentEdges(for rect: CGRect, in screenFrame: CGRect) -> Edge? {
        let sharedEdges = rect.sharedEdges(withRect: screenFrame)

        switch self {
        case .edgesAndCorners:
            return sharedEdges
        case .corners:
            return sharedEdges.isCorner ? sharedEdges : .none
        case .centered:
            return Edge.none
        case .leadingCorner:
            return nil
        }
    }
}
