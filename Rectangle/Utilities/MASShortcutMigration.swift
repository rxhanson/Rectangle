/// MASShortcutMigration.swift

import Foundation
import MASShortcut

enum MASShortcutMigration {

    static func migrate() {
        for action in WindowAction.active {
            if let dataValue = PreferencesStore.shared.data(forKey: action.name),
               let dataTransformer = ValueTransformer(forName: .secureUnarchiveFromDataTransformerName),
               let shortcut = dataTransformer.transformedValue(dataValue) as? MASShortcut {
                ShortcutStore.setShortcut(shortcut, forKey: action.name)
            }
        }
    }

    static func syncRenamedSideShortcutAliases(userDefaults: UserDefaults = .standard) {
        for action in WindowAction.active {
            guard let aliasName = action.aliasName,
                  let aliasValue = userDefaults.object(forKey: aliasName)
            else { continue }

            if let currentValue = userDefaults.object(forKey: action.name) as? NSObject,
               let aliasObject = aliasValue as? NSObject,
               currentValue.isEqual(aliasObject) {
                userDefaults.removeObject(forKey: aliasName)
                continue
            }

            userDefaults.set(aliasValue, forKey: action.name)
            userDefaults.removeObject(forKey: aliasName)
        }
    }
    
}
