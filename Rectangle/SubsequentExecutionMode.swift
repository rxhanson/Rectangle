/// SubsequentExecutionMode.swift

import Foundation

enum SubsequentExecutionMode: Int {
    case resize = 0 // based on Spectacle
    case acrossMonitor = 1
    case none = 2
    case acrossAndResize = 3 // across monitor for right/left, spectacle resize for all else
    case cycleMonitor = 4
    case resizeAndCycleQuadrants = 5
    case switchSides = 6 // repeated half actions move to the opposite side
    
    var title: String {
        switch self {
        case .resize: return String(localized: "cycle sizes on side actions")
        case .acrossMonitor: return String(localized: "move to adjacent display on left or right")
        case .none: return String(localized: "do nothing")
        case .acrossAndResize: return String(localized: "move to adjacent on left/right, or cycle size on side")
        case .cycleMonitor: return String(localized: "cycle through displays")
        case .resizeAndCycleQuadrants: return String(localized: "cycle positions on quadrants, cycle sizes on side")
        case .switchSides: return String(localized: "Switch to the opposite side on half actions")
        }
    }
    
    var resizes: Bool {
        switch self {
        case .resize, .acrossAndResize, .resizeAndCycleQuadrants: return true
        default: return false
        }
    }
    
    static var ordered: [SubsequentExecutionMode] = [.none, .cycleMonitor, .resize, .acrossMonitor, .acrossAndResize, .resizeAndCycleQuadrants, .switchSides]
}

class SubsequentExecutionDefault: Default {
    public private(set) var key: String = "subsequentExecutionMode"
    private var initialized = false
    
    var value: SubsequentExecutionMode {
        didSet {
            if initialized {
                UserDefaults.standard.set(value.rawValue, forKey: key)
            }
        }
    }
    
    init() {
        let intValue = UserDefaults.standard.integer(forKey: key)
        value = SubsequentExecutionMode(rawValue: intValue) ?? .resize
        initialized = true
    }
    
    var resizes: Bool {
        switch value {
        case .resize, .acrossAndResize, .resizeAndCycleQuadrants: return true
        default: return false
        }
    }

    /// First/last thirds and fourths step through their positions on repeat, except when repeating
    /// should do nothing or move to the adjacent display (which needs an adjacent display to move to).
    func cyclesThirdsAndFourths(hasAdjacentScreen: Bool) -> Bool {
        switch value {
        case .none: return false
        case .acrossMonitor: return !hasAdjacentScreen
        default: return true
        }
    }

    var cyclesQuadrantPositions: Bool {
        switch value {
        case .resizeAndCycleQuadrants: return true
        default: return false
        }
    }

    var traversesDisplays: Bool {
        switch value {
        case .acrossMonitor, .acrossAndResize: return true
        default: return false
        }
    }

    func load(from codable: CodableDefault) {
        if let int = codable.int,
           let mode = SubsequentExecutionMode(rawValue: int) {
            value = mode
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(int: value.rawValue)
    }

}
