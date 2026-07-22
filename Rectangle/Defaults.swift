/// Defaults.swift

import Cocoa
import MASShortcut

// MARK: - PreferencesStore

/// A thread-safe, plist-backed key-value store that replaces UserDefaults for
/// all Rectangle preferences.
///
/// **Symlink / read-only handling** — the store is designed for use with
/// externally-managed plist files (e.g. an iTerm2-style live config symlink).
/// If the resolved plist path is not writable by the current process, the store
/// silently enters read-only mode: reads work normally (the symlink is followed),
/// writes are no-ops.  No data is lost because the underlying file is owned and
/// written by an external tool.
final class PreferencesStore {
    static let shared = PreferencesStore()

    // Sentinel stored in the plist to distinguish "user explicitly cleared a
    // shortcut" from "key absent (→ restore the per-action default)".
    fileprivate static let disabledShortcutMarker = "__RECTANGLE_SHORTCUT_DISABLED__"

    private let fileURL: URL
    private var format: PropertyListSerialization.PropertyListFormat = .binary
    private var storage: [String: Any] = [:]

    // Concurrent queue: reads are synchronised via sync{}, writes use barrier.
    private let queue = DispatchQueue(
        label: "com.knollsoft.Rectangle.PreferencesStore",
        attributes: .concurrent
    )

    /// True when the plist file is on a read-only path or is a symlink to a
    /// file we don't own.  In read-only mode all writes are silently skipped.
    private(set) var isReadOnly = false

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

    // MARK: Disk I/O

    func reloadFromDisk() {
        // Determine read-only status by probing write access on the *resolved*
        // path (so symlinks are followed, not treated as errors).
        let resolvedPath: String
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path) {
            // fileURL is a symlink — follow it for reads, treat as read-only for writes.
            resolvedPath = dest
            isReadOnly = true
        } else {
            resolvedPath = fileURL.path
            // Check writability: either the file exists and is writable, or its
            // parent directory is writable (so we can create the file).
            let fm = FileManager.default
            if fm.fileExists(atPath: resolvedPath) {
                isReadOnly = !fm.isWritableFile(atPath: resolvedPath)
            } else {
                let dir = fileURL.deletingLastPathComponent().path
                isReadOnly = !fm.isWritableFile(atPath: dir)
            }
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            queue.async(flags: .barrier) {
                self.storage = [:]
                self.format = .binary
            }
            return
        }

        do {
            let resolvedURL = URL(fileURLWithPath: resolvedPath)
            let data = try Data(contentsOf: resolvedURL)
            var readFormat: PropertyListSerialization.PropertyListFormat = .binary
            let plist = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &readFormat)
            if let dict = plist as? [String: Any] {
                queue.async(flags: .barrier) {
                    self.storage = dict
                    self.format = readFormat
                }
            } else {
                throw NSError(domain: "PreferencesStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Root is not a dictionary"])
            }
        } catch {
            queue.async(flags: .barrier) {
                self.storage = [:]
                self.format = .binary
            }
            Logger.log("Unable to load preferences from \(resolvedPath): \(error.localizedDescription)")
        }
    }

    // MARK: Existence / raw access

    func objectExists(forKey key: String) -> Bool {
        queue.sync { storage[key] != nil }
    }

    func foundationObject(forKey key: String) -> Any? {
        queue.sync { storage[key] }
    }

    // MARK: Typed reads

    func bool(forKey key: String) -> Bool {
        queue.sync { storage[key] as? Bool ?? false }
    }

    func int(forKey key: String) -> Int {
        queue.sync {
            if let v = storage[key] as? Int { return v }
            if let v = storage[key] as? Double { return Int(v) }
            return 0
        }
    }

    func float(forKey key: String) -> Float {
        queue.sync {
            if let v = storage[key] as? Double { return Float(v) }
            if let v = storage[key] as? Int { return Float(v) }
            return 0
        }
    }

    func string(forKey key: String) -> String? {
        queue.sync { storage[key] as? String }
    }

    func data(forKey key: String) -> Data? {
        queue.sync { storage[key] as? Data }
    }

    // MARK: Typed writes

    func set(_ value: Bool, forKey key: String) {
        write { self.storage[key] = value }
    }

    func set(_ value: Int, forKey key: String) {
        write { self.storage[key] = value }
    }

    func set(_ value: Float, forKey key: String) {
        write { self.storage[key] = Double(value) }
    }

    func set(_ value: String?, forKey key: String) {
        write { self.storage[key] = value }
    }

    func set(_ value: Data?, forKey key: String) {
        write { self.storage[key] = value }
    }

    /// Stores an arbitrary Foundation-compatible value (the type used by
    /// MASShortcut's dictionary transformer).  Logs and no-ops if the value
    /// cannot be represented in a plist.
    func set(any value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
            Logger.log("Unable to save unsupported preference value for \(key)")
            return
        }
        write { self.storage[key] = value }
    }

    func removeObject(forKey key: String) {
        write { self.storage[key] = nil }
    }

    // MARK: Private helpers

    /// Runs `mutation` under a barrier write, then persists — unless read-only.
    private func write(_ mutation: @escaping () -> Void) {
        queue.async(flags: .barrier) {
            mutation()
            self.persist()
        }
    }

    private func persist() {
        // In read-only mode (symlink target or non-writable path) we skip writes
        // silently.  Preferences are still readable for the duration of the
        // session; the external owner is responsible for persistence.
        guard !isReadOnly else { return }

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            let data = try PropertyListSerialization.data(fromPropertyList: storage, format: format, options: 0)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.log("Unable to save preferences to \(fileURL.path): \(error.localizedDescription)")
        }
    }
}

// MARK: - ShortcutStore

/// Manages reading and writing MASShortcut values through PreferencesStore.
///
/// Shortcuts are stored as dictionaries produced by `MASDictionaryTransformerName`.
/// A sentinel string (`PreferencesStore.disabledShortcutMarker`) is written when
/// the user explicitly clears a shortcut, so the per-action default is not
/// restored on next launch.
enum ShortcutStore {

    private static var dictTransformer: ValueTransformer? {
        ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))
    }

    private static var dataTransformer: ValueTransformer? {
        ValueTransformer(forName: .secureUnarchiveFromDataTransformerName)
    }

    // MARK: Reads

    static func shortcut(for action: WindowAction) -> MASShortcut? {
        shortcut(forKey: action.name, fallback: defaultShortcut(for: action))
    }

    /// Three-tier read:
    ///   1. Sentinel present → user explicitly disabled this shortcut.
    ///   2. Dict format → current storage format.
    ///   3. Legacy Data format → migrate on the fly and return.
    ///   4. `fallback` → first-run default.
    static func shortcut(forKey key: String, fallback: MASShortcut? = nil) -> MASShortcut? {
        if PreferencesStore.shared.string(forKey: key) == PreferencesStore.disabledShortcutMarker {
            return nil
        }

        if let rawShortcut = PreferencesStore.shared.foundationObject(forKey: key) as? [String: Any],
           let shortcut = dictTransformer?.transformedValue(rawShortcut) as? MASShortcut {
            return shortcut
        }

        // Legacy binary Data format — migrate to dict format in place.
        if let dataValue = PreferencesStore.shared.data(forKey: key),
           let shortcut = dataTransformer?.transformedValue(dataValue) as? MASShortcut {
            setShortcut(shortcut, forKey: key)
            return shortcut
        }

        // First run: write the fallback so future reads skip this path.
        if let fallback {
            setShortcut(fallback, forKey: key)
        }
        return fallback
    }

    // MARK: Writes

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

    // MARK: Defaults

    static func defaultShortcut(for action: WindowAction) -> MASShortcut? {
        let shortcut = Defaults.alternateDefaultShortcuts.enabled
            ? action.alternateDefault
            : action.spectacleDefault
        guard let shortcut else { return nil }
        return MASShortcut(keyCode: shortcut.keyCode,
                           modifierFlags: NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags))
    }
}

// MARK: - Defaults

class Defaults {
    static let launchOnLogin = BoolDefault(key: "launchOnLogin")
    static let disabledApps = StringDefault(key: "disabledApps")
    static let hideMenuBarIcon = BoolDefault(key: "hideMenubarIcon")
    static let alternateDefaultShortcuts = BoolDefault(key: "alternateDefaultShortcuts") // switch to magnet defaults
    static let subsequentExecutionMode = SubsequentExecutionDefault()
    static let selectedCycleSizes = CycleSizesDefault()
    static let cycleSizesIsChanged = BoolDefault(key: "cycleSizesIsChanged")
    static let cornerCycleExpansionAxis = IntEnumDefault<CornerCycleExpansionAxis>(key: "cornerCycleExpansionAxis", defaultValue: .horizontal)
    static let cooperativeCornerResize = BoolDefault(key: "cooperativeCornerResize")
    static let allowAnyShortcut = BoolDefault(key: "allowAnyShortcut")
    static let windowSnapping = OptionalBoolDefault(key: "windowSnapping")
    static let almostMaximizeHeight = FloatDefault(key: "almostMaximizeHeight")
    static let almostMaximizeWidth = FloatDefault(key: "almostMaximizeWidth")
    static let gapSize = FloatDefault(key: "gapSize")
    static let skipGapTopEdge = BoolDefault(key: "skipGapTopEdge")
    static let snapEdgeMarginTop = FloatDefault(key: "snapEdgeMarginTop", defaultValue: 5)
    static let snapEdgeMarginBottom = FloatDefault(key: "snapEdgeMarginBottom", defaultValue: 5)
    static let snapEdgeMarginLeft = FloatDefault(key: "snapEdgeMarginLeft", defaultValue: 5)
    static let snapEdgeMarginRight = FloatDefault(key: "snapEdgeMarginRight", defaultValue: 5)
    static let centeredDirectionalMove = OptionalBoolDefault(key: "centeredDirectionalMove")
    static let resizeOnDirectionalMove = BoolDefault(key: "resizeOnDirectionalMove")
    static let moveFixedSizeToEdge = IntEnumDefault<EdgeAlignment>(key: "moveFixedSizeToEdge", defaultValue: .edgesAndCorners)
    static let ignoredSnapAreas = IntDefault(key: "ignoredSnapAreas")
    static let traverseSingleScreen = OptionalBoolDefault(key: "traverseSingleScreen")
    static let useCursorScreenDetection = BoolDefault(key: "useCursorScreenDetection")
    static let minimumWindowWidth = FloatDefault(key: "minimumWindowWidth")
    static let minimumWindowHeight = FloatDefault(key: "minimumWindowHeight")
    static let sizeOffset = FloatDefault(key: "sizeOffset")
    static let widthStepSize = FloatDefault(key: "widthStepSize", defaultValue: 30)
    static let unsnapRestore = OptionalBoolDefault(key: "unsnapRestore")
    static let unsnapRestoreFromSizeChange = OptionalBoolDefault(key: "unsnapRestoreFromSizeChange")
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
    static let landscapeSnapAreas = JSONDefault<[Directional: SnapAreaConfig]>(key: "landscapeSnapAreas")
    static let portraitSnapAreas = JSONDefault<[Directional: SnapAreaConfig]>(key: "portraitSnapAreas")
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
    static let screensOrderedByX = IntEnumDefault<ScreenOrdering>(key: "screensOrderedByX", defaultValue: .yThenMinX)
    static let combinedDisplayMode = OptionalBoolDefault(key: "combinedDisplayMode")
    static let greenButtonOverride = BoolDefault(key: "greenButtonOverride")
    // Live config file (iTerm2-style). Deliberately excluded from `array` so the
    // config file never writes its own location/enablement back into itself.
    static let configFileEnabled = OptionalBoolDefault(key: "configFileEnabled")
    static let configFileFolder = StringDefault(key: "configFileFolder")
    static var array: [Default] = [
        launchOnLogin,
        disabledApps,
        hideMenuBarIcon,
        alternateDefaultShortcuts,
        subsequentExecutionMode,
        selectedCycleSizes,
        cycleSizesIsChanged,
        cornerCycleExpansionAxis,
        cooperativeCornerResize,
        allowAnyShortcut,
        windowSnapping,
        almostMaximizeHeight,
        almostMaximizeWidth,
        gapSize,
        skipGapTopEdge,
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
        todoSidebarWidthUnit,
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
        moveFixedSizeToEdge,
        greenButtonOverride
    ]
}

// MARK: - CodableDefault

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

// MARK: - Default protocol

protocol Default {
    var key: String { get }
    func load(from codable: CodableDefault)
    func toCodable() -> CodableDefault
}

// MARK: - BoolDefault

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

// MARK: - OptionalBoolDefault

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

// MARK: - StringDefault

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

// MARK: - FloatDefault

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

// MARK: - IntDefault

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

// MARK: - JSONDefault

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
        guard let jsonString = value,
              let jsonData = jsonString.data(using: .utf8) else { return }
        typedValue = try? JSONDecoder().decode(T.self, from: jsonData)
    }

    private func saveToJSON(_ obj: T?) {
        if let jsonData = try? JSONEncoder().encode(obj),
           let jsonString = String(data: jsonData, encoding: .utf8),
           jsonString != value {
            value = jsonString
        }
    }
}

// MARK: - IntEnumDefault

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

// MARK: - CodableColor

struct CodableColor: Codable {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 1.0

    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    init(nsColor: NSColor) {
        red = nsColor.redComponent
        green = nsColor.greenComponent
        blue = nsColor.blueComponent
        alpha = nsColor.alphaComponent
    }
}
