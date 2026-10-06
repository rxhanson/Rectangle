import Foundation

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
