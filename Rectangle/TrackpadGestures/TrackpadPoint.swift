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
