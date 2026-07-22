/// StringExtension.swift

import Foundation

extension String {
    
    var localized: String {
        NSLocalizedString(self, tableName: "Main", comment: "")
    }
    
    func localized(key: String) -> String {
        NSLocalizedString(key, tableName: "Main", value: self, comment: "")
    }
    
}
