//
//  StageUtil.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class StageUtil {
    static func stageCapable() -> Bool {
        if #available(macOS 13, *) { return true }
        return false
    }
    
    static func stageEnabled() -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        return defaults.bool(forKey: "GloballyEnabled")
    }
    
    static func stageHide() -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        return defaults.bool(forKey: "AutoHide")
    }
    
    static func stagePresent() -> Bool {
        let infos = WindowUtil.windowList().filter { $0.bundleIdentifier == "com.apple.WindowManager" && $0.screen == NSScreen.main }
        // A single window could be for the dragged window
        return infos.count >= 2
    }
    
    static func stagePosition() -> StagePosition {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock") else { return .left }
        return defaults.string(forKey: "orientation") == "left" ? .right : .left
    }
}

enum StagePosition {
    case left
    case right
}
