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

enum WindowAnimationGeometry {
    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } && frame.width > 0 && frame.height > 0
    }
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        valid(a) && valid(b) && abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance && abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
}

enum WindowAnimationSize {
    static func animationSize(_ requested: CGSize, origin: CGSize, hint: CGSize?) -> CGSize {
        guard let hint else { return requested }
        func axis(_ requested: CGFloat, _ origin: CGFloat, _ hint: CGFloat) -> CGFloat {
            guard hint.isFinite, hint > 0, hint <= origin + 2, requested < origin else { return requested }
            return max(requested, min(origin, hint))
        }
        return CGSize(width: axis(requested.width, origin.width, hint.width),
                      height: axis(requested.height, origin.height, hint.height))
    }
}

/// Geometry evidence is scoped to one animation. Oversized shrink responses
/// remain eligible for retry rather than becoming inferred minimum sizes.
struct WindowAnimationSizeFeedback {
    private struct Observation {
        let requested: CGSize
        let actual: CGSize
        let time: TimeInterval
    }
    private var observations: [Observation] = []
    private(set) var fixedWidth: CGFloat?
    private(set) var fixedHeight: CGFloat?
    private(set) var aspectRatio: CGFloat?

    mutating func observe(requested: CGSize, actual: CGRect, server: CGRect?, at time: TimeInterval) {
        guard let server, WindowAnimationGeometry.valid(actual),
              WindowAnimationGeometry.near(actual, server, tolerance: 1),
              actual.width <= requested.width + 1, actual.height <= requested.height + 1 else {
            reset()
            return
        }
        guard abs(actual.width - requested.width) > 1 || abs(actual.height - requested.height) > 1 else {
            reset()
            return
        }
        if let last = observations.last,
           abs(last.requested.width - requested.width) <= 1,
           abs(last.requested.height - requested.height) <= 1 { return }
        observations.append(Observation(requested: requested, actual: actual.size, time: time))
        if observations.count > 6 { observations.removeFirst() }
        guard observations.count >= 3, let first = observations.first,
              time - first.time >= 1.0 / 30 else { return }
        fixedWidth = abs(first.requested.width - requested.width) > 2
            && observations.allSatisfy { abs($0.actual.width - actual.width) <= 1 } ? actual.width : nil
        fixedHeight = abs(first.requested.height - requested.height) > 2
            && observations.allSatisfy { abs($0.actual.height - actual.height) <= 1 } ? actual.height : nil
        let ratio = actual.width / actual.height
        aspectRatio = fixedWidth == nil && fixedHeight == nil
            && abs(first.actual.width - actual.width) > 2 && abs(first.actual.height - actual.height) > 2
            && observations.allSatisfy { abs($0.actual.width / $0.actual.height - ratio) <= ratio * 0.005 }
            ? ratio : nil
    }

    func size(for requested: CGSize) -> CGSize {
        var result = CGSize(width: fixedWidth ?? requested.width, height: fixedHeight ?? requested.height)
        if let ratio = aspectRatio {
            result.width = min(result.width, result.height * ratio)
            result.height = result.width / ratio
        }
        return result
    }

    private mutating func reset() {
        observations.removeAll(keepingCapacity: true)
        fixedWidth = nil
        fixedHeight = nil
        aspectRatio = nil
    }
}
