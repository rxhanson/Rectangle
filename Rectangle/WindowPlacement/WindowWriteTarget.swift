import Cocoa

/// Identifies a window that an operation may write, including temporary missing IDs.
struct WindowWriteTarget {
    let element: AccessibilityElement?
    let windowID: CGWindowID?

    func overlaps(_ other: WindowWriteTarget) -> Bool {
        if let windowID, let otherID = other.windowID { return windowID == otherID }
        if let pid = element?.pid, let otherPID = other.element?.pid, pid != otherPID { return false }
        // Two wrappers in the same app can represent the same window even
        // when macOS temporarily stops providing a window ID.
        return true
    }
}

