import Foundation

struct TrackpadGestureRecognizer {
    private struct Session {
        var origin: TrackpadPoint
        var contacts: Int
        var maximumContacts: Int
        var peakRight: Double
        var peakLeft: Double
        var peakUp: Double
        var peakDown: Double
        var fired: Bool

        init(origin: TrackpadPoint, contacts: Int) {
            self.origin = origin
            self.contacts = contacts
            self.maximumContacts = contacts
            self.peakRight = 0
            self.peakLeft = 0
            self.peakUp = 0
            self.peakDown = 0
            self.fired = false
        }
        mutating func observe(_ velocity: TrackpadPoint) {
            peakRight = max(peakRight, velocity.x)
            peakLeft = max(peakLeft, -velocity.x)
            peakUp = max(peakUp, velocity.y)
            peakDown = max(peakDown, -velocity.y)
        }
        // Contact-count changes must not re-arm a gesture that already fired.
        mutating func rebaseline(origin: TrackpadPoint, contacts: Int) {
            self.origin = origin
            self.contacts = contacts
            self.maximumContacts = max(maximumContacts, contacts)
            self.peakRight = 0
            self.peakLeft = 0
            self.peakUp = 0
            self.peakDown = 0
        }

        func peakSpeed(towards direction: TrackpadDirection) -> Double {
            switch direction {
            case .right: return peakRight
            case .left: return peakLeft
            case .up: return peakUp
            case .down: return peakDown
            }
        }
    }

    private var config: TrackpadConfig
    private var session: Session?
    private var highestContactsInPhysicalSession = 0
    private var latched = false
    private var lastFireTime: Double?

    init(config: TrackpadConfig) {
        self.config = config
    }

    mutating func setConfig(_ config: TrackpadConfig) {
        self.config = config
    }

    mutating func process(_ frame: TrackpadTouchFrame) -> TrackpadGestureEvent? {
        let contacts = frame.touches.count

        if contacts == 0 {
            session = nil
            latched = false
            highestContactsInPhysicalSession = 0
            return nil
        }
        highestContactsInPhysicalSession = max(highestContactsInPhysicalSession, contacts)
        if contacts > 4 {
            session = nil
            latched = true
            return nil
        }

        guard contacts >= 3 else {
            session = nil
            return nil
        }

        let thresholds = config.effectiveThresholds
        let center = centroid(of: frame.touches)

        guard var current = session else {
            if !latched && !isInCooldown(at: frame.timestamp, thresholds) {
                session = Session(origin: center, contacts: contacts)
            }
            return nil
        }

        if current.contacts != contacts {
            current.rebaseline(origin: center, contacts: contacts)
        } else {
            current.observe(meanVelocity(of: frame.touches))
        }
        session = current

        guard !current.fired,
              contacts == current.maximumContacts,
              contacts == highestContactsInPhysicalSession else { return nil }

        let dx = center.x - current.origin.x
        let dy = center.y - current.origin.y
        let adx = abs(dx)
        let ady = abs(dy)
        let horizontal = adx >= ady
        let dominant = horizontal ? adx : ady
        let other = horizontal ? ady : adx

        guard dominant >= thresholds.distance else { return nil }

        let direction: TrackpadDirection =
            horizontal
            ? (dx > 0 ? .right : .left)
            : (dy > 0 ? .up : .down)
        guard current.peakSpeed(towards: direction) >= thresholds.velocity else { return nil }
        guard other <= 1e-9 || dominant / other >= thresholds.axisRatio else { return nil }

        current.fired = true
        session = current
        latched = true
        lastFireTime = frame.timestamp

        return TrackpadGestureEvent(direction: direction, timestamp: frame.timestamp, fingers: current.contacts)
    }

    private func isInCooldown(at timestamp: Double, _ thresholds: TrackpadThresholds) -> Bool {
        guard let last = lastFireTime else { return false }
        return (timestamp - last) * 1000.0 < thresholds.cooldownMs
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
