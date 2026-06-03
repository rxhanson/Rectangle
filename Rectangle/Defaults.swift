/// Defaults.swift

import Cocoa
import SwiftPList
import MASShortcut

final class PreferencesStore {
    static let shared = PreferencesStore()

    fileprivate static let disabledShortcutMarker = "__RECTANGLE_SHORTCUT_DISABLED__"

    private let fileURL: URL
    private var format: PListFormat = .binary
    private var storage: PListDictionary = [:]

    init(fileURL: URL = PreferencesStore.defaultFileURL()) {
        self.fileURL = fileURL
        reloadFromDisk()
    }

    static func defaultFileURL(bundle: Bundle = .main,
                               fileManager: FileManager = .default) -> URL {
        let bundleId = bundle.bundleIdentifier ?? "com.knollsoft.Rectangle"
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return libraryURL
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(bundleId).plist")
    }

    func reloadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storage = [:]
            format = .binary
            return
        }

        do {
            let plist = try DictionaryPList(url: fileURL)
            storage = plist.storage
            format = plist.format
        } catch {
            storage = [:]
            format = .binary
            Logger.log("Unable to load preferences from \(fileURL.path): \(error.localizedDescription)")
        }
    }

    func objectExists(forKey key: String) -> Bool {
        storage[any: key] != nil
    }

    func plistValue(forKey key: String) -> PListValue? {
        storage[any: key]
    }

    func foundationObject(forKey key: String) -> Any? {
        guard let value = storage[any: key] else { return nil }
        return Self.foundationObject(from: value)
    }

    func bool(forKey key: String) -> Bool {
        storage[bool: key] ?? false
    }

    func int(forKey key: String) -> Int {
        storage[int: key] ?? storage[double: key].map(Int.init) ?? 0
    }

    func float(forKey key: String) -> Float {
        storage[double: key].map(Float.init) ?? storage[int: key].map(Float.init) ?? 0
    }

    func string(forKey key: String) -> String? {
        storage[string: key]
    }

    func data(forKey key: String) -> Data? {
        storage[data: key]
    }

    func set(_ value: Bool, forKey key: String) {
        storage[bool: key] = value
        persist()
    }

    func set(_ value: Int, forKey key: String) {
        storage[int: key] = value
        persist()
    }

    func set(_ value: Float, forKey key: String) {
        storage[double: key] = Double(value)
        persist()
    }

    func set(_ value: String?, forKey key: String) {
        storage[string: key] = value
        persist()
    }

    func set(_ value: Data?, forKey key: String) {
        storage[data: key] = value
        persist()
    }

    func set(any value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }

        guard let plistValue = Self.plistValue(from: value) else {
            Logger.log("Unable to save unsupported preference value for \(key)")
            return
        }

        storage[key] = plistValue
        persist()
    }

    func removeObject(forKey key: String) {
        storage[key] = nil
        persist()
    }

    private func persist() {
        do {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let type = attrs[.type] as? FileAttributeType,
               type == .typeSymbolicLink {
                return
            }

            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL,
                                                   withIntermediateDirectories: true,
                                                   attributes: nil)

            let plist = DictionaryPList(root: storage, format: format)
            try plist.save(toFileAtURL: fileURL, format: format)
        } catch {
            Logger.log("Unable to save preferences to \(fileURL.path): \(error.localizedDescription)")
        }
    }

    fileprivate static func foundationObject(from value: PListValue) -> Any {
        switch value {
        case let string as String:     string
        case let int as Int:           int
        case let double as Double:     double
        case let bool as Bool:         bool
        case let date as Date:         date
        case let data as Data:         data
        case let dictionary as PListDictionary:
            dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = foundationObject(from: entry.value)
            }
        case let array as PListArray:
            array.map { foundationObject(from: $0) }
        default:
            value
        }
    }

    private static func plistValue(from value: Any) -> PListValue? {
        // NSNumber boxes Bools as well as numbers; check for Bool first before
        // hitting the numeric cases below.
        if let boolNumber = value as? NSNumber, CFGetTypeID(boolNumber) == CFBooleanGetTypeID() {
            return boolNumber.boolValue
        }

        switch value {
        case let string as String:  return string
        case let int as Int:        return int
        case let float as Float:    return Double(float)
        case let double as Double:  return double
        case let bool as Bool:      return bool
        case let date as Date:      return date
        case let data as Data:      return data
        case let dictionary as [String: Any]:
            var plistDictionary: PListDictionary = [:]
            for (key, nestedValue) in dictionary {
                guard let plistValue = plistValue(from: nestedValue) else { return nil }
                plistDictionary[key] = plistValue
            }
            return plistDictionary
        case let array as [Any]:
            var plistArray: PListArray = []
            for nestedValue in array {
                guard let plistValue = plistValue(from: nestedValue) else { return nil }
                plistArray.append(plistValue)
            }
            return plistArray
        case let number as NSNumber:
            // Fall back for numeric NSNumbers that didn't match Swift Int/Double above.
            let doubleValue = number.doubleValue
            return floor(doubleValue) == doubleValue ? number.intValue : doubleValue
        default:
            return nil
        }
    }
}

enum ShortcutStore {
    private static var dictTransformer: ValueTransformer? {
        ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))
    }

    private static var dataTransformer: ValueTransformer? {
        ValueTransformer(forName: .secureUnarchiveFromDataTransformerName)
    }

    static func shortcut(for action: WindowAction) -> MASShortcut? {
        shortcut(forKey: action.name, fallback: defaultShortcut(for: action))
    }

    static func shortcut(forKey key: String, fallback: MASShortcut? = nil) -> MASShortcut? {
        if PreferencesStore.shared.string(forKey: key) == PreferencesStore.disabledShortcutMarker {
            return nil
        }

        if let rawShortcut = PreferencesStore.shared.foundationObject(forKey: key) as? [String: Any],
           let shortcut = dictTransformer?.transformedValue(rawShortcut) as? MASShortcut {
            return shortcut
        }

        if let dataValue = PreferencesStore.shared.data(forKey: key),
           let shortcut = dataTransformer?.transformedValue(dataValue) as? MASShortcut {
            setShortcut(shortcut, forKey: key)
            return shortcut
        }

        return fallback
    }

    static func setShortcut(_ shortcut: MASShortcut?, forKey key: String) {
        if let shortcut,
           let rawShortcut = dictTransformer?.reverseTransformedValue(shortcut) {
            PreferencesStore.shared.set(any: rawShortcut, forKey: key)
        } else {
            // A sentinel string marks an explicitly-cleared shortcut so that the
            // per-action default is NOT restored on next launch.
            PreferencesStore.shared.set(PreferencesStore.disabledShortcutMarker, forKey: key)
        }
    }

    static func resetShortcut(forKey key: String) {
        PreferencesStore.shared.removeObject(forKey: key)
    }

    static func defaultShortcut(for action: WindowAction) -> MASShortcut? {
        let shortcut = Defaults.alternateDefaultShortcuts.enabled
            ? action.alternateDefault
            : action.spectacleDefault
        guard let shortcut else { return nil }
        return MASShortcut(keyCode: shortcut.keyCode,
                           modifierFlags: NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags))
    }
}

class Defaults {
    static let launchOnLogin = BoolDefault(key: "launchOnLogin")
    static let disabledApps = StringDefault(key: "disabledApps")
    static let hideMenuBarIcon = BoolDefault(key: "hideMenubarIcon")
    static let alternateDefaultShortcuts = BoolDefault(key: "alternateDefaultShortcuts") // switch to magnet defaults
    static let subsequentExecutionMode = SubsequentExecutionDefault()
    static let selectedCycleSizes = CycleSizesDefault()
    static let cycleSizesIsChanged = BoolDefault(key: "cycleSizesIsChanged")
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
    static let moveFixedSizeToEdge = OptionalBoolDefault(key: "moveFixedSizeToEdge")
    static let ignoredSnapAreas = IntDefault(key: "ignoredSnapAreas")
    static let traverseSingleScreen = OptionalBoolDefault(key: "traverseSingleScreen")
    static let useCursorScreenDetection = BoolDefault(key: "useCursorScreenDetection")
    static let minimumWindowWidth = FloatDefault(key: "minimumWindowWidth")
    static let minimumWindowHeight = FloatDefault(key: "minimumWindowHeight")
    static let sizeOffset = FloatDefault(key: "sizeOffset")
    static let widthStepSize = FloatDefault(key: "widthStepSize", defaultValue: 30)
    static let unsnapRestore = OptionalBoolDefault(key: "unsnapRestore")
    static let curtainChangeSize = OptionalBoolDefault(key: "curtainChangeSize")
    static let relaunchOpensMenu = BoolDefault(key: "relaunchOpensMenu")
    static let obtainWindowOnClick = OptionalBoolDefault(key: "obtainWindowOnClick")
    static let screenEdgeGapTop = FloatDefault(key: "screenEdgeGapTop", defaultValue: 0)
    static let screenEdgeGapBottom = FloatDefault(key: "screenEdgeGapBottom", defaultValue: 0)
    static let screenEdgeGapLeft = FloatDefault(key: "screenEdgeGapLeft", defaultValue: 0)
    static let screenEdgeGapRight = FloatDefault(key: "screenEdgeGapRight", defaultValue: 0)
    static let screenEdgeGapsOnMainScreenOnly = BoolDefault(key: "screenEdgeGapsOnMainScreenOnly")
    static let screenEdgeGapTopNotch = FloatDefault(key: "screenEdgeGapTopNotch", defaultValue: 0)
    static let lastVersion = StringDefault(key: "lastVersion")
    static let installVersion = StringDefault(key: "installVersion")
    static let showAllActionsInMenu = OptionalBoolDefault(key: "showAllActionsInMenu")
    static let showAdditionalSizesInMenu = OptionalBoolDefault(key: "showAdditionalSizesInMenu")
    // Sparkle owns this key; we read it directly rather than wrapping it in a BoolDefault.
    static var SUHasLaunchedBefore: Bool { PreferencesStore.shared.bool(forKey: "SUHasLaunchedBefore") }
    static let footprintAlpha = FloatDefault(key: "footprintAlpha", defaultValue: 0.3)
    static let footprintBorderWidth = FloatDefault(key: "footprintBorderWidth", defaultValue: 2)
    static let footprintFade = OptionalBoolDefault(key: "footprintFade")
    static let footprintColor = JSONDefault<CodableColor>(key: "footprintColor")
    static let SUEnableAutomaticChecks = BoolDefault(key: "SUEnableAutomaticChecks")
    static let todo = OptionalBoolDefault(key: "todo")
    static let todoMode = BoolDefault(key: "todoMode")
    static let todoApplication = StringDefault(key: "todoApplication")
    static let todoSidebarWidth = FloatDefault(key: "todoSidebarWidth", defaultValue: 400)
    static let todoSidebarWidthUnit = IntEnumDefault<TodoSidebarWidthUnit>(key: "todoSidebarWidthUnit", defaultValue: .pixels)
    static let todoSidebarSide = IntEnumDefault<TodoSidebarSide>(key: "todoSidebarSide", defaultValue: .right)
    static let snapModifiers = IntDefault(key: "snapModifiers")
    static let attemptMatchOnNextPrevDisplay = OptionalBoolDefault(key: "attemptMatchOnNextPrevDisplay")
    static let altThirdCycle = OptionalBoolDefault(key: "altThirdCycle")
    static let centerHalfCycles = OptionalBoolDefault(key: "centerHalfCycles")
    static let cyclingOverlapOffset = OptionalBoolDefault(key: "cyclingOverlapOffset")
    static let cyclingOverlapOffsetSize = FloatDefault(key: "cyclingOverlapOffsetSize", defaultValue: 11)
    static let cyclingOverlapMaxCascade = IntDefault(key: "cyclingOverlapMaxCascade", defaultValue: 1)
    static let fullIgnoreBundleIds = JSONDefault<[String]>(key: "fullIgnoreBundleIds")
    static let notifiedOfProblemApps = BoolDefault(key: "notifiedOfProblemApps")
    static let specifiedHeight = FloatDefault(key: "specifiedHeight", defaultValue: 1050)
    static let specifiedWidth = FloatDefault(key: "specifiedWidth", defaultValue: 1680)
    static let horizontalSplitRatio = FloatDefault(key: "horizontalSplitRatio", defaultValue: 50)
    static let verticalSplitRatio = FloatDefault(key: "verticalSplitRatio", defaultValue: 50)
    static let moveCursorAcrossDisplays = OptionalBoolDefault(key: "moveCursorAcrossDisplays")
    static let moveCursor = OptionalBoolDefault(key: "moveCursor")
    static let autoMaximize = OptionalBoolDefault(key: "autoMaximize")
    static let applyGapsToMaximize = OptionalBoolDefault(key: "applyGapsToMaximize")
    static let applyGapsToMaximizeHeight = OptionalBoolDefault(key: "applyGapsToMaximizeHeight")
    static let cornerSnapAreaSize = FloatDefault(key: "cornerSnapAreaSize", defaultValue: 20)
    static let shortEdgeSnapAreaSize = FloatDefault(key: "shortEdgeSnapAreaSize", defaultValue: 145)
    static let cascadeAllDeltaSize = FloatDefault(key: "cascadeAllDeltaSize", defaultValue: 30)
    static let sixthsSnapArea = OptionalBoolDefault(key: "sixthsSnapArea")
    static let stageSize = FloatDefault(key: "stageSize", defaultValue: 190)
    static let dragFromStage = OptionalBoolDefault(key: "dragFromStage")
    static let alwaysAccountForStage = OptionalBoolDefault(key: "alwaysAccountForStage")
    static let landscapeSnapAreas = JSONDefault<[Directional:SnapAreaConfig]>(key: "landscapeSnapAreas")
    static let portraitSnapAreas = JSONDefault<[Directional:SnapAreaConfig]>(key: "portraitSnapAreas")
    static let missionControlDragging = OptionalBoolDefault(key: "missionControlDragging")
    static let enhancedUI = IntEnumDefault<EnhancedUI>(key: "enhancedUI", defaultValue: .disableEnable)
    static let footprintAnimationDurationMultiplier = FloatDefault(key: "footprintAnimationDurationMultiplier", defaultValue: 0)
    static let hapticFeedbackOnSnap = OptionalBoolDefault(key: "hapticFeedbackOnSnap")
    static let missionControlDraggingAllowedOffscreenDistance = FloatDefault(key: "missionControlDraggingAllowedOffscreenDistance", defaultValue: 25)
    static let missionControlDraggingDisallowedDuration = IntDefault(key: "missionControlDraggingDisallowedDuration", defaultValue: 250)
    static let doubleClickTitleBar = IntDefault(key: "doubleClickTitleBar")
    static let doubleClickTitleBarRestore = OptionalBoolDefault(key: "doubleClickTitleBarRestore")
    static let doubleClickTitleBarIgnoredApps = JSONDefault<[String]>(key: "doubleClickTitleBarIgnoredApps")
    static let doubleClickToolBarIgnoredApps = JSONDefault<Set<String>>(key: "doubleClickTitleBarIgnoredApps", defaultValue: ["epp.package.java"])
    static let ignoreDragSnapToo = OptionalBoolDefault(key: "ignoreDragSnapToo")
    static let systemWideMouseDown = OptionalBoolDefault(key: "systemWideMouseDown")
    static let systemWideMouseDownApps = JSONDefault<Set<String>>(key: "systemWideMouseDownApps", defaultValue: Set<String>(["org.languagetool.desktop", "com.microsoft.teams2"]))
    static let internalTilingNotified = BoolDefault(key: "internalTilingNotified")
    static let screensOrderedByX = OptionalBoolDefault(key: "screensOrderedByX")
    static let combinedDisplayMode = OptionalBoolDefault(key: "combinedDisplayMode")
    static var array: [Default] = [
        launchOnLogin,
        disabledApps,
        hideMenuBarIcon,
        alternateDefaultShortcuts,
        subsequentExecutionMode,
        selectedCycleSizes,
        cycleSizesIsChanged,
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
        widthStepSize,
        unsnapRestore,
        curtainChangeSize,
        relaunchOpensMenu,
        obtainWindowOnClick,
        screenEdgeGapTop,
        screenEdgeGapBottom,
        screenEdgeGapLeft,
        screenEdgeGapRight,
        screenEdgeGapsOnMainScreenOnly,
        screenEdgeGapTopNotch,
        showAllActionsInMenu,
        showAdditionalSizesInMenu,
        footprintAlpha,
        footprintBorderWidth,
        footprintFade,
        footprintColor,
        SUEnableAutomaticChecks,
        todo,
        todoMode,
        todoApplication,
        todoSidebarWidth,
        todoSidebarSide,
        snapModifiers,
        attemptMatchOnNextPrevDisplay,
        altThirdCycle,
        centerHalfCycles,
        fullIgnoreBundleIds,
        notifiedOfProblemApps,
        specifiedHeight,
        specifiedWidth,
        horizontalSplitRatio,
        verticalSplitRatio,
        moveCursorAcrossDisplays,
        moveCursor,
        autoMaximize,
        applyGapsToMaximize,
        applyGapsToMaximizeHeight,
        cornerSnapAreaSize,
        shortEdgeSnapAreaSize,
        cascadeAllDeltaSize,
        sixthsSnapArea,
        stageSize,
        dragFromStage,
        alwaysAccountForStage,
        landscapeSnapAreas,
        portraitSnapAreas,
        missionControlDragging,
        enhancedUI,
        footprintAnimationDurationMultiplier,
        hapticFeedbackOnSnap,
        missionControlDraggingAllowedOffscreenDistance,
        missionControlDraggingDisallowedDuration,
        doubleClickTitleBar,
        doubleClickTitleBarRestore,
        doubleClickTitleBarIgnoredApps,
        ignoreDragSnapToo,
        systemWideMouseDown,
        systemWideMouseDownApps,
        screensOrderedByX,
        cyclingOverlapOffset,
        cyclingOverlapOffsetSize,
        cyclingOverlapMaxCascade,
        moveFixedSizeToEdge
    ]

    static func loadPreferencesOnStartup() {
        PreferencesStore.shared.reloadFromDisk()
    }
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
                PreferencesStore.shared.set(enabled, forKey: key)
            }
        }
    }

    init(key: String) {
        self.key = key
        enabled = PreferencesStore.shared.bool(forKey: key)
        initialized = true
    }

    func load(from codable: CodableDefault) {
        if let value = codable.bool {
            enabled = value
        }
    }

    func toCodable() -> CodableDefault {
        CodableDefault(bool: enabled)
    }
}

class OptionalBoolDefault: Default {
    public private(set) var key: String
    private var initialized = false

    var enabled: Bool? {
        didSet {
            if initialized {
                if enabled == true {
                    PreferencesStore.shared.set(1, forKey: key)
                } else if enabled == false {
                    PreferencesStore.shared.set(2, forKey: key)
                } else {
                    PreferencesStore.shared.set(0, forKey: key)
                }
            }
        }
    }

    var userDisabled: Bool { enabled == false }
    var userEnabled: Bool { enabled == true }
    var notSet: Bool { enabled == nil }

    init(key: String) {
        self.key = key
        let intValue = PreferencesStore.shared.int(forKey: key)
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
        guard let enabled else { return CodableDefault(int: 0) }
        return CodableDefault(int: enabled ? 1 : 2)
    }
}

class StringDefault: Default {
    public private(set) var key: String
    private var initialized = false

    var value: String? {
        didSet {
            if initialized {
                PreferencesStore.shared.set(value, forKey: key)
            }
        }
    }

    init(key: String) {
        self.key = key
        value = PreferencesStore.shared.string(forKey: key)
        initialized = true
    }

    func load(from codable: CodableDefault) {
        value = codable.string
    }

    func toCodable() -> CodableDefault {
        CodableDefault(string: value)
    }
}

class FloatDefault: Default {
    public private(set) var key: String
    private var initialized = false

    var value: Float {
        didSet {
            if initialized {
                PreferencesStore.shared.set(value, forKey: key)
            }
        }
    }

    var cgFloat: CGFloat { CGFloat(value) }

    init(key: String, defaultValue: Float = 0) {
        self.key = key
        value = PreferencesStore.shared.float(forKey: key)
        // Apply the compile-time default only when the key is absent (value == 0)
        // and the caller specified a non-zero default.
        if defaultValue != 0 && value == 0 {
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
        CodableDefault(float: value)
    }
}

class IntDefault: Default {
    public private(set) var key: String
    private var initialized = false

    var value: Int {
        didSet {
            if initialized {
                PreferencesStore.shared.set(value, forKey: key)
            }
        }
    }

    init(key: String, defaultValue: Int = 0) {
        self.key = key
        value = PreferencesStore.shared.int(forKey: key)
        // Apply the compile-time default only when the key is absent (value == 0)
        // and the caller specified a non-zero default.
        if defaultValue != 0 && value == 0 {
            value = defaultValue
        }
        initialized = true
    }

    func load(from codable: CodableDefault) {
        if let int = codable.int {
            value = int
        }
    }

    func toCodable() -> CodableDefault {
        CodableDefault(int: value)
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

    init(key: String, defaultValue: T) {
        super.init(key: key)
        loadFromJSON()
        if typedValue == nil {
            typedValue = defaultValue
            saveToJSON(defaultValue)
        }
        typeInitialized = true
    }

    override func load(from codable: CodableDefault) {
        if value != codable.string {
            value = codable.string
            typeInitialized = false
            loadFromJSON()
            typeInitialized = true
        }
    }

    private func loadFromJSON() {
        guard let jsonString = value else { return }
        let decoder = JSONDecoder()
        guard let jsonData = jsonString.data(using: .utf8) else { return }
        typedValue = try? decoder.decode(T.self, from: jsonData)
    }

    private func saveToJSON(_ obj: T?) {
        let encoder = JSONEncoder()
        if let jsonData = try? encoder.encode(obj),
           let jsonString = String(data: jsonData, encoding: .utf8),
           jsonString != value {
            value = jsonString
        }
    }
}

class IntEnumDefault<E: RawRepresentable>: Default where E.RawValue == Int {
    public private(set) var key: String
    private let defaultValue: E

    private var backingValue: E
    var value: E {
        get { backingValue }
        set {
            guard newValue != backingValue else { return }
            backingValue = newValue
            PreferencesStore.shared.set(backingValue.rawValue, forKey: key)
        }
    }

    init(key: String, defaultValue: E) {
        self.key = key
        self.defaultValue = defaultValue
        let intValue = PreferencesStore.shared.int(forKey: key)
        backingValue = E(rawValue: intValue) ?? defaultValue
    }

    func load(from codable: CodableDefault) {
        if let intValue = codable.int, backingValue.rawValue != intValue {
            backingValue = E(rawValue: intValue) ?? defaultValue
            PreferencesStore.shared.set(backingValue.rawValue, forKey: key)
        }
    }

    func toCodable() -> CodableDefault {
        CodableDefault(int: value.rawValue)
    }
}

struct CodableColor: Codable {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 1.0

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    init(nsColor: NSColor) {
        self.red = nsColor.redComponent
        self.green = nsColor.greenComponent
        self.blue = nsColor.blueComponent
        self.alpha = nsColor.alphaComponent
    }
}
