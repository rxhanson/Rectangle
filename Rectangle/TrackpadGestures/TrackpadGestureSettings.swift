import Foundation

struct TrackpadGestureSettings: Codable, Equatable {
    var enabled = false
    var fingers = 4
    var sensitivity = TrackpadSensitivity.high
    var up = WindowAction.maximize.rawValue
    var down = TrackpadGestureAction.minimize
    var left = WindowAction.leftHalf.rawValue
    var right = WindowAction.rightHalf.rawValue

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, fingers, sensitivity, up, down, left, right }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        fingers = try values.decode(Int.self, forKey: .fingers)
        sensitivity = try values.decodeIfPresent(TrackpadSensitivity.self, forKey: .sensitivity) ?? .high
        up = try values.decode(Int.self, forKey: .up)
        down = try values.decode(Int.self, forKey: .down)
        left = try values.decode(Int.self, forKey: .left)
        right = try values.decode(Int.self, forKey: .right)
    }

    subscript(direction: TrackpadDirection) -> Int {
        get {
            switch direction {
            case .up: return up
            case .down: return down
            case .left: return left
            case .right: return right
            }
        }
        set {
            switch direction {
            case .up: up = newValue
            case .down: down = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    var validated: Self {
        var result = self
        if ![3, 4].contains(fingers) { result.fingers = 4 }
        for direction in TrackpadDirection.allCases where !TrackpadGestureAction.isValid(result[direction]) {
            result[direction] = TrackpadGestureAction.none
        }
        return result
    }
}

enum TrackpadGestureAction {
    static let none = -1
    static let minimize = -2
    static let common = [WindowAction.maximize.rawValue, minimize,
                         WindowAction.leftHalf.rawValue, WindowAction.rightHalf.rawValue,
                         WindowAction.topHalf.rawValue, WindowAction.bottomHalf.rawValue,
                         WindowAction.restore.rawValue, WindowAction.center.rawValue]
    // Multi-window and Todo actions do not operate on the window under the cursor.
    static let actions = WindowAction.active.filter {
        ![.tileAll, .tileRows, .tileColumns, .cascadeAll, .cascadeActiveApp, .tileActiveApp,
          .leftTodo, .rightTodo, .reverseAll].contains($0)
    }
    static func isValid(_ value: Int) -> Bool {
        value == none || value == minimize || actions.contains { $0.rawValue == value }
    }
    static func title(_ value: Int) -> String {
        if value == none { return String(localized: "None") }
        if value == minimize { return String(localized: "Minimize") }
        guard let action = WindowAction(rawValue: value) else { return String(localized: "None") }
        if let title = action.displayName { return title }
        switch action {
        case .topLeftThird: return String(localized: "Top Left Third")
        case .topRightThird: return String(localized: "Top Right Third")
        case .bottomLeftThird: return String(localized: "Bottom Left Third")
        case .bottomRightThird: return String(localized: "Bottom Right Third")
        case .doubleHeightUp: return String(localized: "Double Height Up")
        case .doubleHeightDown: return String(localized: "Double Height Down")
        case .doubleWidthLeft: return String(localized: "Double Width Left")
        case .doubleWidthRight: return String(localized: "Double Width Right")
        case .halveHeightUp: return String(localized: "Halve Height Up")
        case .halveHeightDown: return String(localized: "Halve Height Down")
        case .halveWidthLeft: return String(localized: "Halve Width Left")
        case .halveWidthRight: return String(localized: "Halve Width Right")
        case .specified: return String(localized: "Specified Size")
        case .centerProminently: return String(localized: "Center Prominently")
        case .largerHeight: return String(localized: "Larger Height")
        case .smallerHeight: return String(localized: "Smaller Height")
        case .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive,
             .displaySix, .displaySeven, .displayEight, .displayNine:
            return String(localized: "Display \(value - WindowAction.displayOne.rawValue + 1)")
        default: return action.name
        }
    }
}

// Read system assignments without changing the user's macOS gesture preferences.
enum TrackpadSystemGestures {
    static func occupiedFingerCounts() -> Set<Int> {
        var result = Set<Int>()
        let keys = [("TrackpadThreeFingerHorizSwipeGesture", 3),
                    ("TrackpadThreeFingerVertSwipeGesture", 3),
                    ("TrackpadThreeFingerDrag", 3),
                    ("TrackpadFourFingerHorizSwipeGesture", 4),
                    ("TrackpadFourFingerVertSwipeGesture", 4)]
        for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            CFPreferencesAppSynchronize(domain as CFString)
            for (key, fingers) in keys {
                let value = CFPreferencesCopyValue(key as CFString, domain as CFString,
                                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                if (value as? NSNumber)?.intValue ?? 0 > 0 { result.insert(fingers) }
            }
        }
        return result
    }
}

enum TrackpadSensitivity: String, Codable, CaseIterable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        }
    }

    var thresholds: TrackpadThresholds {
        switch self {
        case .low: return TrackpadThresholds(distance: 0.225, velocity: 1.95)
        case .medium: return TrackpadThresholds(distance: 0.15, velocity: 1.30)
        case .high: return TrackpadThresholds(distance: 0.098, velocity: 0.85)
        }
    }
}
