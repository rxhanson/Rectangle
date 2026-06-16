/// MASShortcutMigration.swift

import Foundation
import MASShortcut

class MASShortcutMigration {
    
    static func migrate() {
        
        guard let dataTransformer = ValueTransformer(forName: .secureUnarchiveFromDataTransformerName) else { return }
        
        guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }

        for action in WindowAction.active {
            
            if let dataValue = UserDefaults.standard.data(forKey: action.name) {
                if let shortcut = dataTransformer.transformedValue(dataValue) {
                    
                    let dictValue = dictTransformer.reverseTransformedValue(shortcut)
                    UserDefaults.standard.setValue(dictValue, forKey: action.name)
                }
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
