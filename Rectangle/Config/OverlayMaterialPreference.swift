import AppKit

enum OverlayMaterial: Int {
    case standard = 0
    case liquidGlass = 1
    case noBlur = 2

    var usesBlur: Bool { self != .noBlur }

    static var supportsLiquidGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    func effective(supportsLiquidGlass: Bool, reduceTransparency: Bool) -> Self {
        if reduceTransparency { return .noBlur }
        return self == .liquidGlass && !supportsLiquidGlass ? .standard : self
    }
}

struct OverlayMaterialPreference: Default {
    private static let footprintKey = "footprintBlur"
    private static let footprintMaterialKey = "blurMaterial"

    let key = "overlayMaterial"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var value: OverlayMaterial {
        get { storedSelection ?? .noBlur }
        nonmutating set {
            // Clear malformed values before writing an integer. Preferences can otherwise
            // preserve a Boolean when its numeric value matches the new enum case.
            if storedSelection == nil, defaults.object(forKey: key) != nil { defaults.removeObject(forKey: key) }
            defaults.set(newValue.rawValue, forKey: key)
        }
    }

    private var storedSelection: OverlayMaterial? {
        storedInteger(forKey: key).flatMap(OverlayMaterial.init(rawValue:))
    }

    private func storedInteger(forKey key: String) -> Int? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.intValue
        return number.compare(NSNumber(value: raw)) == .orderedSame ? raw : nil
    }

    func migrateFootprintSetting() {
        guard defaults.object(forKey: Self.footprintKey) != nil else { return }
        if storedSelection == nil {
            value = footprintSelection(blurred: defaults.bool(forKey: Self.footprintKey),
                                       rawMaterial: storedInteger(forKey: Self.footprintMaterialKey))
        }
        guard storedSelection != nil else { return }
        // Retire the footprint choices after saving the overlay material so a reset stays reset.
        defaults.removeObject(forKey: Self.footprintMaterialKey)
        defaults.removeObject(forKey: Self.footprintKey)
    }

    func importSelection(from entries: [String: CodableDefault]) {
        if let rawValue = entries[key]?.int, let material = OverlayMaterial(rawValue: rawValue) {
            value = material
        } else if let enabled = entries[Self.footprintKey]?.bool {
            value = footprintSelection(blurred: enabled, rawMaterial: entries[Self.footprintMaterialKey]?.int)
        }
    }

    private func footprintSelection(blurred: Bool, rawMaterial: Int?) -> OverlayMaterial {
        guard blurred else { return .noBlur }
        return rawMaterial == OverlayMaterial.liquidGlass.rawValue ? .liquidGlass : .standard
    }

    func load(from codable: CodableDefault) {
        if let raw = codable.int, let material = OverlayMaterial(rawValue: raw) { value = material }
    }

    func toCodable() -> CodableDefault { CodableDefault(int: value.rawValue) }
}
