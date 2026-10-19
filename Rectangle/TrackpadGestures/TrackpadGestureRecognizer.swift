import Foundation

struct TrackpadGestureRecognizer {
    private var config: TrackpadConfig
    private var origins: [Int: TrackpadPoint] = [:]
    private var recentVelocities: [(time: Double, values: [Int: TrackpadPoint])] = []
    private var highestContacts = 0
    private(set) var hasFired = false
    private var lastTimestamp: Double?
    private var lastFireTime: Double?
    private(set) var captureEligible = false
    private(set) var rejected = false
    private(set) var identitiesChanged = false

    init(config: TrackpadConfig) { self.config = config }
    mutating func setConfig(_ config: TrackpadConfig) { self.config = config }

    mutating func process(_ frame: TrackpadTouchFrame) -> TrackpadGestureEvent? {
        captureEligible = false
        identitiesChanged = false
        let touches = frame.touches
        guard !touches.isEmpty else {
            origins = [:]
            recentVelocities = []
            highestContacts = 0
            hasFired = false
            rejected = false
            lastTimestamp = nil
            return nil
        }
        let ids = Set(touches.map(\.identifier))
        guard frame.timestamp.isFinite, ids.count == touches.count,
              touches.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite
                  && (0...1).contains($0.position.x) && (0...1).contains($0.position.y)
                  && $0.velocity.x.isFinite && $0.velocity.y.isFinite }) else {
            rejected = true
            return nil
        }
        let previousIDs = Set(origins.keys)
        identitiesChanged = !previousIDs.isEmpty && !ids.isSubset(of: previousIDs)
        let discontinuous = lastTimestamp.map { frame.timestamp <= $0 || frame.timestamp - $0 > 0.25 } ?? false
        lastTimestamp = frame.timestamp
        highestContacts = max(highestContacts, touches.count)
        if touches.count > 4 || hasBroadContact(touches) { rejected = true }
        guard !rejected else { return nil }
        if ids != previousIDs || discontinuous {
            origins = Dictionary(uniqueKeysWithValues: touches.map { ($0.identifier, $0.position) })
            recentVelocities = []
            return nil
        }
        guard touches.count >= 3, touches.count == highestContacts, !hasFired else { return nil }
        let thresholds = config.effectiveThresholds
        if let lastFireTime, (frame.timestamp - lastFireTime) * 1000 < thresholds.cooldownMs { return nil }

        let deltas = touches.map { touch -> TrackpadPoint in
            let origin = origins[touch.identifier]!
            return .init(x: touch.position.x - origin.x, y: touch.position.y - origin.y)
        }
        let dx = deltas.reduce(0) { $0 + $1.x } / Double(deltas.count)
        let dy = deltas.reduce(0) { $0 + $1.y } / Double(deltas.count)
        let horizontal = abs(dx) >= abs(dy)
        let dominant = horizontal ? abs(dx) : abs(dy)
        let other = horizontal ? abs(dy) : abs(dx)
        let sign = (horizontal ? dx : dy) >= 0 ? 1.0 : -1.0
        let forward = deltas.map { (horizontal ? $0.x : $0.y) * sign }
        // A moving subset cannot borrow a resting contact to reach the finger count.
        // Keep this rejection sticky until physical lift, including a palm left behind.
        if let fastest = forward.max(), let slowest = forward.min(),
           fastest >= 0.06, slowest < fastest * 0.15 {
            rejected = true
            return nil
        }
        let aligned = zip(deltas, forward).allSatisfy { delta, travel in
            travel >= 0.012 && travel >= dominant * 0.5
                && abs(horizontal ? delta.y : delta.x) <= travel / thresholds.axisRatio
        }
        captureEligible = aligned
        recentVelocities.append((frame.timestamp, Dictionary(uniqueKeysWithValues: touches.map { ($0.identifier, $0.velocity) })))
        recentVelocities.removeAll { frame.timestamp - $0.time > 0.100 }
        guard aligned, dominant >= thresholds.distance,
              other <= 1e-9 || dominant / other >= thresholds.axisRatio else { return nil }
        // All fingers must have recent directional speed in the same sample.
        // A speed spike earlier in the contact session cannot qualify later drift.
        let fastEnough = recentVelocities.contains { sample in
            let speeds = touches.map { touch -> Double in
                let velocity = sample.values[touch.identifier] ?? .zero
                return (horizontal ? velocity.x : velocity.y) * sign
            }
            return speeds.allSatisfy { $0 >= thresholds.velocity * 0.25 }
                && speeds.reduce(0, +) / Double(speeds.count) >= thresholds.velocity
        }
        guard fastEnough else { return nil }
        hasFired = true
        lastFireTime = frame.timestamp
        let direction: TrackpadDirection = horizontal ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
        return .init(direction: direction, timestamp: frame.timestamp, fingers: touches.count)
    }

    private func hasBroadContact(_ touches: [TrackpadTouch]) -> Bool {
        // Metadata varies by device. Require two independent shape outliers;
        // unknown labels or a corner position alone do not identify a palm.
        let sizes = touches.compactMap(\.size).filter { $0.isFinite && $0 > 0 }.sorted()
        let axes = touches.compactMap(\.majorAxis).filter { $0.isFinite && $0 > 0 }.sorted()
        guard sizes.count == touches.count, axes.count == touches.count, touches.count >= 3 else { return false }
        let typicalSize = sizes[(sizes.count - 1) / 2]
        let typicalAxis = axes[(axes.count - 1) / 2]
        return touches.contains { ($0.size ?? 0) > typicalSize * 2.5 && ($0.majorAxis ?? 0) > typicalAxis * 2 }
    }
}

struct TrackpadGestureEvent: Equatable, Sendable {
    var direction: TrackpadDirection
    var fingers: Int
    var timestamp: Double

    init(direction: TrackpadDirection, timestamp: Double, fingers: Int = 3) {
        self.direction = direction
        self.fingers = fingers
        self.timestamp = timestamp
    }
}
