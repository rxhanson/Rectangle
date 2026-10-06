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
