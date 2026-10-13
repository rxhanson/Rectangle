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


}

/// Keyboard retargeting and native drag restoration have distinct motion curves.
enum WindowAnimationProfile {
    case standard, keyboard

    func constraintCorrection(after elapsed: TimeInterval) -> CGFloat {
        min(1, CGFloat(max(0, elapsed)) * 60)
    }
}


/// Shared geometry timing for target-zone previews and window enlargement.
enum WindowPreviewDeceleration {
    static let duration: TimeInterval = 0.20

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
