/// PresetManager.swift

import Cocoa

/// Owns the list of presets and applies them.
///
/// The active preset mirrors the live settings: everything the user changes in
/// the settings window is written straight to UserDefaults, and the stored copy
/// of the active preset is refreshed whenever something is about to read it.
/// That removes the need for a save button, a dirty flag, or change observers.
class PresetManager {

    private let userDefaults: UserDefaults
    private let domainName: String

    init(userDefaults: UserDefaults = .standard,
         domainName: String = Bundle.main.bundleIdentifier ?? "com.knollsoft.Rectangle") {
        self.userDefaults = userDefaults
        self.domainName = domainName
        seedIfEmpty()
    }

    var presets: [Preset] { store.presets }

    var activePreset: Preset? {
        let current = store
        guard let index = activeIndex(in: current) else { return nil }
        return current.presets[index]
    }

    /// Writes the live configuration into the active preset.
    func syncActivePreset() {
        var current = store
        guard let index = activeIndex(in: current) else { return }

        let existing = current.presets[index]
        current.presets[index] = capture(named: existing.name, id: existing.id)
        store = current
    }

    func activate(_ id: UUID) {
        syncActivePreset()

        guard let target = store.presets.first(where: { $0.id == id }) else { return }
        apply(target)

        var current = store
        current.activePresetId = id
        store = current
    }

    @discardableResult
    func createFromDefaults(named name: String) -> Preset {
        syncActivePreset()

        var current = store
        let preset = Preset(id: UUID(),
                            name: PresetNaming.unique(name, existing: current.presets.map { $0.name }),
                            version: bundleVersion,
                            shortcuts: [:],
                            clearedShortcuts: [],
                            defaults: PresetSnapshot.builtInDefaultsSnapshot(from: PresetScope.defaults))
        current.presets.append(preset)
        store = current
        return preset
    }

    @discardableResult
    func duplicateActivePreset(named name: String) -> Preset? {
        syncActivePreset()

        var current = store
        guard let index = activeIndex(in: current) else { return nil }

        var copy = current.presets[index]
        copy.id = UUID()
        copy.name = PresetNaming.unique(name, existing: current.presets.map { $0.name })
        current.presets.append(copy)
        store = current
        return copy
    }

    func rename(_ id: UUID, to name: String) {
        guard let sanitized = PresetNaming.sanitized(name) else { return }

        var current = store
        guard let index = current.presets.firstIndex(where: { $0.id == id }) else { return }
        current.presets[index].name = sanitized
        store = current
    }

    /// Removes a preset. The last remaining preset cannot be removed. If the
    /// active preset is removed, the first remaining one is applied.
    ///
    /// There is deliberately no syncActivePreset() here: the preset that mirrored
    /// the live settings is the one being thrown away.
    func delete(_ id: UUID) {
        guard let result = PresetMutation.removing(id: id, from: store) else { return }

        store = result.store

        if let replacement = result.activates {
            apply(replacement)
        }
    }

    private var store: PresetStore {
        get { Defaults.presets.typedValue ?? PresetStore(presets: [], activePresetId: nil) }
        set { Defaults.presets.typedValue = newValue }
    }

    private var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    private func activeIndex(in store: PresetStore) -> Int? {
        if let id = store.activePresetId,
           let index = store.presets.firstIndex(where: { $0.id == id }) {
            return index
        }
        return store.presets.isEmpty ? nil : 0
    }

    private func seedIfEmpty() {
        guard store.presets.isEmpty else { return }

        let name = NSLocalizedString("Default", tableName: "Main", value: "", comment: "")
        let preset = capture(named: name)
        store = PresetStore(presets: [preset], activePresetId: preset.id)
    }

    private func capture(named name: String, id: UUID = UUID()) -> Preset {
        let domain = userDefaults.persistentDomain(forName: domainName) ?? [:]
        let states = PresetSnapshot.shortcutStates(in: domain, keys: PresetScope.shortcutKeys)

        return Preset(id: id,
                      name: name,
                      version: bundleVersion,
                      shortcuts: states.assigned,
                      clearedShortcuts: states.cleared,
                      defaults: PresetSnapshot.defaultsSnapshot(from: PresetScope.defaults))
    }

    private func apply(_ preset: Preset) {
        Notification.Name.windowSnapping.post(object: false)

        // Settings first: alternateDefaultShortcuts decides which built-in shortcut
        // set an unset key falls back to, and it has to be current before
        // ShortcutManager re-registers its defaults.
        Defaults.apply(defaults: preset.defaults)

        for (key, write) in PresetSnapshot.shortcutWrites(for: preset, keys: PresetScope.shortcutKeys) {
            switch write {
            case .set(let dictionary): userDefaults.set(dictionary, forKey: key)
            case .remove: userDefaults.removeObject(forKey: key)
            }
        }

        Notification.Name.configImported.post()
        Notification.Name.windowSnapping.post(object: true)
    }
}
