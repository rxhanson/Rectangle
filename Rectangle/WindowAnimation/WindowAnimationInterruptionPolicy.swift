import Cocoa
import QuartzCore

enum WindowAnimationInterruptionPolicy {
    static func isMissionControlElement(role: String?, identifier: String?) -> Bool {
        role == kAXGroupRole && identifier == "mc"
    }

    static var missionControlActive: Bool {
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

    static func shouldCancel(activatedPID: pid_t?, targetPID: pid_t) -> Bool {
        guard let activatedPID else { return false }
        return activatedPID != targetPID
    }
}
