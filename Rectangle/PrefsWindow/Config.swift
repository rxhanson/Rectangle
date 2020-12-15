//
//  Config.swift
//  Rectangle
//
//  Created by Ryan Hanson on 12/15/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation
import MASShortcut

extension Defaults {
    static func encoded() -> String? {
        
        var shortcuts = [String: KeyboardShortcut]()
        for action in WindowAction.active {
            if let masShortcut =  MASShortcutBinder.shared()?.value(forKey: action.name) as? MASShortcut {
                shortcuts[action.name] = KeyboardShortcut(masShortcut: masShortcut)
            }
        }
        
        let config = Config(bundleId: "com.knollsoft.Rectangle", shortcuts: shortcuts)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let encodedJson = try? encoder.encode(config) {
            if let jsonString = String(data: encodedJson, encoding: .utf8) {
                print(jsonString)
                return jsonString
            }
        }
        return nil
    }
    
    static func from(string: String) -> Config? {
        let decoder = JSONDecoder()
        guard let jsonData = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(Config.self, from: jsonData)
    }
}

struct Config: Codable {
    let bundleId: String
    let shortcuts: [String: KeyboardShortcut]
}

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: Int
    let modifierFlags: UInt
    
    init(masShortcut: MASShortcut) {
        self.keyCode = masShortcut.keyCode
        self.modifierFlags = masShortcut.modifierFlags.rawValue
    }
    
    func toMASSHortcut() -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags))
    }
    
    func displayString() -> String {
        let masShortcut = toMASSHortcut()
        return masShortcut.modifierFlagsString + masShortcut.keyCodeString
    }
}
