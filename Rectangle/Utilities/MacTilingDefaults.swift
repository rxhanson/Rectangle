//
//  MacTilingDefaults.swift
//  Rectangle
//
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

/// Read / disable the user defaults values for the macOS built-in window tiling, added in macOS 15 Sequoia.
/// These are toggled in the Desktop & Dock System Settings Pane:
enum MacTilingDefaults: String {
    case tilingByEdgeDrag = "EnableTilingByEdgeDrag"
    case tilingOptionAccelerator = "EnableTilingOptionAccelerator"
    case tiledWindowMargins = "EnableTiledWindowMargins"
    
    var enabled: Bool {
        guard #available(macOS 15, *), let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        else {
            return false
        }
        
        if defaults.object(forKey: self.rawValue) == nil { // These are enabled by default
            return true
        }
        return defaults.bool(forKey: self.rawValue)
    }
    
    func disable() {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager")
        else {
            return
        }
        
        defaults.set(false, forKey: self.rawValue)
        defaults.synchronize()
    }
    
    static func openSystemSettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.Desktop-Settings.extension")!)
    }
}
