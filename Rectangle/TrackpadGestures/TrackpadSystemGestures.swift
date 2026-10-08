import Foundation

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
