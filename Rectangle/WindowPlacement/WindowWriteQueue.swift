import Cocoa

/// Animation and verified placement serialize writes to external applications.
/// The count belongs to main; bodies run on the serial queue. Ordinary actions
/// drain already accepted work before they regain synchronous write ownership.
final class WindowWriteQueue {
    static let shared = WindowWriteQueue()
    let queue = DispatchQueue(label: "Rectangle.WindowWrites", qos: .userInteractive)
    private(set) var pending = 0

    func perform(_ body: @escaping () -> Void) {
        pending += 1
        queue.async { [self] in
            body()
            DispatchQueue.main.async { self.pending -= 1 }
        }
    }
}

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
