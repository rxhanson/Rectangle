/// WindowAnimationCurves.swift

import Cocoa

enum WindowDisplayTransition {
    enum Route: String { case move, fade }

    static func route(from source: CGRect, to destination: CGRect) -> Route {
        if source == destination { return .move }
        let verticalOverlap = min(source.maxY, destination.maxY) - max(source.minY, destination.minY)
        let touchingSides = abs(source.maxX - destination.minX) <= 1
            || abs(destination.maxX - source.minX) <= 1
        return touchingSides && verticalOverlap > 1 ? .move : .fade
    }

    static func display(containing frame: CGRect, displays: [CGRect]) -> CGRect? {
        displays.filter { $0.intersects(frame) }.max {
            let a = $0.intersection(frame), b = $1.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
    }

    /// The geometry changes only while fully transparent, leaving intermediate
    /// displays empty even when source and destination are far apart.
    static func fadeFrame(from source: CGRect, to destination: CGRect, progress: Double) -> CGRect {
        progress < 0.5 ? source : destination
    }

    static func fadeOpacity(progress: Double, initial: Double = 1) -> Double {
        let t = min(1, max(0, progress))
        func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        if t < 0.4 { return initial * (1 - smooth(t / 0.4)) }
        if t > 0.6 { return smooth((t - 0.6) / 0.4) }
        return 0
    }
}

/// Shared geometry timing for target-zone previews and window enlargement.
enum WindowPreviewDeceleration {
    static let duration: TimeInterval = 0.26

    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.1, 0.9, 0.2, 1)
    }

    static func value(at time: Double) -> CGFloat {
        let x = min(1, max(0, time))
        if x == 0 || x == 1 { return CGFloat(x) }
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lower = 0.0, upper = 1.0
        for _ in 0..<40 {
            let t = (lower + upper) / 2
            if bezier(t, 0.1, 0.2) < x { lower = t } else { upper = t }
        }
        return CGFloat(bezier((lower + upper) / 2, 0.9, 1))
    }

}

/// Original direct-resize and preview easing from fe06e88.
enum WindowAnimationCurve {
    static let duration: TimeInterval = 0.34
    static let unsnapPlaybackRate: Double = 1.2
    static let unsnapDuration: TimeInterval = 0.18 / unsnapPlaybackRate

    static func unsnapValue(at progress: Double) -> CGFloat {
        let t = min(1, max(0, progress))
        // Quintic smoothstep: zero velocity and acceleration at both endpoints.
        return CGFloat(t * t * t * (10 + t * (-15 + 6 * t)))
    }

    static func value(at progress: Double) -> CGFloat {
        let progress = min(1, max(0, progress))
        // Integral of t * (1 - t)^5, normalized to [0, 1].
        return CGFloat(1 - pow(1 - progress, 6) * (1 + 6 * progress))
    }
}

/// A short continuation from the current presentation. Component velocities
/// pointing at the new target are retained within monotonic Hermite bounds;
/// reversal brakes immediately and never overshoots the new destination.
enum WindowFrostRetargetMotion {
    struct Plan {
        let frames: [CGRect]
        let duration: TimeInterval
    }
    static func plan(from source: CGRect, to target: CGRect, velocity: [CGFloat], requested: TimeInterval) -> Plan {
        let a = [source.minX, source.minY, source.width, source.height]
        let b = [target.minX, target.minY, target.width, target.height]
        let distance = zip(a, b).map { abs($0 - $1) }.max() ?? 0
        let duration = requested <= 0 ? 0 : min(0.28, max(0.08, Double(distance) / 3200))
        let count = max(2, Int(ceil(duration * 120)))
        let frames = (0...count).map { index -> CGRect in
            let t = CGFloat(index) / CGFloat(count)
            let values = (0..<4).map { component -> CGFloat in
                let delta = b[component] - a[component]
                let incoming = component < velocity.count ? velocity[component] : 0
                let tangent = delta == 0 ? 0 : delta * min(3, max(0, incoming * CGFloat(duration) / delta))
                return a[component] + delta * (3 * t * t - 2 * t * t * t)
                    + tangent * (t * t * t - 2 * t * t + t)
            }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        return Plan(frames: frames, duration: duration)
    }
    static func frame(_ frames: [CGRect], progress: Double) -> CGRect {
        let position = min(1, max(0, progress)) * Double(frames.count - 1)
        let lower = Int(position), upper = min(frames.count - 1, lower + 1)
        let t = CGFloat(position - Double(lower)), a = frames[lower], b = frames[upper]
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}
