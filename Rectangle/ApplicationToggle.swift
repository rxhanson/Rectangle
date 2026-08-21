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
        applyEnhancedUIActivationPolicy(to: NSWorkspace.shared.frontmostApplication)
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

    private func applyEnhancedUIActivationPolicy(to application: NSRunningApplication?) {
        guard let application else { return }
        let enhancedUI = Defaults.enhancedUI.value
        let bundleIdentifier = application.bundleIdentifier
        let builtInAssistiveTechnologyEnabled = NSWorkspace.shared.isVoiceOverEnabled
            || NSWorkspace.shared.isSwitchControlEnabled
        guard enhancedUI.disablesEnhancedUIOnApplicationActivation(
            bundleIdentifier: bundleIdentifier,
            builtInAssistiveTechnologyEnabled: builtInAssistiveTechnologyEnabled
        ) else { return }

        let activatedApplicationPid = application.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            guard let activatedApplication = NSRunningApplication(processIdentifier: activatedApplicationPid),
                  activatedApplication.bundleIdentifier == bundleIdentifier else { return }
            AccessibilityElement(activatedApplicationPid).enhancedUserInterface = false
        }
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
            applyEnhancedUIActivationPolicy(to: application)
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
