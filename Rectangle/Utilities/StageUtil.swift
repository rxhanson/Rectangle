/// StageUtil.swift

import Foundation

class StageUtil {
    private static let windowManagerDefaults = UserDefaults(suiteName: "com.apple.WindowManager")
    private static let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    
    static var stageCapable: Bool {
        guard #available(macOS 13, *) else {
            return false
        }
        return true
    }
    
    static var stageEnabled: Bool {
        guard let value = windowManagerDefaults?.object(forKey: "GloballyEnabled") as? Bool else {
            return false
        }
        return value
    }

    static func observeEnabled(_ change: @escaping () -> Void) -> NSObject? {
        guard stageCapable, let windowManagerDefaults else { return nil }
        return EnabledObservation(defaults: windowManagerDefaults, change: change)
    }

    private final class EnabledObservation: NSObject {
        private let defaults: UserDefaults
        private let change: () -> Void

        init(defaults: UserDefaults, change: @escaping () -> Void) {
            self.defaults = defaults
            self.change = change
            super.init()
            defaults.addObserver(self, forKeyPath: "GloballyEnabled", options: [], context: nil)
        }

        deinit { defaults.removeObserver(self, forKeyPath: "GloballyEnabled") }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            guard keyPath == "GloballyEnabled" else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
                return
            }
            DispatchQueue.main.async { [weak self] in self?.change() }
        }
    }
    
    static var stageStripShow: Bool {
        guard let value = windowManagerDefaults?.object(forKey: "AutoHide") as? Bool else {
            return false
        }
        return !value
    }
    
    static var stageStripPosition: StageStripPosition {
        switch dockDefaults?.string(forKey: "orientation") {
        case "left":
            return .right
        case "right":
            return .left
        default: // bottom
            let isRTL = Locale.current.language.characterDirection == .rightToLeft
            return isRTL ? .right : .left
        }
    }
    
    static func isStageStripVisible(_ screen: NSScreen? = .main) -> Bool {
        guard let screen else {
            return false
        }
        let infos = WindowUtil.getWindowList().filter { info in
            guard info.processName == "WindowManager" else {
                return false
            }
            let frame = info.frame.screenFlipped
            let screens = NSScreen.screens.filter { $0.frame.minY <= frame.minY && frame.maxY <= $0.frame.maxY }
            var infoScreen: NSScreen?
            if stageStripPosition == .left {
                infoScreen = screens.min { abs(frame.minX - $0.frame.minX) < abs(frame.minX - $1.frame.minX) }
            } else {
                infoScreen = screens.min { abs($0.frame.maxX - frame.maxX) < abs($1.frame.maxX - frame.maxX) }
            }
            return infoScreen == screen
        }
        // A single window could be for the dragged window
        return infos.count >= 2
    }
    
    private static func getStageStripWindowGroups(_ screen: NSScreen? = .main) -> [[CGWindowID]] {
        guard
            let screen,
            let appElement = AccessibilityElement("com.apple.WindowManager"),
            let stripElements = appElement.getChildElements(.group),
            let stripElement = (stripElements.first {
                let frame = $0.frame.screenFlipped
                return !frame.isNull && screen.frame.contains(frame)
            }),
            let groupElements = stripElement.getChildElement(.list)?.getChildElements(.button)
        else {
            return []
        }
        return groupElements.compactMap { $0.windowIds }
    }
    
    static func getStageStripWindowGroup(_ windowId: CGWindowID, _ screen: NSScreen? = .main) -> [CGWindowID]? {
        return getStageStripWindowGroups(screen).first { $0.contains(windowId) }
    }
}

enum StageStripPosition {
    case left
    case right
}
