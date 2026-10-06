import Cocoa
import QuartzCore

/// Input-specific timing shares the same window placement and verification code.
enum WindowAnimationProfile {
    case standard, keyboard
    // A picker selection is one placement, even when a shortcut opened it.
    // Use the single destination trajectory without keyboard retargeting.
    case layoutHelper

    func constraintCorrection(after elapsed: TimeInterval) -> CGFloat {
        if self == .layoutHelper {
            // Complete more of the size-limited alignment during the picker
            // animation to reduce the correction needed afterward.
            // Bound long ticks so an unresponsive app cannot cause a large jump.
            return CGFloat(min(1.0 / 30, max(0, elapsed))) * 240
        }
        return min(1, CGFloat(max(0, elapsed)) * 60)
    }
}
