//
//  Defaults.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/14/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

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
    static let screenEdgeGapsOnMainScreenOnly = BoolDefault(key: "screenEdgeGapsOnMainScreenOnly")
    static let lastVersion = StringDefault(key: "lastVersion")
    static let showAllActionsInMenu = OptionalBoolDefault(key: "showAllActionsInMenu")
    static var SUHasLaunchedBefore: Bool { UserDefaults.standard.bool(forKey: "SUHasLaunchedBefore") }
    static let footprintAlpha = FloatDefault(key: "footprintAlpha", defaultValue: 0.3)
    static let footprintBorderWidth = FloatDefault(key: "footprintBorderWidth", defaultValue: 2)
    static let footprintFade = OptionalBoolDefault(key: "footprintFade")
    static let footprintColor = JSONDefault<CodableColor>(key: "footprintColor")
    static let SUEnableAutomaticChecks = BoolDefault(key: "SUEnableAutomaticChecks")
    static let todo = OptionalBoolDefault(key: "todo")
    static let todoMode = BoolDefault(key: "todoMode")
    static let todoApplication = StringDefault(key: "todoApplication")
    static let todoSidebarWidth = FloatDefault(key: "todoSidebarWidth", defaultValue: 400)
    static let snapModifiers = IntDefault(key: "snapModifiers")
    static let attemptMatchOnNextPrevDisplay = OptionalBoolDefault(key: "attemptMatchOnNextPrevDisplay")
    static let altThirdCycle = OptionalBoolDefault(key: "altThirdCycle")
    static let centerHalfCycles = OptionalBoolDefault(key: "centerHalfCycles")
    static let fullIgnoreBundleIds = JSONDefault<[String]>(key: "fullIgnoreBundleIds")
    static let notifiedOfProblemApps = BoolDefault(key: "notifiedOfProblemApps")
    static let specifiedHeight = FloatDefault(key: "specifiedHeight", defaultValue: 1050)
    static let specifiedWidth = FloatDefault(key: "specifiedWidth", defaultValue: 1680)
    static let moveCursorAcrossDisplays = OptionalBoolDefault(key: "moveCursorAcrossDisplays")
    static let moveCursor = OptionalBoolDefault(key: "moveCursor")
    static let autoMaximize = OptionalBoolDefault(key: "autoMaximize")
    static let applyGapsToMaximize = OptionalBoolDefault(key: "applyGapsToMaximize")
    static let applyGapsToMaximizeHeight = OptionalBoolDefault(key: "applyGapsToMaximizeHeight")
    static let cornerSnapAreaSize = FloatDefault(key: "cornerSnapAreaSize", defaultValue: 20)
    static let shortEdgeSnapAreaSize = FloatDefault(key: "shortEdgeSnapAreaSize", defaultValue: 145)
    static let cascadeAllDeltaSize = FloatDefault(key: "cascadeAllDeltaSize", defaultValue: 30)
    static let sixthsSnapArea = OptionalBoolDefault(key: "sixthsSnapArea")
    static let eightsSnapArea = OptionalBoolDefault(key: "eightsSnapArea")
    static let stageSize = FloatDefault(key: "stageSize", defaultValue: 190)

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
        screenEdgeGapsOnMainScreenOnly,
        showAllActionsInMenu,
        footprintAlpha,
        footprintBorderWidth,
        footprintFade,
        footprintColor,
        SUEnableAutomaticChecks,
        todo,
        todoMode,
        todoApplication,
        todoSidebarWidth,
        snapModifiers,
        attemptMatchOnNextPrevDisplay,
        altThirdCycle,
        centerHalfCycles,
        fullIgnoreBundleIds,
        notifiedOfProblemApps,
        specifiedHeight,
        specifiedWidth,
        moveCursorAcrossDisplays,
        moveCursor,
        autoMaximize,
        applyGapsToMaximize,
        applyGapsToMaximizeHeight,
        cornerSnapAreaSize,
        shortEdgeSnapAreaSize,
        cascadeAllDeltaSize,
        sixthsSnapArea,
        stageSize
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
    
    var cgFloat: CGFloat { CGFloat(value) }

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

class JSONDefault<T: Codable>: StringDefault {
    
    private var typeInitialized = false
    
    var typedValue: T? {
        didSet {
            if typeInitialized {
                saveToJSON(typedValue)
            }
        }
    }
    
    override init(key: String) {
        super.init(key: key)
        loadFromJSON()
        typeInitialized = true
    }
    
    private func loadFromJSON() {
        guard let jsonString = value else { return }
        let decoder = JSONDecoder()
        guard let jsonData = jsonString.data(using: .utf8) else { return }
        typedValue = try? decoder.decode(T.self, from: jsonData)
    }
    
    private func saveToJSON(_ obj: T?) {
        let encoder = JSONEncoder()
        
        if let jsonData = try? encoder.encode(obj) {
            let jsonString = String(data: jsonData, encoding: .utf8)
            if jsonString != value {
                value = jsonString
            }
        }
    }
}

struct CodableColor : Codable {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat? = 1.0

    var nsColor : NSColor {
        return NSColor(red: red, green: green, blue: blue, alpha: alpha ?? 1.0)
    }

    init(nsColor: NSColor) {
        self.red = nsColor.redComponent
        self.green = nsColor.greenComponent
        self.blue = nsColor.blueComponent
        self.alpha = nsColor.alphaComponent
    }
}
