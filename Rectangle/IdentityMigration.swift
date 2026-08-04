/// IdentityMigration.swift
///
/// One-time prefs migration from `com.perg593.divvy2` → `com.perg593.chiva`.
/// Must run before any `Defaults` / `CustomLayoutStore` access.

import Foundation

enum IdentityMigration {

    static let oldDomain = "com.perg593.divvy2"
    static let newDomain = "com.perg593.chiva"
    static let oldCustomLayoutsKey = "com.perg593.divvy2.customLayouts"
    static let newCustomLayoutsKey = "com.perg593.chiva.customLayouts"
    static let completedKey = "com.perg593.chiva.identityMigrationCompleted"

    /// Idempotent. Safe to call at every launch.
    static func runIfNeeded(
        standard: UserDefaults = .standard,
        oldDomain: String = IdentityMigration.oldDomain,
        newDomain: String = IdentityMigration.newDomain,
        oldCustomLayoutsKey: String = IdentityMigration.oldCustomLayoutsKey,
        newCustomLayoutsKey: String = IdentityMigration.newCustomLayoutsKey,
        completedKey: String = IdentityMigration.completedKey
    ) {
        if standard.bool(forKey: completedKey) { return }

        let old = standard.persistentDomain(forName: oldDomain) ?? [:]
        if old.isEmpty {
            standard.set(true, forKey: completedKey)
            return
        }

        var merged = old
        let existingNew = standard.persistentDomain(forName: newDomain) ?? [:]
        for (key, value) in existingNew {
            merged[key] = value
        }

        if merged[newCustomLayoutsKey] == nil, let legacy = merged[oldCustomLayoutsKey] {
            merged[newCustomLayoutsKey] = legacy
        }
        merged.removeValue(forKey: oldCustomLayoutsKey)
        merged.removeValue(forKey: completedKey)

        standard.setPersistentDomain(merged, forName: newDomain)
        standard.set(true, forKey: completedKey)
        standard.synchronize()
    }
}
