import Foundation

struct TrackpadTouchFrame: Equatable, Codable, Sendable {
    var timestamp: Double
    var touches: [TrackpadTouch]

    init(timestamp: Double, touches: [TrackpadTouch]) {
        self.timestamp = timestamp
        self.touches = touches
    }
}
