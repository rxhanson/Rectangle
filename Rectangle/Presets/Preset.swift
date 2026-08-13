/// Preset.swift

import Foundation

struct Preset: Codable {
    var id: UUID
    var name: String
    var version: String

    /// Shortcuts the preset assigns explicitly.
    var shortcuts: [String: Shortcut]

    /// Shortcuts the preset deliberately leaves unbound. MASShortcut stores these
    /// as an empty dictionary so they outrank the built-in default.
    var clearedShortcuts: [String]

    var defaults: [String: CodableDefault]
}

struct PresetStore: Codable {
    var presets: [Preset]
    var activePresetId: UUID?
}

/// What to write to a shortcut's UserDefaults key when a preset is applied.
enum ShortcutWrite: Equatable {
    /// Write this dictionary. An empty dictionary means "explicitly no shortcut".
    case set([String: Int])

    /// Remove the key so the shortcut registered by ShortcutManager applies again.
    case remove
}

enum PresetScope {

    /// Keys that describe the app itself rather than window behavior. They stay
    /// global: switching presets must not change how the app launches, updates or
    /// which apps are excluded.
    ///
    /// The preset store itself needs no entry here — it is not in `Defaults.array`,
    /// so it can never reach a snapshot.
    static let excludedDefaultKeys: Set<String> = [
        "launchOnLogin",
        "hideMenubarIcon",
        "relaunchOpensMenu",
        "SUEnableAutomaticChecks",
        "notifiedOfProblemApps",
        "showAllActionsInMenu",
        "showAdditionalSizesInMenu",
        "disabledApps",
        "fullIgnoreBundleIds",
        "doubleClickTitleBarIgnoredApps",
        "systemWideMouseDownApps",
        "todoMode",
        "todoApplication"
    ]

    static var defaults: [Default] {
        Defaults.array.filter { !excludedDefaultKeys.contains($0.key) }
    }

    static var shortcutKeys: [String] {
        WindowAction.active.map { $0.name } + TodoManager.defaultsKeys
    }
}

enum PresetSnapshot {

    /// Splits shortcut keys of a persistent defaults domain into the ones the user
    /// assigned and the ones the user cleared. Keys absent from the domain are in
    /// neither list: they fall through to the registration domain.
    ///
    /// The domain must come from `persistentDomain(forName:)`, not from
    /// `dictionary(forKey:)` — the latter resolves registered defaults and cannot
    /// tell an untouched shortcut from an assigned one.
    static func shortcutStates(in domain: [String: Any], keys: [String]) -> (assigned: [String: Shortcut], cleared: [String]) {
        var assigned = [String: Shortcut]()
        var cleared = [String]()

        for key in keys {
            guard let stored = domain[key] as? [String: Any] else { continue }

            if let keyCode = (stored["keyCode"] as? NSNumber)?.intValue,
               let modifierFlags = (stored["modifierFlags"] as? NSNumber)?.uintValue {
                assigned[key] = Shortcut(modifierFlags, keyCode)
            } else {
                cleared.append(key)
            }
        }

        return (assigned, cleared.sorted())
    }

    static func shortcutWrites(for preset: Preset, keys: [String]) -> [String: ShortcutWrite] {
        let cleared = Set(preset.clearedShortcuts)

        return keys.reduce(into: [String: ShortcutWrite]()) { writes, key in
            if let shortcut = preset.shortcuts[key] {
                writes[key] = .set(["keyCode": shortcut.keyCode,
                                    "modifierFlags": Int(shortcut.modifierFlags)])
            } else if cleared.contains(key) {
                writes[key] = .set([:])
            } else {
                writes[key] = .remove
            }
        }
    }

    static func defaultsSnapshot(from defaults: [Default]) -> [String: CodableDefault] {
        defaults.reduce(into: [String: CodableDefault]()) { snapshot, item in
            snapshot[item.key] = item.toCodable()
        }
    }

    static func builtInDefaultsSnapshot(from defaults: [Default]) -> [String: CodableDefault] {
        defaults.reduce(into: [String: CodableDefault]()) { snapshot, item in
            snapshot[item.key] = item.defaultCodable()
        }
    }
}

enum PresetMutation {

    /// Removes a preset from a store. Returns nil when the removal must be refused:
    /// the id is unknown, or it is the last remaining preset.
    ///
    /// `activates` is the preset that has to be applied to the live settings because
    /// it took over as the active one. It is nil when the active preset survives.
    static func removing(id: UUID, from store: PresetStore) -> (store: PresetStore, activates: Preset?)? {
        guard store.presets.count > 1,
              let index = store.presets.firstIndex(where: { $0.id == id })
        else { return nil }

        let activeIndex = store.presets.firstIndex { $0.id == store.activePresetId } ?? 0

        var presets = store.presets
        presets.remove(at: index)

        guard index == activeIndex else {
            return (PresetStore(presets: presets, activePresetId: store.activePresetId), nil)
        }

        let replacement = presets[0]
        return (PresetStore(presets: presets, activePresetId: replacement.id), replacement)
    }
}

enum PresetNaming {

    static func sanitized(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Appends " 2", " 3", … until the name no longer collides.
    static func unique(_ name: String, existing: [String]) -> String {
        guard existing.contains(name) else { return name }

        var suffix = 2
        while existing.contains("\(name) \(suffix)") {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }
}
