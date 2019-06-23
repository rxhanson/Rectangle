//
//  Defaults.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class Defaults {
    static let launchOnLogin = BoolDefault(key: "launchOnLogin")
    static let disabledApps = StringDefault(key: "disabledApps")
    static let hideMenuBarIcon = BoolDefault(key: "hideMenubarIcon")
    static let alternateDefaultShortcuts = BoolDefault(key: "alternateDefaultShortcuts") // switch to magnet defaults
    static let strictWindowActions = BoolDefault(key: "strictWindowActions") // Spectacle will resize to third screen sizes on successive triggers. Disable that by setting this to true
}

class BoolDefault {
    private let key: String
    private var initialized = false
    
    var enabled: Bool {
        didSet {
            if initialized {
                UserDefaults.standard.set(enabled, forKey: key)
            }
        }
    }
    
    init(key: String) {
        self.key = key
        enabled = UserDefaults.standard.bool(forKey: key)
        initialized = true
    }
}

class StringDefault {
    private let key: String
    private var initialized = false
    
    var value: String? {
        didSet {
            if initialized {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
    
    init(key: String) {
        self.key = key
        value = UserDefaults.standard.string(forKey: key)
        initialized = true
    }
}
