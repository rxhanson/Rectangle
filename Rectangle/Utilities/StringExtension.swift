//
//  StringExtension.swift
//  Rectangle
//
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

extension String {
    
    var localized: String {
        NSLocalizedString(self, tableName: "Main", comment: "")
    }
    
    func localized(key: String) -> String {
        NSLocalizedString(key, tableName: "Main", value: self, comment: "")
    }
    
}
