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
    
    static func stagePresent(_ windowInfo: Array<Dictionary<String,Any>>? = nil) -> Bool {
        var windowInfo = windowInfo
        if windowInfo == nil {
            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
            windowInfo = CGWindowListCopyWindowInfo(options, 0) as? Array<Dictionary<String,Any>>
        }
        if let windowInfo = windowInfo {
            var count = 0
            for infoDict in windowInfo {
                let name = infoDict[kCGWindowOwnerName as String] as? String
                if name == "WindowManager" {
                    count += 1
                    // A single window could be for the dragged window
                    if count == 2 { return true }
                }
            }
        }
        return false
    }
    
    static func stagePosition() -> StagePosition {
        // When the Dock is on the left
        if NSScreen.main!.visibleFrame.origin.x > 0 { return .right }
        return .left
    }
}

enum StagePosition {
    case left
    case right
}
