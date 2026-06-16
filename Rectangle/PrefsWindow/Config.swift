/// Config.swift

import Foundation
import MASShortcut

extension Defaults {
    static func encoded() -> String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        
        var shortcuts = [String: Shortcut]()
        for action in WindowAction.active {
            if let masShortcut = ShortcutCycle.shortcut(for: action) {
                shortcuts[action.name] = Shortcut(masShortcut: masShortcut)
            }
        }
        for defaultsKey in TodoManager.defaultsKeys {
            guard
                let shortcutDict = UserDefaults.standard.dictionary(forKey: defaultsKey),
                let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)),
                let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
            else {
                continue
            }
            shortcuts[defaultsKey] = Shortcut(masShortcut: shortcut)
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
        
        // Size cap: legitimate configs are ~tens of KB; refuse anything that
        // looks abusive (defense against OOM via a giant config file).
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileUrl.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 1_048_576 {
            return
        }
        
        guard let jsonString = try? String(contentsOf: fileUrl, encoding: .utf8),
              let config = convert(jsonString: jsonString) else { return }

        for availableDefault in Defaults.array {
            if let codedDefault = config.defaults[availableDefault.key] {
                availableDefault.load(from: codedDefault)
            }
        }
        
        for action in WindowAction.active {
            let importedShortcut = config.shortcuts[action.name] ?? action.aliasName.flatMap { config.shortcuts[$0] }
            if let shortcut = importedShortcut?.toMASSHortcut() {
                let dictValue = dictTransformer.reverseTransformedValue(shortcut)
                UserDefaults.standard.setValue(dictValue, forKey: action.name)
            }
        }
        for defaultsKey in TodoManager.defaultsKeys {
            if let shortcut = config.shortcuts[defaultsKey]?.toMASSHortcut() {
                let dictValue = dictTransformer.reverseTransformedValue(shortcut)
                UserDefaults.standard.setValue(dictValue, forKey: defaultsKey)
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
                // Defense-in-depth: any process running as this user can drop
                // a RectangleConfig.json in Application Support and have it
                // silently applied on next launch, overwriting shortcuts and
                // defaults. Require the user to confirm before loading.
                //
                // We also refuse symlinks (could redirect reads elsewhere) and
                // any file with world-write permission (suggests tampering).
                let path = configURL.path
                let fm = FileManager.default
                var isSafe = true
                
                if let attrs = try? fm.attributesOfItem(atPath: path) {
                    if (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
                        isSafe = false
                    }
                    if let perms = attrs[.posixPermissions] as? NSNumber,
                       (perms.intValue & 0o002) != 0 {
                        isSafe = false
                    }
                }
                
                guard isSafe else {
                    AlertUtil.oneButtonAlert(
                        question: "Refused to load RectangleConfig.json",
                        text: "The configuration file at \(path) is a symlink or world-writable. Rectangle has refused to load it. Remove the file or fix its permissions and try again."
                    )
                    try? fm.removeItem(at: configURL)
                    return
                }
                
                let response = AlertUtil.twoButtonAlert(
                    question: "Apply Rectangle configuration?",
                    text: "A configuration file was found at \(path). Applying it will overwrite your current Rectangle shortcuts and preferences. Apply now?",
                    confirmText: "Apply",
                    cancelText: "Discard"
                )
                guard response == .alertFirstButtonReturn else {
                    try? fm.removeItem(at: configURL)
                    return
                }
                
                load(fileUrl: configURL)
                do {
                    let newFilename = "RectangleConfig\(timestamp()).json"
                    
                    try fm.moveItem(atPath: configURL.path, toPath: rectangleSupportURL.appendingPathComponent(newFilename).path)
                } catch {
                    do {
                        try fm.removeItem(at: configURL)
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
