//
//  StageUtil.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class StageUtil {
    
    static func stageVisible() -> Bool {
        guard let stageDefaults = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        
        return stageDefaults.bool(forKey: "GloballyEnabled") && !stageDefaults.bool(forKey: "AutoHide")
    }

    static func stageWindowPresent() -> Bool {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        if let windowInfo = CGWindowListCopyWindowInfo(options, 0) as? Array<Dictionary<String,Any>> {
            for infoDict in windowInfo {
                if let bounds = infoDict[kCGWindowBounds as String] as? [String: CGFloat] {
                    guard let name = infoDict[kCGWindowOwnerName as String] as? String,
                          let w = bounds["Width"],
                          let h = bounds["Height"]
                    else { continue }
                    if name == "WindowManager" && w == 64 && h == 64 {
                        return true
                    }
                }
            }
        }
        return false
    }
    
}
