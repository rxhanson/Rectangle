import Cocoa
import QuartzCore

struct WindowAnimationResponseKey: Hashable {
    let pid: pid_t
    let window: CGWindowID
    let launch: TimeInterval
}
