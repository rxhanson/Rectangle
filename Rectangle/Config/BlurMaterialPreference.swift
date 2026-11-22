import Foundation

enum BlurMaterial: Int {
    case standard = 0
    case liquidGlass = 1
}

struct BlurMaterialPreference: Default {
    let key = "blurMaterial"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var selection: BlurMaterial? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.intValue
        guard number.compare(NSNumber(value: raw)) == .orderedSame else { return nil }
        return BlurMaterial(rawValue: raw)
    }

    var hasSelection: Bool { selection != nil }

    // A saved standard choice and an absent choice render alike, but only the latter
    // should select Glass the first time the user enables footprint blur.
    var value: BlurMaterial {
        get { selection ?? .standard }
        nonmutating set {
            // Preferences can treat Boolean true and integer 1 as equal during a write.
            // Remove the malformed value first so the replacement keeps its integer type.
            if selection == nil, defaults.object(forKey: key) != nil { defaults.removeObject(forKey: key) }
            defaults.set(newValue.rawValue, forKey: key)
        }
    }

    func load(from codable: CodableDefault) {
        if let raw = codable.int, let material = BlurMaterial(rawValue: raw) {
            value = material
        }
    }

    func toCodable() -> CodableDefault {
        CodableDefault(int: value.rawValue)
    }
}
