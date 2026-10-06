import Foundation

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
