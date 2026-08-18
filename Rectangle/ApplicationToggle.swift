/// ApplicationToggle.swift

import Cocoa

class ApplicationToggle: NSObject {
    
    private var disabledApps = Set<String>()
    public private(set) static var frontAppId: String? = "com.knollsoft.Rectangle"
    public private(set) static var frontAppName: String? = "Rectangle"
    public private(set) static var shortcutsDisabled: Bool = false

    private let shortcutManager: ShortcutManager
    
    init(shortcutManager: ShortcutManager) {
        self.shortcutManager = shortcutManager
        super.init()
        registerFrontAppChangeNote()
        if let disabledApps = Defaults.disabledApps.typedValue {
            self.disabledApps = disabledApps
        }
    }
    
    public func reloadFromDefaults() {
        if let disabledApps = Defaults.disabledApps.typedValue {
            self.disabledApps = disabledApps
        } else {
            disabledApps.removeAll()
        }
    }

    private func disableShortcuts() {
        if !Self.shortcutsDisabled {
            Self.shortcutsDisabled = true
            self.shortcutManager.unbindShortcuts()
            if !Defaults.ignoreDragSnapToo.userDisabled {
                Notification.Name.windowSnapping.post(object: false)
            }
        }
    }
    
    private func enableShortcuts() {
        if Self.shortcutsDisabled {
            Self.shortcutsDisabled = false
            self.shortcutManager.bindShortcuts()
            if !Defaults.ignoreDragSnapToo.userDisabled {
                Notification.Name.windowSnapping.post(object: true)
            }
        }
    }

    public func disableApp(appBundleId: String? = frontAppId) {
        if let appBundleId {
            disabledApps.insert(appBundleId)
            Defaults.disabledApps.typedValue = disabledApps
            disableShortcuts()
        }
    }
    
    public func enableApp(appBundleId: String? = frontAppId) {
        if let appBundleId {
            disabledApps.remove(appBundleId)
            Defaults.disabledApps.typedValue = disabledApps
            enableShortcuts()
        }
    }
    
    public func isDisabled(bundleId: String) -> Bool {
        return disabledApps.contains(bundleId)
    }
    
    private func registerFrontAppChangeNote() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.receiveFrontAppChangeNote(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc func receiveFrontAppChangeNote(_ notification: Notification) {
        if let application = notification.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication {
            Self.frontAppId = application.bundleIdentifier
            Self.frontAppName = application.localizedName
            if let frontAppId = application.bundleIdentifier {
                if isDisabled(bundleId: frontAppId) {
                    disableShortcuts()
                } else {
                    enableShortcuts()
                }
                Notification.Name.frontAppChanged.post()
            } else {
                enableShortcuts()
            }
            if Defaults.enhancedUI.value == .frontmostDisable {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                    AccessibilityElement.getFrontApplicationElement()?.enhancedUserInterface = false
                }
            }
        }
    }
}

// todo mode
extension ApplicationToggle {
    public func setTodoApp() {
        Defaults.todoApplication.value = Self.frontAppId
    }

    public func todoAppIsActive() -> Bool {
        return Defaults.todoApplication.value == Self.frontAppId
    }
}
