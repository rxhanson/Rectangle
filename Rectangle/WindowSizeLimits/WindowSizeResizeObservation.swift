import Cocoa

/// Samples contain only agreeing AX/WindowServer frames. A stable oversized
/// response is evidence only when the requested axis actually shrank.
struct WindowSizeResizeObservation {
    let before: CGRect
    let requested: CGRect
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(before: CGRect, requested: CGRect) {
        self.before = before
        self.requested = requested
    }

    mutating func observe(_ frame: CGRect?, at time: TimeInterval) -> CGRect? {
        guard let frame, WindowAnimationGeometry.valid(frame),
              WindowAnimationGeometry.valid(before), WindowAnimationGeometry.valid(requested),
              WindowGeometry.matches(frame, requested, tolerance: 1)
                || (Self.learnedMinimum(before: before.size, requested: requested.size, settled: frame.size) != nil
                    && frame.minX <= requested.minX + 1 && frame.maxX >= requested.maxX - 1
                    && frame.minY <= requested.minY + 1 && frame.maxY >= requested.maxY - 1) else {
            previous = nil; stableSince = nil
            return nil
        }
        guard let previous, WindowGeometry.matches(frame, previous, tolerance: 1) else {
            self.previous = frame
            stableSince = time
            return nil
        }
        guard let stableSince, time - stableSince >= 0.12 else { return nil }
        return frame
    }

    static func learnedMinimum(before: CGSize, requested: CGSize, settled: CGSize) -> CGSize? {
        func clamp(_ old: CGFloat, _ target: CGFloat, _ actual: CGFloat) -> CGFloat {
            // An unchanged dimension can be an ignored write. Coupled changes
            // can be an aspect ratio or a sizing grid rather than a minimum.
            target + 2 < actual && actual < old - 1 ? actual : 0
        }
        let learned = CGSize(width: clamp(before.width, requested.width, settled.width),
                             height: clamp(before.height, requested.height, settled.height))
        guard (learned.width > 0) != (learned.height > 0),
              learned.width > 0 ? abs(requested.height - settled.height) <= 1
                                : abs(requested.width - settled.width) <= 1 else { return nil }
        return learned
    }
}
