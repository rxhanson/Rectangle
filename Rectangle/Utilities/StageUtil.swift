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
    
}
