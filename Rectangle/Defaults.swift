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
    static let almostMaximizeHeight = FloatDefault(key: "almostMaximizeHeight")
    static let almostMaximizeWidth = FloatDefault(key: "almostMaximizeWidth")
    static let gapSize = FloatDefault(key: "gapSize")
    static let snapEdgeMarginTop = FloatDefault(key: "snapEdgeMarginTop", defaultValue: 5)
    static let snapEdgeMarginBottom = FloatDefault(key: "snapEdgeMarginBottom", defaultValue: 5)
    static let snapEdgeMarginLeft = FloatDefault(key: "snapEdgeMarginLeft", defaultValue: 5)
    static let snapEdgeMarginRight = FloatDefault(key: "snapEdgeMarginRight", defaultValue: 5)
    static let centeredDirectionalMove = OptionalBoolDefault(key: "centeredDirectionalMove")
    static let resizeOnDirectionalMove = BoolDefault(key: "resizeOnDirectionalMove")
    static let ignoredSnapAreas = IntDefault(key: "ignoredSnapAreas")
    static let traverseSingleScreen = OptionalBoolDefault(key: "traverseSingleScreen")
    static let minimumWindowWidth = FloatDefault(key: "minimumWindowWidth")
    static let minimumWindowHeight = FloatDefault(key: "minimumWindowHeight")
    static let sizeOffset = FloatDefault(key: "sizeOffset")
    static let unsnapRestore = OptionalBoolDefault(key: "unsnapRestore")
    static let curtainChangeSize = OptionalBoolDefault(key: "curtainChangeSize")
    static let relaunchOpensMenu = BoolDefault(key: "relaunchOpensMenu")
    static let obtainWindowOnClick = OptionalBoolDefault(key: "obtainWindowOnClick")
    static let screenEdgeGapTop = FloatDefault(key: "screenEdgeGapTop", defaultValue: 0)
    static let screenEdgeGapBottom = FloatDefault(key: "screenEdgeGapBottom", defaultValue: 0)
    static let screenEdgeGapLeft = FloatDefault(key: "screenEdgeGapLeft", defaultValue: 0)
    static let screenEdgeGapRight = FloatDefault(key: "screenEdgeGapRight", defaultValue: 0)
    static let lastVersion = StringDefault(key: "lastVersion")
    static let showAllActionsInMenu = OptionalBoolDefault(key: "showAllActionsInMenu")
    static var SUHasLaunchedBefore: Bool { UserDefaults.standard.bool(forKey: "SUHasLaunchedBefore") }
    static let footprintAlpha = FloatDefault(key: "footprintAlpha", defaultValue: 0.3)
    static let footprintBorderWidth = FloatDefault(key: "footprintBorderWidth", defaultValue: 2)
    static let footprintFade = OptionalBoolDefault(key: "footprintFade")
    static let SUEnableAutomaticChecks = BoolDefault(key: "SUEnableAutomaticChecks")
    static let showExportImport = BoolDefault(key: "showExportImport")
    static let todoMode = BoolDefault(key: "todoMode")
    
    static var array: [Default] = [
        launchOnLogin,
        disabledApps,
        hideMenuBarIcon,
        alternateDefaultShortcuts,
        subsequentExecutionMode,
        allowAnyShortcut,
        windowSnapping,
        almostMaximizeHeight,
        almostMaximizeWidth,
        gapSize,
        snapEdgeMarginTop,
        snapEdgeMarginBottom,
        snapEdgeMarginLeft,
        snapEdgeMarginRight,
        centeredDirectionalMove,
        resizeOnDirectionalMove,
        ignoredSnapAreas,
        traverseSingleScreen,
        minimumWindowWidth,
        minimumWindowHeight,
        sizeOffset,
        unsnapRestore,
        curtainChangeSize,
        relaunchOpensMenu,
        obtainWindowOnClick,
        screenEdgeGapTop,
        screenEdgeGapBottom,
        screenEdgeGapLeft,
        screenEdgeGapRight,
        showAllActionsInMenu,
        footprintAlpha,
        footprintBorderWidth,
        footprintFade,
        SUEnableAutomaticChecks
    ]
}

struct CodableDefault: Codable {
    let bool: Bool?
    let int: Int?
    let float: Float?
    let string: String?
    
    init(bool: Bool? = nil, int: Int? = nil, float: Float? = nil, string: String? = nil) {
        self.bool = bool
        self.int = int
        self.float = float
        self.string = string
    }
}

protocol Default {
    var key: String { get }
    func load(from codable: CodableDefault)
    func toCodable() -> CodableDefault
}

class BoolDefault: Default {
    public private(set) var key: String
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
    
    func load(from codable: CodableDefault) {
        if let value = codable.bool {
            self.enabled = value
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(bool: enabled)
    }
}

class OptionalBoolDefault: Default {
    public private(set) var key: String
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
    
    var userDisabled: Bool { enabled == false }
    var userEnabled: Bool { enabled == true }
    
    init(key: String) {
        self.key = key
        let intValue = UserDefaults.standard.integer(forKey: key)
        set(using: intValue)
        initialized = true
    }
    
    private func set(using intValue: Int) {
        switch intValue {
        case 0: enabled = nil
        case 1: enabled = true
        case 2: enabled = false
        default: break
        }
    }
    
    func load(from codable: CodableDefault) {
        if let value = codable.int {
            set(using: value)
        }
    }
    
    func toCodable() -> CodableDefault {
        guard let enabled = enabled else { return CodableDefault(int: 0)}
        let intValue = enabled ? 1 : 2
        return CodableDefault(int: intValue)
    }
}

class StringDefault: Default {
    public private(set) var key: String
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
    
    func load(from codable: CodableDefault) {
        value = codable.string
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(string: value)
    }
}

class FloatDefault: Default {
    public private(set) var key: String
    private var initialized = false
    
    var value: Float {
        didSet {
            if initialized {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
    
    init(key: String, defaultValue: Float = 0) {
        self.key = key
        value = UserDefaults.standard.float(forKey: key)
        if(defaultValue != 0 && value == 0) {
            value = defaultValue
        }
        initialized = true
    }
    
    func load(from codable: CodableDefault) {
        if let float = codable.float {
            value = float
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(float: value)
    }
}

class IntDefault: Default {
    public private(set) var key: String
    private var initialized = false
    
    var value: Int {
        didSet {
            if initialized {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
    
    init(key: String) {
        self.key = key
        value = UserDefaults.standard.integer(forKey: key)
        initialized = true
    }
    
    func load(from codable: CodableDefault) {
        if let int = codable.int {
            value = int
        }
    }
    
    func toCodable() -> CodableDefault {
        return CodableDefault(int: value)
    }
}
