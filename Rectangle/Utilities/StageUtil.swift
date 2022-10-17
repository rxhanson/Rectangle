//
//  StageUtil.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class StageUtil {
    static func stageCapable() -> Bool {
        guard #available(macOS 13, *) else { return false }
        return true
    }
    
    static func stageEnabled() -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager"), defaults.object(forKey: "GloballyEnabled") != nil
        else { return false }
        return defaults.bool(forKey: "GloballyEnabled")
    }
    
    static func stageStripShow() -> Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager"), defaults.object(forKey: "AutoHide") != nil
        else { return false }
        return !defaults.bool(forKey: "AutoHide")
    }
    
    static func stageStripVisible() -> Bool {
        let infos = WindowUtil.windowList().filter { $0.bundleIdentifier == "com.apple.WindowManager" && $0.screen == NSScreen.main }
        // A single window could be for the dragged window
        return infos.count >= 2
    }
    
    static func stageStripPosition() -> StageStripPosition {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock"), defaults.object(forKey: "orientation") != nil
        else { return .left }
        return defaults.string(forKey: "orientation") == "left" ? .right : .left
    }
}

enum StageStripPosition {
    case left
    case right
}
