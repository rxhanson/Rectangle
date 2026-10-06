import CoreGraphics
import Foundation

protocol TrackpadScrollEventTapDriving: AnyObject {
    var isEnabled: Bool { get }
    var onDisabled: (@Sendable () -> Void)? { get set }
    var onUnexpectedStop: (@Sendable () -> Void)? { get set }
    func start(filter: @escaping @Sendable (TrackpadScrollStreamPhase) -> Bool) -> Bool
    func reenable() -> Bool
    func recreate(filter: @escaping @Sendable (TrackpadScrollStreamPhase) -> Bool) -> Bool
    func stop()
}
