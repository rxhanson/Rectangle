import Foundation

struct TrackpadPoint: Equatable, Codable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = TrackpadPoint(x: 0, y: 0)

    var magnitude: Double { (x * x + y * y).squareRoot() }
}

func centroid(of touches: [TrackpadTouch]) -> TrackpadPoint {
    guard !touches.isEmpty else { return .zero }
    let n = Double(touches.count)
    let sx = touches.reduce(0.0) { $0 + $1.position.x }
    let sy = touches.reduce(0.0) { $0 + $1.position.y }
    return TrackpadPoint(x: sx / n, y: sy / n)
}
func meanVelocity(of touches: [TrackpadTouch]) -> TrackpadPoint {
    guard !touches.isEmpty else { return .zero }
    let n = Double(touches.count)
    let vx = touches.reduce(0.0) { $0 + $1.velocity.x } / n
    let vy = touches.reduce(0.0) { $0 + $1.velocity.y } / n
    return TrackpadPoint(x: vx, y: vy)
}
func meanSpeed(of touches: [TrackpadTouch]) -> Double {
    meanVelocity(of: touches).magnitude
}

struct TrackpadTouch: Equatable, Codable, Sendable {
    var identifier: Int
    var position: TrackpadPoint
    var velocity: TrackpadPoint

    init(identifier: Int, position: TrackpadPoint, velocity: TrackpadPoint) {
        self.identifier = identifier
        self.position = position
        self.velocity = velocity
    }
}
struct TrackpadTouchFrame: Equatable, Codable, Sendable {
    var timestamp: Double
    var touches: [TrackpadTouch]

    init(timestamp: Double, touches: [TrackpadTouch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}

enum TrackpadDirection: String, Codable, Sendable, CaseIterable {
    case left, right, up, down
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

struct TrackpadThresholds {
    var distance = 0.15
    var velocity = 1.30
    var axisRatio = 1.5
    var cooldownMs = 300.0
}
struct TrackpadConfig {
    static let `default` = TrackpadConfig()
    var effectiveThresholds = TrackpadThresholds()
}
