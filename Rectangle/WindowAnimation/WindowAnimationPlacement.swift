import Cocoa
import QuartzCore

struct WindowAnimationPlacement: Equatable {
    let screenFrame: CGRect
    let sharedEdges: Edge?
    let constrainToScreen: Bool
    let gap: CGFloat

    func positionBeforeGrowing(from previous: CGRect, to requested: CGRect) -> CGPoint? {
        guard constrainToScreen else { return nil }
        var position = previous.origin
        // Make room on an expanding axis before asking AX to resize. Otherwise
        // macOS can clip the new size at the old origin even though the next
        // animation frame fits, producing a stop/start edge during the resize.
        if requested.width > previous.width + 1,
           previous.minX + requested.width > screenFrame.maxX + 1,
           requested.minX < previous.minX {
            position.x = requested.minX
        }
        if requested.height > previous.height + 1,
           previous.minY + requested.height > screenFrame.maxY + 1,
           requested.minY < previous.minY {
            position.y = requested.minY
        }
        return position == previous.origin ? nil : position
    }

    func frame(for requested: CGRect, actualSize: CGSize, origin: CGRect, progress: CGFloat) -> CGRect {
        var frame = CGRect(origin: requested.origin, size: actualSize)
        if let sharedEdges {
            frame = ClampedWindowAligner.aligned(window: frame, inZone: requested, sharedEdges: sharedEdges)
        }
        guard constrainToScreen else { return frame }

        // Bring an initially out-of-bounds window back gradually instead of clipping its first frame.
        let initialBounds = screenFrame.union(origin)
        let progress = min(1, max(0, progress))
        let bounds = CGRect(x: initialBounds.minX + (screenFrame.minX - initialBounds.minX) * progress,
                            y: initialBounds.minY + (screenFrame.minY - initialBounds.minY) * progress,
                            width: initialBounds.width + (screenFrame.width - initialBounds.width) * progress,
                            height: initialBounds.height + (screenFrame.height - initialBounds.height) * progress)
        return WindowFrameBounds.constrained(frame, to: bounds, gap: gap)
    }

    /// A transient resize response must not send an intermediate position past
    /// its requested trajectory and then back when the size catches up.
    func intermediateFrame(_ resolved: CGRect, requested: CGRect, previous: CGRect, maximumCorrection: CGFloat = 0) -> CGRect {
        var result = resolved
        result.origin.x = min(max(resolved.minX, min(previous.minX, requested.minX)),
                              max(previous.minX, requested.minX))
        result.origin.y = min(max(resolved.minY, min(previous.minY, requested.minY)),
                              max(previous.minY, requested.minY))
        // Consume constraint changes gradually, including necessary movement
        // against the nominal trajectory near a screen edge.
        let limit = max(0, maximumCorrection)
        result.origin.x += min(limit, max(-limit, resolved.minX - result.minX))
        result.origin.y += min(limit, max(-limit, resolved.minY - result.minY))
        return result
    }

    func coordinatedPosition(_ position: CGPoint, size: CGSize, previous: CGRect,
                             origin: CGRect, destination: CGRect) -> CGPoint {
        func coordinate(_ value: CGFloat, size: CGFloat, previous: CGFloat, previousSize: CGFloat,
                        start: CGFloat, startSize: CGFloat, end: CGFloat, endSize: CGFloat) -> CGFloat {
            // When the two edges move apart (or together), advancing position
            // without the corresponding resize makes the opposite edge reverse.
            if end < start, end + endSize >= start + startSize - 0.5, size >= previousSize {
                return min(previous, max(min(previous + previousSize, end + endSize) - size, value))
            }
            if end > start, end + endSize <= start + startSize + 0.5, size <= previousSize {
                return max(previous, min(max(previous + previousSize, end + endSize) - size, value))
            }
            return value
        }
        return CGPoint(x: coordinate(position.x, size: size.width, previous: previous.minX, previousSize: previous.width,
                                     start: origin.minX, startSize: origin.width, end: destination.minX, endSize: destination.width),
                       y: coordinate(position.y, size: size.height, previous: previous.minY, previousSize: previous.height,
                                     start: origin.minY, startSize: origin.height, end: destination.minY, endSize: destination.height))
    }
}
