import Cocoa

/// An action accepted by WindowManager after its target and ownership policy
/// are known. Consumers can correlate its later settlement by request ID.
struct WindowPlacementAcceptance {
    let requestID: UUID
    let result: ResultParameters
}

/// Read-only outcome for a placement that observers may act on. The achieved
/// frame uses AX coordinates. The calculation result uses AppKit coordinates.
struct WindowPlacementSettlement {
    let requestID: UUID
    let result: ResultParameters
    let achievedFrame: CGRect
    let alreadyAchieved: Bool

    func publish() {
        guard result.action != .restore, WindowGeometry.valid(achievedFrame) else { return }
        Notification.Name.windowPlacementSettled.post(object: self)
    }
}

extension Notification.Name {
    static let windowPlacementAccepted = Notification.Name("windowPlacementAccepted")
    static let windowPlacementSettled = Notification.Name("windowPlacementSettled")
}
