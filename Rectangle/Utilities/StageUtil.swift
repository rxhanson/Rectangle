//
//  StageUtil.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

class StageUtil {
    static var stageCapable: Bool {
        guard #available(macOS 13, *) else { return false }
        return true
    }
    
    static var stageEnabled: Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager"), defaults.object(forKey: "GloballyEnabled") != nil
        else { return false }
        return defaults.bool(forKey: "GloballyEnabled")
    }
    
    static var stageStripShow: Bool {
        guard let defaults = UserDefaults(suiteName: "com.apple.WindowManager"), defaults.object(forKey: "AutoHide") != nil
        else { return false }
        return !defaults.bool(forKey: "AutoHide")
    }
    
    static var stageStripPosition: StageStripPosition {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock"), defaults.object(forKey: "orientation") != nil
        else { return .left }
        return defaults.string(forKey: "orientation") == "left" ? .right : .left
    }
    
    static func getStageStripWindowGroups() -> [[CGWindowID]] {
        var groups = [[CGWindowID]]()
        if let appElement = AccessibilityElement("com.apple.WindowManager"),
           let groupElements = appElement.getChildElement(.group)?.getChildElement(.list)?.getChildElements(.button) {
            for groupElement in groupElements {
                guard let windowIds = groupElement.windowIds else { continue }
                groups.append(windowIds)
            }
        }
        return groups
    }
    
    static func getStageStripWindowGroup(_ windowId: CGWindowID) -> [CGWindowID]? {
        return getStageStripWindowGroups().first { $0.contains(windowId) }
    }
}

enum StageStripPosition {
    case left
    case right
}
