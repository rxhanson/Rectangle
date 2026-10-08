import CoreFoundation
import Foundation
import IOKit

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

struct TrackpadTouchFrame: Equatable, Codable, Sendable {
    var timestamp: Double
    var touches: [TrackpadTouch]

    init(timestamp: Double, touches: [TrackpadTouch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}

protocol TrackpadTouchSource: AnyObject {
    var onDeviceOverlap: (() -> Void)? { get set }
    var onContactCount: ((Int) -> Void)? { get set }
    var onFrame: ((TrackpadTouchFrame) -> Void)? { get set }
    var deviceCount: Int { get }
    func start()
    func stop()
}

// A second trackpad must lift before it can claim a fresh session after the current owner.
struct TrackpadDeviceSession {
    private var owner: UInt?
    private var waitingForLift = Set<UInt>()

    mutating func accepts(device: UInt, contacts: Int) -> Bool {
        if owner == device {
            if contacts == 0 { owner = nil }
            return true
        }
        if contacts == 0 {
            waitingForLift.remove(device)
            return false
        }
        guard owner == nil, waitingForLift.isEmpty else {
            waitingForLift.insert(device)
            return false
        }
        owner = device
        return true
    }
}
