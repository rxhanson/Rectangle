/// DisplayTransfer.swift

import CoreGraphics

/// Places a window on a destination display so that it keeps the spot it had on the source
/// display, instead of being centered (issue #1666).
///
/// Each axis is worked out on its own, and both use the same rule: an edge that was against the
/// source screen edge is put back against the matching destination screen edge. The rest follows
/// from that.
///
/// - Against both edges: the window follows both, so it spans the destination on that axis. A
///   maximized window stays maximized, a left half stays full height.
/// - Against one edge: the window keeps its size and stays against that edge, so a window parked
///   in a corner arrives in the same corner.
/// - Against neither: the window keeps its size and its center keeps the same relative spot, so a
///   window sitting in the right third arrives in the right third.
///
/// Sizes only change where the window has to follow the screen edges, which is what makes this
/// feel like dragging the window across yourself. The exception is a window that is larger than
/// the destination display, which is cut down to fit.
///
/// The distance from an edge is carried over rather than flattened to zero, so a window that was
/// snapped with gaps arrives with the same gaps.
class DisplayTransfer {

    /// How far from the screen edge a window edge can be and still count as being against it.
    /// Windows are rarely placed to the exact point - the accessibility API rounds and apps round
    /// to their own grid - and with gaps turned on nothing is ever flush to begin with.
    static var edgeTolerance: CGFloat { 4 + Defaults.gapSize.cgFloat }

    static func transferredRect(window: CGRect, source: CGRect, destination: CGRect, edgeTolerance: CGFloat = DisplayTransfer.edgeTolerance) -> CGRect {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else {
            return window
        }

        let horizontal = transfer(window: (window.minX, window.width),
                                  source: (source.minX, source.width),
                                  destination: (destination.minX, destination.width),
                                  edgeTolerance: edgeTolerance)
        let vertical = transfer(window: (window.minY, window.height),
                                source: (source.minY, source.height),
                                destination: (destination.minY, destination.height),
                                edgeTolerance: edgeTolerance)

        return CGRect(x: horizontal.origin,
                      y: vertical.origin,
                      width: horizontal.length,
                      height: vertical.length)
    }

    /// One axis of the window, the source screen and the destination screen, as a starting point
    /// and a length.
    private typealias Span = (origin: CGFloat, length: CGFloat)

    private static func transfer(window: Span, source: Span, destination: Span, edgeTolerance: CGFloat) -> Span {
        // A window hanging off the screen has a negative inset here, which counts as being against
        // that edge: bringing it back into view is the only sensible thing to do with it.
        let startInset = window.origin - source.origin
        let endInset = (source.origin + source.length) - (window.origin + window.length)
        let againstStart = startInset <= edgeTolerance
        let againstEnd = endInset <= edgeTolerance

        if againstStart, againstEnd {
            // Following both edges at once is what stretches the window to the destination.
            let start = clamp(startInset, 0, destination.length / 2)
            let end = clamp(endInset, 0, destination.length / 2)
            return (destination.origin + start, destination.length - start - end)
        }

        let length = min(window.length, destination.length)
        let slack = destination.length - length

        if againstStart {
            return (destination.origin + clamp(startInset, 0, slack), length)
        }
        if againstEnd {
            return (destination.origin + destination.length - length - clamp(endInset, 0, slack), length)
        }

        let centerFraction = (window.origin + window.length / 2 - source.origin) / source.length
        let origin = destination.origin + centerFraction * destination.length - length / 2
        return (clamp(origin, destination.origin, destination.origin + slack), length)
    }

    private static func clamp(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        return min(max(value, lowerBound), upperBound)
    }
}
