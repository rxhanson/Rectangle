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
///
/// One case is handled differently: a window against three screen edges - spanning one axis and
/// against one edge of the other, like a left half or a top half - that moves between a landscape
/// and a portrait display. Following the rule above would stretch a left half into a tall sliver
/// down the whole length of a portrait display. Instead it stays against the middle one of its
/// three edges, keeps its size, and is centered along that edge. Picking a corner would mean
/// guessing from how the displays happen to be arranged, whereas centering makes no assumption.
class DisplayTransfer {

    /// How far from the screen edge a window edge can be and still count as being against it.
    /// Windows are rarely placed to the exact point - the accessibility API rounds and apps round
    /// to their own grid - and with gaps turned on nothing is ever flush to begin with.
    static var edgeTolerance: CGFloat { 4 + Defaults.gapSize.cgFloat }

    static func transferredRect(window: CGRect, source: CGRect, destination: CGRect, edgeTolerance: CGFloat = DisplayTransfer.edgeTolerance) -> CGRect {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else {
            return window
        }

        var horizontal = transfer(window: (window.minX, window.width),
                                  source: (source.minX, source.width),
                                  destination: (destination.minX, destination.width),
                                  edgeTolerance: edgeTolerance)
        var vertical = transfer(window: (window.minY, window.height),
                                source: (source.minY, source.height),
                                destination: (destination.minY, destination.height),
                                edgeTolerance: edgeTolerance)

        if changesOrientation(from: source, to: destination) {
            // Against three edges: one axis spans, and the other is against exactly one edge, which
            // is the middle one of the three. The spanning axis is the one that gets centered.
            if horizontal.contact == .both, vertical.contact.isOneEdge {
                horizontal.span = centered(length: window.width, on: horizontal.span,
                                          destination: (destination.minX, destination.width))
            } else if vertical.contact == .both, horizontal.contact.isOneEdge {
                vertical.span = centered(length: window.height, on: vertical.span,
                                         destination: (destination.minY, destination.height))
            }
        }

        return CGRect(x: horizontal.span.origin,
                      y: vertical.span.origin,
                      width: horizontal.span.length,
                      height: vertical.span.length)
    }

    /// One axis of the window, the source screen and the destination screen, as a starting point
    /// and a length.
    private typealias Span = (origin: CGFloat, length: CGFloat)

    /// Which of the two screen edges on an axis the window was against.
    private enum Contact {
        case neither, start, end, both

        var isOneEdge: Bool { self == .start || self == .end }
    }

    /// Landscape to portrait or back. A square display is neither, so it never counts.
    private static func changesOrientation(from source: CGRect, to destination: CGRect) -> Bool {
        return (source.width > source.height && destination.height > destination.width)
            || (source.height > source.width && destination.width > destination.height)
    }

    /// Keeps `length` and centers it on the destination, rather than following both edges. If the
    /// window is too long to fit between the edges, following them is all that can be done anyway.
    private static func centered(length: CGFloat, on spanned: Span, destination: Span) -> Span {
        guard length < spanned.length else { return spanned }
        return (destination.origin + (destination.length - length) / 2, length)
    }

    private static func transfer(window: Span, source: Span, destination: Span, edgeTolerance: CGFloat) -> (span: Span, contact: Contact) {
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
            return ((destination.origin + start, destination.length - start - end), .both)
        }

        let length = min(window.length, destination.length)
        let slack = destination.length - length

        if againstStart {
            return ((destination.origin + clamp(startInset, 0, slack), length), .start)
        }
        if againstEnd {
            return ((destination.origin + destination.length - length - clamp(endInset, 0, slack), length), .end)
        }

        let centerFraction = (window.origin + window.length / 2 - source.origin) / source.length
        let origin = destination.origin + centerFraction * destination.length - length / 2
        return ((clamp(origin, destination.origin, destination.origin + slack), length), .neither)
    }

    private static func clamp(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        return min(max(value, lowerBound), upperBound)
    }
}
