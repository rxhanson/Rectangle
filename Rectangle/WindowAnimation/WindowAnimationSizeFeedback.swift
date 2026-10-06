import Cocoa
import QuartzCore

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
