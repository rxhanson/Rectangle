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
    static let subsequentExecutionMode = SubsequentExecutionDefault()
    static let allowAnyShortcut = BoolDefault(key: "allowAnyShortcut")
    static let windowSnapping = OptionalBoolDefault(key: "windowSnapping")
    static let debug = BoolDefault(key: "debug")
    static let almostMaximizeRatio = FloatDefault(key: "almostMaximizeRatio")
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

class OptionalBoolDefault {
    private let key: String
    private var initialized = false
    
    var enabled: Bool? {
        didSet {
            if initialized {
                if enabled == true {
                    UserDefaults.standard.set(1, forKey: key)
                } else if enabled == false {
                    UserDefaults.standard.set(2, forKey: key)
                } else {
                    UserDefaults.standard.set(0, forKey: key)
                }
            }
        }
    }
    
    init(key: String) {
        self.key = key
        let intValue = UserDefaults.standard.integer(forKey: key)
        switch intValue {
        case 1: enabled = true
        case 2: enabled = false
        default: break
        }
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

class FloatDefault {
    private let key: String
    private var initialized = false
    
    var value: Float {
        didSet {
            if initialized {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
    
    init(key: String) {
        self.key = key
        value = UserDefaults.standard.float(forKey: key)
        initialized = true
    }
}
