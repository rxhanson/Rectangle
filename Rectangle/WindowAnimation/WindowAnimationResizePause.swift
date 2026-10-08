import Cocoa
import QuartzCore

/// Suppresses repeated shrinking only for the current motion. Final placement
/// still retries the requested size; this state never becomes a learned limit.
struct WindowAnimationResizePause {
    private struct AxisObservation {
        var actual: CGFloat
        var firstRequest: CGFloat
        var lastRequest: CGFloat
        var startedAt: TimeInterval
        var count: Int
    }

    struct Motion {
        let destination: CGRect
        let startedAt: TimeInterval
        let width: CGFloat?
        let height: CGFloat?
        let x: WindowKeyboardMotion.Axis
        let y: WindowKeyboardMotion.Axis

        var endsAt: TimeInterval { startedAt + max(x.duration, y.duration) }

        func sample(requested: CGRect, at time: TimeInterval) -> (frame: CGRect, velocity: [CGFloat?]) {
            let x = x.sample(at: max(0, time - startedAt))
            let y = y.sample(at: max(0, time - startedAt))
            return (CGRect(x: width == nil ? requested.minX : x.position.rounded(),
                           y: height == nil ? requested.minY : y.position.rounded(),
                           width: width ?? requested.width, height: height ?? requested.height),
                    [width == nil ? nil : x.velocity, height == nil ? nil : y.velocity,
                     width == nil ? nil : 0, height == nil ? nil : 0])
        }
    }

    private var width: AxisObservation?
    private var height: AxisObservation?
    private(set) var motion: Motion?

    mutating func observe(requested: CGSize, actual: CGRect, server: CGRect?, destination: CGRect,
                          placement: WindowAnimationPlacement, origin: CGRect, velocity: CGPoint,
                          at now: TimeInterval, endingAt: TimeInterval) {
        guard let server, WindowAnimationGeometry.valid(actual), WindowAnimationGeometry.valid(server) else {
            width = nil; height = nil; motion = nil
            return
        }
        let widthAgrees = abs(actual.width - server.width) <= 1
        let heightAgrees = abs(actual.height - server.height) <= 1
        let retainedWidth = motion?.width.flatMap {
            widthAgrees && abs(actual.width - $0) <= 1 && requested.width < $0 - 1 ? $0 : nil
        }
        let retainedHeight = motion?.height.flatMap {
            heightAgrees && abs(actual.height - $0) <= 1 && requested.height < $0 - 1 ? $0 : nil
        }
        if !widthAgrees { width = nil }
        if !heightAgrees { height = nil }
        let blockedWidth = widthAgrees
            && Self.observeAxis(&width, requested: requested.width, actual: actual.width, at: now)
        let blockedHeight = heightAgrees
            && Self.observeAxis(&height, requested: requested.height, actual: actual.height, at: now)
        let canStart = endingAt > now
        let heldWidth = retainedWidth ?? (canStart && blockedWidth ? actual.width : nil)
        let heldHeight = retainedHeight ?? (canStart && blockedHeight ? actual.height : nil)
        guard heldWidth != nil || heldHeight != nil else { motion = nil; return }
        guard motion == nil || heldWidth != motion?.width || heldHeight != motion?.height else { return }

        // Only the rejected axis pauses. The other dimension continues to
        // follow the original trajectory rather than growing at completion.
        let finalSize = CGSize(width: heldWidth ?? destination.width, height: heldHeight ?? destination.height)
        let aligned = placement.frame(for: destination, actualSize: finalSize, origin: origin, progress: 1)
        let remaining = max(0.06, endingAt - now)
        motion = Motion(destination: aligned, startedAt: now, width: heldWidth, height: heldHeight,
            x: WindowKeyboardMotion.Axis(origin: actual.minX, destination: aligned.minX,
                velocity: velocity.x, duration: remaining, maximumDrift: 0),
            y: WindowKeyboardMotion.Axis(origin: actual.minY, destination: aligned.minY,
                velocity: velocity.y, duration: remaining, maximumDrift: 0))
    }

    private static func observeAxis(_ observation: inout AxisObservation?, requested: CGFloat,
                                    actual: CGFloat, at now: TimeInterval) -> Bool {
        guard actual > requested + 1 else { observation = nil; return false }
        guard var previous = observation, now >= previous.startedAt,
              abs(previous.actual - actual) <= 1, requested <= previous.lastRequest + 1 else {
            observation = AxisObservation(actual: actual, firstRequest: requested,
                lastRequest: requested, startedAt: now, count: 1)
            return false
        }
        if requested < previous.lastRequest - 0.5 { previous.count += 1 }
        previous.lastRequest = requested
        observation = previous
        return previous.count >= 2 && previous.firstRequest - requested >= 2
            && now - previous.startedAt >= 0.03
    }
}
