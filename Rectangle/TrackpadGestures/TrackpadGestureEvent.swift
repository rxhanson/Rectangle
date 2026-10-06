import Foundation

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
