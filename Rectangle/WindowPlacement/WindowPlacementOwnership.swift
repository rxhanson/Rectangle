import Cocoa

/// A later action can supersede the active command without taking ownership of
/// every other window. Recovery may write only while its window's token is current.
final class WindowPlacementOwnership {
    final class Token {
        fileprivate(set) var isCurrent = true
    }

    private struct Entry {
        let element: AccessibilityElement
        let windowID: CGWindowID?
        let token: Token

        func matches(_ other: AccessibilityElement, id: CGWindowID?) -> Bool {
            if let windowID, let id { return windowID == id }
            if let pid = element.pid, let otherPID = other.pid, pid != otherPID { return false }
            return true
        }
    }

    private var entries: [Entry] = []

    func claim(_ element: AccessibilityElement, id: CGWindowID?) -> Token {
        for entry in entries where entry.matches(element, id: id) { entry.token.isCurrent = false }
        entries.removeAll { !$0.token.isCurrent }
        let token = Token()
        entries.append(Entry(element: element, windowID: id, token: token))
        return token
    }

    func finish(_ token: Token) {
        token.isCurrent = false
        entries.removeAll { $0.token === token }
    }
}
