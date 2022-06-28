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
        guard let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        
        var shortcuts = [String: Shortcut]()
        for action in WindowAction.active {
            if let masShortcut =  MASShortcutBinder.shared()?.value(forKey: action.name) as? MASShortcut {
                shortcuts[action.name] = Shortcut(masShortcut: masShortcut)
            }
        }
        
        var codableDefaults = [String: CodableDefault]()
        for exportableDefault in Defaults.array {
            codableDefaults[exportableDefault.key] = exportableDefault.toCodable()
        }
                
        let config = Config(bundleId: "com.knollsoft.Rectangle",
                            version: version,
                            shortcuts: shortcuts,
                            defaults: codableDefaults)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if #available(macOS 10.13, *) {
            encoder.outputFormatting.update(with: .sortedKeys)
        }
        if let encodedJson = try? encoder.encode(config) {
            if let jsonString = String(data: encodedJson, encoding: .utf8) {
                return jsonString
            }
        }
        return nil
    }
    
    static func convert(jsonString: String) -> Config? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Config.self, from: jsonData)
    }
    
    static func load(fileUrl: URL) {
        guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
        
        guard let jsonString = try? String(contentsOf: fileUrl, encoding: .utf8),
              let config = convert(jsonString: jsonString) else { return }

        for availableDefault in Defaults.array {
            if let codedDefault = config.defaults[availableDefault.key] {
                availableDefault.load(from: codedDefault)
            }
        }
        
        for action in WindowAction.active {
            if let shortcut = config.shortcuts[action.name]?.toMASSHortcut() {
                let dictValue = dictTransformer.reverseTransformedValue(shortcut)
                UserDefaults.standard.setValue(dictValue, forKey: action.name)
            }
        }
        
        Notification.Name.configImported.post()
    }
}

struct Config: Codable {
    let bundleId: String
    let version: String
    let shortcuts: [String: Shortcut]
    let defaults: [String: CodableDefault]
}
