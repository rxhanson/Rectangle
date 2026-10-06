import Cocoa
import QuartzCore

struct WindowReleasedSnapStability {
    enum Decision { case waiting, ready, timedOut }
    let startedAt: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(startedAt: TimeInterval) { self.startedAt = startedAt }

    mutating func observe(ax: CGRect, server: CGRect?, at now: TimeInterval) -> Decision {
        if let server, WindowAnimationGeometry.valid(ax), WindowAnimationGeometry.valid(server),
           WindowAnimationGeometry.near(ax, server, tolerance: 1) {
            if let previous, WindowAnimationGeometry.near(previous, server, tolerance: 1) {
                if let stableSince, now - stableSince >= 1.0 / 30 { return .ready }
            } else { stableSince = now }
            previous = server
        } else {
            previous = nil
            stableSince = nil
        }
        return now - startedAt >= 0.15 ? .timedOut : .waiting
    }
}
