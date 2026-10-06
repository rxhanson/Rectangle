import Cocoa

/// Render candidates from copied metadata without waiting for app replies.
/// Selection refreshes the snapshot and AX reference before placement.
struct LayoutHelperWindowSnapshot {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let bundleID: String
    let title: String
    let frame: CGRect
    let reportedMinimum: CGSize?
    let resizable: Bool?
    let element: AXUIElement?
    let observedAt: TimeInterval
    var isMinimized = false
    var desktopDisplays = Set<CGDirectDisplayID>()
    var isMainWindow: Bool?
    var isLayoutWindow: Bool?

    var previewKey: LayoutHelperPreviewKey {
        LayoutHelperPreviewKey(id: id, pid: pid, launch: launch,
                               width: Int(frame.width.rounded()), height: Int(frame.height.rounded()))
    }
    func accessibilityElement() -> AccessibilityElement? {
        element.map { AccessibilityElement($0, messagingTimeout: 0.05, windowID: id) }
    }
}
