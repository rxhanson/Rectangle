//
//  ApplicationToggle.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/18/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class ApplicationToggle: NSObject {
    
    private var disabledApps = Set<String>()
    public private(set) var frontAppId: String? = "com.knollsoft.Rectangle"
    public private(set) var frontAppName: String? = "Rectangle"
    public private(set) var shortcutsDisabled: Bool = false

    private let shortcutManager: ShortcutManager
    
    init(shortcutManager: ShortcutManager) {
        self.shortcutManager = shortcutManager
        super.init()
        registerFrontAppChangeNote()
        if let disabledApps = getDisabledApps() {
            self.disabledApps = disabledApps
        }
    }
    
    public func reloadFromDefaults() {
        if let disabledApps = getDisabledApps() {
            self.disabledApps = disabledApps
        } else {
            disabledApps.removeAll()
        }
    }
    
    private func saveDisabledApps() {
        let encoder = JSONEncoder()
        if let jsonDisabledApps = try? encoder.encode(disabledApps) {
            if let jsonString = String(data: jsonDisabledApps, encoding: .utf8) {
                Defaults.disabledApps.value = jsonString
            }
        }
    }
    
    private func getDisabledApps() ->  Set<String>? {
        guard let jsonDisabledAppsString = Defaults.disabledApps.value else { return nil }
        
        let decoder = JSONDecoder()
        guard let jsonDisabledApps = jsonDisabledAppsString.data(using: .utf8) else { return nil }
        guard let disabledApps = try? decoder.decode(Set<String>.self, from: jsonDisabledApps) else { return nil }
        
        return disabledApps
    }

    private func disableShortcuts() {
        if !self.shortcutsDisabled {
            self.shortcutsDisabled = true
            self.shortcutManager.unbindShortcuts()
        }
    }
    
    private func enableShortcuts() {
        if self.shortcutsDisabled {
            self.shortcutsDisabled = false
            self.shortcutManager.bindShortcuts()
        }
    }

    public func disableFrontApp() {
        if let frontAppId = self.frontAppId {
            disabledApps.insert(frontAppId)
            saveDisabledApps()
            disableShortcuts()
        }
    }
    
    public func enableFrontApp() {
        if let frontAppId = self.frontAppId {
            disabledApps.remove(frontAppId)
            saveDisabledApps()
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
            self.frontAppId = application.bundleIdentifier
            self.frontAppName = application.localizedName
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
        Defaults.todoApplication.value = self.frontAppId
    }

    public func todoAppIsActive() -> Bool {
        return Defaults.todoApplication.value == self.frontAppId
    }
}
