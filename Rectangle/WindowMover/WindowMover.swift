/// WindowMover.swift

import Foundation

protocol WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters)
}

/// Repositions a window that may not fill its snap zone. Pure geometry, no side effects.
///
/// Per axis: if the zone touches exactly one screen edge on that axis, anchor the window
/// to that edge; if it spans the full axis (both edges) or floats inside (neither), center.
/// `window` and `zone` must be in the same (screen-flipped) coordinate space, where the
/// `.top` edge corresponds to maxY and `.bottom` to minY (matching the rest of Rectangle).
enum ClampedWindowAligner {

    static func aligned(window: CGRect, inZone zone: CGRect, sharedEdges: Edge) -> CGRect {
        var result = window

        if window.width != zone.width {
            if sharedEdges.contains(.left), !sharedEdges.contains(.right) {
                result.origin.x = zone.minX
            } else if sharedEdges.contains(.right), !sharedEdges.contains(.left) {
                result.origin.x = zone.maxX - window.width
            } else {
                result.origin.x = round((zone.width - window.width) / 2.0) + zone.minX
            }
        }

        if window.height != zone.height {
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
