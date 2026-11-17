/// MissionControl.swift

import Cocoa

enum MissionControl {
    static func isMissionControlElement(role: String?, identifier: String?) -> Bool {
        role == kAXGroupRole && identifier == "mc"
    }

    /// Whether Mission Control is showing. A best-effort read of the Dock's accessibility tree.
    static var isActive: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return false }
        // Mission Control does not necessarily activate Dock or change the current Space.
        // Its AX identifier is independent of the localized title. This is a best-effort
        // system marker; ordinary Dock groups and unavailable AX reads must not match.
        return children.contains { child in
            var role: CFTypeRef?
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard role as? String == kAXGroupRole else { return false }
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier)
            return isMissionControlElement(role: role as? String, identifier: identifier as? String)
        }
    }
}
