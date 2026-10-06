import CoreGraphics
import Foundation

protocol TrackpadExclusiveGestureCapturing: AnyObject, Sendable {
    var isHealthy: Bool { get }
    var onHealthChange: (@Sendable (Bool) -> Void)? { get set }
    func start()
    func stop()
    func recheck(accessibilityTrusted: Bool)
    func setAccessibilityTrusted(_ trusted: Bool)
    func setEnabled(_ enabled: Bool)
    func setAllowedFingerCounts(_ counts: Set<Int>)
    func observeContactCount(_ count: Int)
    func contaminateSession()
    @discardableResult
    func performIfHealthy(_ action: () -> Void) -> Bool
    func reset()
}
