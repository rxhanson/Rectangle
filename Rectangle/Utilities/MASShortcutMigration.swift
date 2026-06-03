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
}
