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
    
    static func loadFromSupportDir() {
        if let rectangleSupportURL = getSupportDir()?
            .appendingPathComponent("Rectangle", isDirectory: true) {
            
            let configURL = rectangleSupportURL.appendingPathComponent("RectangleConfig.json")
                        
            let exists = try? configURL.checkResourceIsReachable()
            if exists == true {
                load(fileUrl: configURL)
                do {
                    let newFilename = "RectangleConfig\(timestamp()).json"
                    
                    try FileManager.default.moveItem(atPath: configURL.path, toPath: rectangleSupportURL.appendingPathComponent(newFilename).path)
                } catch {
                    do {
                        try FileManager.default.removeItem(at: configURL)
                    } catch {
                        AlertUtil.oneButtonAlert(question: "Error after loading from Support Dir", text: "Unable to rename/remove RectangleConfig.json from \(rectangleSupportURL) after loading.")
                    }
                }
            }
        }
    }
    
    private static func getSupportDir() -> URL? {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths.isEmpty ? nil : paths[0]
    }
    
    private static func timestamp() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "y-MM-dd_H-mm-ss-SSSS"
        return formatter.string(from: date)
    }
}

struct Config: Codable {
    let bundleId: String
    let version: String
    let shortcuts: [String: Shortcut]
    let defaults: [String: CodableDefault]
}
