import CoreGraphics
import Foundation

enum QuartzScrollEventPhaseDecoder {
    private static let scrollEnded = UInt64(CGScrollPhase.ended.rawValue)
    private static let scrollCancelled = UInt64(CGScrollPhase.cancelled.rawValue)
    private static let momentumEnd = Int64(CGMomentumScrollPhase.end.rawValue)

    static func phase(scrollPhase: Int64, momentumPhase: Int64) -> TrackpadScrollStreamPhase {
        if momentumPhase == momentumEnd {
            return .momentumEnded
        }
        if momentumPhase != 0 {
            return .active
        }
        let scrollBits = UInt64(bitPattern: scrollPhase)
        if (scrollBits & scrollCancelled) != 0 {
            return .cancelled
        }
        if (scrollBits & scrollEnded) != 0 {
            return .scrollEnded
        }
        if scrollPhase != 0 {
            return .active
        }
        return .none
    }
}
