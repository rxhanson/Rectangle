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
    public private(set) var currentAppId: String? = "com.knollsoft.Rectangle"
    public private(set) var currentAppName: String? = "Rectangle"
    public private(set) var shortcutsDisabled: Bool = false
    public private(set) var shortcutsDisabledForAll: Bool = false
    
    private let shortcutManager: ShortcutManager
    
    init(shortcutManager: ShortcutManager) {
        self.shortcutManager = shortcutManager
        super.init()
        registerCurrentAppChangeNote()
        self.shortcutsDisabledForAll = Defaults.disabledForAll.enabled
        if let disabledApps = getDisabledApps() {
            self.disabledApps = disabledApps
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
        if Logger.logging {
            Logger.log("disabling shortcuts")
        }
        if !self.shortcutsDisabled {
            self.shortcutsDisabled = true
            self.shortcutManager.unbindShortcuts()
        }
    }
    
    private func enableShortcuts() {
        if Logger.logging {
            Logger.log("enabling shortcuts")
        }
        if self.shortcutsDisabled {
            self.shortcutsDisabled = false
            self.shortcutManager.bindShortcuts()
        }
    }
    
    public func disableForAllApps() {
        if  !self.shortcutsDisabledForAll {
            self.shortcutsDisabledForAll = true
            Defaults.disabledForAll.enabled = true
            disableShortcuts()
        }
    }
    
    public func disabledStatus() -> Bool {
        return self.shortcutsDisabledForAll || self.shortcutsDisabled
    }
    
    public func enableForAllApps() {
        if self.shortcutsDisabledForAll {
            self.shortcutsDisabledForAll = false
            Defaults.disabledForAll.enabled = false
            enableShortcuts()
        }
    }
    
    public func toggleDisableForAllApps() {
        if Logger.logging {
            Logger.log("toggleForAllApps")
        }
        if !self.shortcutsDisabledForAll {
            disableForAllApps()
        } else {
            enableForAllApps()
        }
        RectangleStatusItem.instance.refreshVisibility()
    }
    
    public func toggleDisableForCurrentApp() {
        if Logger.logging {
            Logger.log("toggleForCurrentApp")
        }
        if !self.shortcutsDisabled {
            disableCurrentApp()
        } else {
            enableCurrentApp()
        }
        RectangleStatusItem.instance.refreshVisibility()
    }

    public func disableCurrentApp() {
        if let currentAppId = self.currentAppId {
            disabledApps.insert(currentAppId)
            saveDisabledApps()
            disableShortcuts()
        }
    }
    
    public func enableCurrentApp() {
        if let currentAppId = self.currentAppId {
            disabledApps.remove(currentAppId)
            saveDisabledApps()
            enableShortcuts()
        }
    }
    
    public func isDisabledApp(bundleId: String) -> Bool {
        return disabledApps.contains(bundleId)
    }
    
    private func registerCurrentAppChangeNote() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.receiveCurrentAppChangeNote(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }
    
    @objc func receiveCurrentAppChangeNote(_ notification: Notification) {
        if let application = notification.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication {
            self.currentAppId = application.bundleIdentifier
            self.currentAppName = application.localizedName
            
            if Defaults.disabledForAll.enabled {
                disableShortcuts()
            } else if let currentAppId = application.bundleIdentifier {
                if isDisabledApp(bundleId: currentAppId) {
                    disableShortcuts()
                } else {
                    enableShortcuts()
                }
            } else {
                enableShortcuts()
            }
            RectangleStatusItem.instance.refreshVisibility()
        }
    }
    
}
