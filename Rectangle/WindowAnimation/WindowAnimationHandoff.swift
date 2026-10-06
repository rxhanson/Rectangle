import Cocoa
import QuartzCore

/// Briefly reuses the previous animation's final geometry when retargeting.
/// This observation does not establish a window size limit.
struct WindowAnimationHandoff {
    struct Evidence {
        let destination: CGRect
        let frame: CGRect
        let sampledAt: TimeInterval
        let stableSince: TimeInterval
        let velocity: CGPoint
    }

    private var samples: [(frame: CGRect, time: TimeInterval, positionConfirmed: Bool)] = []
    private var lastAttempt: TimeInterval?
    private var attempts = 0

    mutating func shouldSample(at now: TimeInterval, endingAt end: TimeInterval) -> Bool {
        guard now >= end - 0.08, now < end, attempts < 3,
              lastAttempt.map({ now - $0 >= 1.0 / 30 - 0.000001 }) ?? true else { return false }
        attempts += 1
        lastAttempt = now
        return true
    }

    mutating func observe(ax: CGRect, server: CGRect?, at now: TimeInterval) {
        guard now.isFinite, let server, WindowAnimationGeometry.valid(ax),
              WindowAnimationGeometry.valid(server), abs(ax.width - server.width) <= 1,
              abs(ax.height - server.height) <= 1 else {
            samples.removeAll(keepingCapacity: true)
            return
        }
        if let first = samples.first, let last = samples.last,
           now <= last.time || now - last.time > 0.05
            || abs(ax.width - first.frame.width) > 1 || abs(ax.height - first.frame.height) > 1 {
            samples.removeAll(keepingCapacity: true)
        }
        // Size acknowledgments remain useful while position writes are still
        // in flight. Velocity requires corroborated positions throughout.
        samples.append((ax, now, WindowAnimationGeometry.near(ax, server, tolerance: 1)))
        if samples.count > 4 { samples.removeFirst() }
    }

    func evidence(for destination: CGRect, at now: TimeInterval) -> Evidence? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last,
              last.positionConfirmed,
              now >= last.time, now - last.time <= 1.0 / 30,
              last.time - first.time >= 1.0 / 30 else { return nil }
        func velocity(_ coordinate: (CGRect) -> CGFloat) -> CGFloat {
            guard samples.allSatisfy({ $0.positionConfirmed }) else { return 0 }
            let delta = coordinate(last.frame) - coordinate(first.frame)
            let pairs = Array(zip(samples, samples.dropFirst()))
            guard let lastMovement = pairs.last(where: { coordinate($0.0.frame) != coordinate($0.1.frame) }),
                  last.time - lastMovement.1.time <= 1.0 / 30 else { return 0 }
            guard pairs.allSatisfy({
                (coordinate($0.1.frame) - coordinate($0.0.frame)) * delta >= 0
            }) else { return 0 }
            return min(140, max(-140, delta / CGFloat(last.time - first.time)))
        }
        return Evidence(destination: destination, frame: last.frame, sampledAt: last.time,
            stableSince: first.time, velocity: CGPoint(x: velocity { $0.minX }, y: velocity { $0.minY }))
    }
}
