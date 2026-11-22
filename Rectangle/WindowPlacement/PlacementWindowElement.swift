import Cocoa
/// A placement worker owns this AX handle with a bounded messaging timeout.
/// Its window ID ties readback to the window reserved for the operation.
final class PlacementWindowElement: AccessibilityElement {
    private let id: CGWindowID
    init(_ element: AXUIElement, messagingTimeout: Float = 0.05, windowID: CGWindowID) {
        id = windowID
        super.init(element)
        setMessagingTimeout(messagingTimeout)
    }
    override var windowId: CGWindowID? { id }
    func writePosition(_ position: CGPoint) -> AXError {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return .failure }
        return AXUIElementSetAttributeValue(axElement, kAXPositionAttribute as CFString, value)
    }
    func writeSize(_ size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(axElement, kAXSizeAttribute as CFString, value)
    }
}
