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
    
}
