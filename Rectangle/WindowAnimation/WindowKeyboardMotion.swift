import Cocoa
import QuartzCore

/// A finite trajectory can be replaced without estimating velocity from rounded AX frames.
struct WindowKeyboardMotion {
    static let duration: TimeInterval = 0.18

    struct Sample {
        let frame: CGRect
        let velocity: [CGFloat]
        let progress: CGFloat
    }

    struct Axis {
        let origin: CGFloat
        let destination: CGFloat
        let initialVelocity: CGFloat
        let brakingDuration: TimeInterval
        let duration: TimeInterval

        init(origin: CGFloat, destination: CGFloat, velocity: CGFloat, duration: TimeInterval,
             maximumDrift: CGFloat = 2) {
            self.origin = origin
            self.destination = destination
            self.duration = duration
            let delta = destination - origin
            let velocity = velocity.isFinite && delta != 0 ? velocity : 0
            if velocity * delta < 0, maximumDrift > 0 {
                initialVelocity = velocity
                brakingDuration = min(0.03, Double(3 * maximumDrift / abs(velocity)))
            } else {
                // A short remaining distance may not accommodate the incoming speed.
                // Prefer a monotonic path to crossing the new destination.
                let limit = 3 * abs(delta) / CGFloat(duration)
                initialVelocity = velocity * delta > 0 ? min(abs(velocity), limit) * (delta < 0 ? -1 : 1) : 0
                brakingDuration = 0
            }
        }

        func sample(at elapsed: TimeInterval) -> (position: CGFloat, velocity: CGFloat) {
            if elapsed >= duration { return (destination, 0) }
            let elapsed = max(0, elapsed)
            if brakingDuration > 0, elapsed < brakingDuration {
                let u = CGFloat(elapsed / brakingDuration)
                let displacement = initialVelocity * CGFloat(brakingDuration) * (u - u * u + u * u * u / 3)
                return (origin + displacement, initialVelocity * (1 - u) * (1 - u))
            }
            let start = origin + initialVelocity * CGFloat(brakingDuration) / 3
            let seconds = CGFloat(duration - brakingDuration)
            let u = CGFloat((elapsed - brakingDuration) / (duration - brakingDuration))
            let velocity = brakingDuration > 0 ? 0 : initialVelocity
            let delta = destination - start
            let position = start + delta * u * u * (3 - 2 * u) + seconds * velocity * u * (1 - u) * (1 - u)
            let derivative = delta * 6 * u * (1 - u) / seconds + velocity * (1 - 4 * u + 3 * u * u)
            return (position, derivative)
        }
    }

    let origin: CGRect
    let destination: CGRect
    let startedAt: TimeInterval
    private let axes: [Axis]

    init(from origin: CGRect, to destination: CGRect, velocity: [CGFloat] = [0, 0, 0, 0],
         at time: TimeInterval, driftLimits: [CGFloat] = [2, 2, 2, 2]) {
        self.origin = origin
        self.destination = destination
        startedAt = time
        let starts = [origin.minX, origin.minY, origin.width, origin.height]
        let ends = [destination.minX, destination.minY, destination.width, destination.height]
        axes = starts.indices.map {
            Axis(origin: starts[$0], destination: ends[$0], velocity: velocity[$0],
                 duration: Self.duration, maximumDrift: driftLimits[$0])
        }
    }

    func sample(at time: TimeInterval) -> Sample {
        let elapsed = max(0, time - startedAt)
        let values = axes.map { $0.sample(at: elapsed) }
        return Sample(frame: CGRect(x: values[0].position, y: values[1].position,
                                    width: values[2].position, height: values[3].position),
                      velocity: values.map(\.velocity), progress: CGFloat(min(1, elapsed / Self.duration)))
    }
}
