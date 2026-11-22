import Cocoa
/// A worker owns this bounded AX handle. Generic window wrappers keep no
/// persistent timeout, identity cache, or feature-specific write state.
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
