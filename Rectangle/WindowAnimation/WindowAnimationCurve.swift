import Cocoa
import QuartzCore

/// Timing for direct resizing and drag restoration.
enum WindowAnimationCurve {
    static let duration: TimeInterval = 0.24
    static let unsnapPlaybackRate: Double = 1.2
    static let unsnapDuration: TimeInterval = 0.18 / unsnapPlaybackRate

    static func unsnapValue(at progress: Double) -> CGFloat {
        let t = min(1, max(0, progress))
        // Quintic smoothstep: zero velocity and acceleration at both endpoints.
        return CGFloat(t * t * t * (10 + t * (-15 + 6 * t)))
    }

    static func value(at progress: Double) -> CGFloat {
        let t = min(1, max(0, progress))
        // Cubic deceleration reaches rest without an extended near-stationary tail.
        return CGFloat(t * (3 + t * (t - 3)))
    }

    static func resizeValue(at progress: Double) -> CGFloat {
        let t = min(1, max(0, progress))
        // Start at rest, leaving enough of the tail for screen-edge constraints to settle.
        return CGFloat(t * t * (10 + t * (-20 + t * (15 - 4 * t))))
    }

    static func placementValue(at progress: Double) -> CGFloat {
        let t = min(1, max(0, progress))
        // A picker starts from rest rather than inheriting a drag's motion.
        return CGFloat(t * t * (3 - 2 * t))
    }
}
