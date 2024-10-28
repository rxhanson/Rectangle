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
    public private(set) static var frontAppId: String? = "com.knollsoft.Rectangle"
    public private(set) static var frontAppName: String? = "Rectangle"
    public private(set) static var shortcutsDisabled: Bool = false

    private let shortcutManager: ShortcutManager
    
    init(shortcutManager: ShortcutManager) {
        self.shortcutManager = shortcutManager
        super.init()
        registerFrontAppChangeNote()
        subscribe()
        if let disabledApps = getDisabledApps() {
            self.disabledApps = disabledApps
        }
    }
    
    public func reloadFromDefaults() {
        subscribe()
        if let disabledApps = getDisabledApps() {
            self.disabledApps = disabledApps
        } else {
            disabledApps.removeAll()
        }
    }
    
    deinit {
        unsubscribe()
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

    public func disableFrontApp() {
        if let frontAppId = Self.frontAppId {
            disabledApps.insert(frontAppId)
            saveDisabledApps()
            disableShortcuts()
        }
    }
    
    public func enableFrontApp() {
        if let frontAppId = Self.frontAppId {
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
    
    @objc func windowActionTriggered(notification: NSNotification) {
        guard let parameters = notification.object as? ExecutionParameters else { return }
        
        let action = parameters.action

        switch action {
        case .ignoreApp:
            disableFrontApp()
            return
        case .unignoreApp:
            enableFrontApp()
            return
        default: break // NOOP
        }
    }
    
    private func unsubscribe() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func subscribe() {
        NotificationCenter.default.addObserver(self, selector: #selector(windowActionTriggered), name: WindowAction.ignoreApp.notificationName, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowActionTriggered), name: WindowAction.unignoreApp.notificationName, object: nil)
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
