/// CustomLayoutStore.swift
///
/// Persistence for custom layouts: a versioned JSON envelope stored under our OWN
/// UserDefaults key `com.perg593.chiva.customLayouts`. Independent of Rectangle's
/// own config import/export. Posts `.customLayoutsChanged` on every successful
/// mutation so the (M2) shortcut manager can re-register. See
/// docs/2026-06-23-Design-M1-Model-Store.md.

import Foundation

extension Notification.Name {
    static let customLayoutsChanged = Notification.Name("com.perg593.chiva.customLayoutsChanged")
}

enum CustomLayoutImportError: Error, Equatable {
    case decode
    case unsupportedSchema
    case invalidLayout
    case duplicateId
}

/// The on-disk envelope. `schemaVersion` enables whole-file migration.
struct CustomLayoutsEnvelope: Codable {
    var schemaVersion: Int
    var layouts: [CustomLayout]
}

final class CustomLayoutStore {

    static let defaultsKey = "com.perg593.chiva.customLayouts"
    static let currentSchemaVersion = 1

    private let defaults: UserDefaults
    private(set) var layouts: [CustomLayout] = []

    /// True when the stored envelope's schemaVersion > currentSchemaVersion (a newer
    /// app wrote it). In this state `layouts` is read-only and all mutators no-op
    /// WITHOUT touching defaults, so future data is never downgraded. Recovery: a
    /// successful `importJSON` (explicit replace) or a future migration.
    private(set) var isReadOnlyFutureSchema = false

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        loadFromDefaults()
    }

    // MARK: - Read

    func layout(id: UUID) -> CustomLayout? { layouts.first { $0.id == id } }

    // MARK: - Mutators (return false when read-only / invalid / absent)

    @discardableResult
    func add(_ layout: CustomLayout) -> Bool {
        assertMain()
        guard !isReadOnlyFutureSchema, layout.rect.isValid,
              !layouts.contains(where: { $0.id == layout.id }) else { return false }
        layouts.append(layout)
        persistAndNotify()
        return true
    }

    @discardableResult
    func update(_ layout: CustomLayout) -> Bool {
        assertMain()
        guard !isReadOnlyFutureSchema, layout.rect.isValid,
              let idx = layouts.firstIndex(where: { $0.id == layout.id }) else { return false }
        layouts[idx] = layout
        persistAndNotify()
        return true
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        assertMain()
        guard !isReadOnlyFutureSchema,
              let idx = layouts.firstIndex(where: { $0.id == id }) else { return false }
        layouts.remove(at: idx)
        persistAndNotify()
        return true
    }

    @discardableResult
    func setHotkey(_ hotkey: HotkeyData?, for id: UUID) -> Bool {
        assertMain()
        guard !isReadOnlyFutureSchema,
              let idx = layouts.firstIndex(where: { $0.id == id }) else { return false }
        layouts[idx].hotkey = hotkey
        persistAndNotify()
        return true
    }

    // MARK: - Export / import

    func exportJSON() -> Data {
        let env = CustomLayoutsEnvelope(schemaVersion: Self.currentSchemaVersion, layouts: layouts)
        return (try? Self.encoder().encode(env)) ?? Data()
    }

    /// STRICT, atomic, all-or-nothing replace. On ANY error, in-memory state AND
    /// defaults are left exactly as they were.
    @discardableResult
    func importJSON(_ data: Data) -> Result<Int, CustomLayoutImportError> {
        assertMain()
        guard let env = try? JSONDecoder().decode(CustomLayoutsEnvelope.self, from: data) else {
            return .failure(.decode)
        }
        guard env.schemaVersion <= Self.currentSchemaVersion else { return .failure(.unsupportedSchema) }
        guard env.layouts.allSatisfy({ $0.rect.isValid }) else { return .failure(.invalidLayout) }
        let ids = env.layouts.map { $0.id }
        guard Set(ids).count == ids.count else { return .failure(.duplicateId) }
        // Commit atomically.
        layouts = env.layouts
        isReadOnlyFutureSchema = false   // user explicitly chose this content
        persistAndNotify()
        return .success(layouts.count)
    }

    func reload() { loadFromDefaults() }

    // MARK: - Private

    /// Tolerant load. HEADER-FIRST: decode only `schemaVersion` before touching
    /// `layouts`, so the future-schema read-only gate holds even if the future
    /// `layouts` payload is undecodable by this version.
    private func loadFromDefaults() {
        isReadOnlyFutureSchema = false
        guard let data = defaults.data(forKey: Self.defaultsKey) else { layouts = []; return }

        struct EnvelopeHeader: Decodable { let schemaVersion: Int }
        guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: data) else {
            // Truly corrupt/foreign JSON: keep empty in-memory, do NOT overwrite the bytes.
            layouts = []
            return
        }

        if header.schemaVersion > Self.currentSchemaVersion {
            // Newer app wrote this — read-only, leave defaults untouched.
            isReadOnlyFutureSchema = true
            if let env = try? JSONDecoder().decode(CustomLayoutsEnvelope.self, from: data) {
                layouts = env.layouts.filter { $0.rect.isValid }
            } else {
                layouts = []   // future layouts shape undecodable here; still read-only
            }
            return
        }

        guard let env = try? JSONDecoder().decode(CustomLayoutsEnvelope.self, from: data) else {
            // Header decoded but full envelope didn't: keep empty, don't overwrite.
            layouts = []
            return
        }
        // Known version <= current (v1 = identity migration). Tolerant: drop invalid
        // rects and duplicate ids, keep the valid remainder; raw bytes stay until a
        // successful mutation rewrites them.
        var seen = Set<UUID>()
        layouts = env.layouts.filter { l in
            guard l.rect.isValid, !seen.contains(l.id) else { return false }
            seen.insert(l.id)
            return true
        }
    }

    private func persistAndNotify() {
        let env = CustomLayoutsEnvelope(schemaVersion: Self.currentSchemaVersion, layouts: layouts)
        if let data = try? Self.encoder().encode(env) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: .customLayoutsChanged, object: nil)
    }

    private static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    private func assertMain() {
        #if DEBUG
        assert(Thread.isMainThread, "CustomLayoutStore must be mutated on the main thread")
        #endif
    }
}
