import Foundation

enum TrackpadScrollStreamPhase: Equatable, Sendable {
    case none
    case active
    case scrollEnded
    case cancelled
    case momentumEnded
}
