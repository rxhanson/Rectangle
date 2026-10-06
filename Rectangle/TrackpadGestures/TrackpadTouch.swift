import Foundation

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
