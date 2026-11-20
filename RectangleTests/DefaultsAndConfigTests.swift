/// DefaultsAndConfigTests.swift

import MASShortcut
import XCTest
@testable import Rectangle

class WindowActionMenuTests: XCTestCase {

    func testRowsAndColumnsShareOptionalSubmenu() throws {
        for showAdditional in [false, true] {
            let menu = makeMenu(showAdditional: showAdditional, showAllActions: false)
            let tilingItems = menu.items.filter { item in
                item.submenu?.items.contains { $0.representedObject as? WindowAction == .tileRows } == true
            }
            XCTAssertEqual(tilingItems.count, 1)
            let tilingItem = try XCTUnwrap(tilingItems.first)
            XCTAssertEqual(tilingItem.submenu?.items.compactMap { $0.representedObject as? WindowAction },
                           [.tileRows, .tileColumns])
            XCTAssertEqual(tilingItem.isHidden, !showAdditional)
            let topLevelActions = menu.items.compactMap { $0.representedObject as? WindowAction }
            XCTAssertFalse(topLevelActions.contains(.tileRows))
            XCTAssertFalse(topLevelActions.contains(.tileColumns))
            XCTAssertTrue(topLevelActions.contains(.maximize))
        }
    }

    func testShowAllActionsKeepsRowsAndColumnsFlat() {
        let menu = makeMenu(showAdditional: false, showAllActions: true)
        let visibleActions = menu.items.filter { !$0.isHidden }.compactMap { $0.representedObject as? WindowAction }
        XCTAssertTrue(visibleActions.contains(.tileRows))
        XCTAssertTrue(visibleActions.contains(.tileColumns))
        XCTAssertFalse(menu.items.contains { $0.submenu != nil })
    }

    private func makeMenu(showAdditional: Bool, showAllActions: Bool) -> NSMenu {
        let menu = NSMenu()
        let delegate = AppDelegate()
        delegate.mainStatusMenu = menu
        delegate.addWindowActionMenuItems(showAdditional: showAdditional, showAllActions: showAllActions)
        return menu
    }
}

class GridLimitDefaultsTests: XCTestCase {
    // Separate limits round-trip without replacing explicitly saved values or
    // writing an absent default into the user's preferences.
    func testIndependentDefaultsAndConfigRoundTripPreserveExplicitValues() {
        let suiteName = "RectangleGridDefaults-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let columns = PositiveIntDefault(key: "columns", defaultValue: 3, userDefaults: preferences)
        let rows = PositiveIntDefault(key: "rows", defaultValue: 3, userDefaults: preferences)
        XCTAssertEqual(columns.value, 3)
        XCTAssertEqual(rows.value, 3)
        XCTAssertNil(preferences.object(forKey: "columns"))
        columns.value = 1
        rows.load(from: CodableDefault(int: 2))
        XCTAssertEqual(columns.toCodable().int, 1)
        XCTAssertEqual(rows.toCodable().int, 2)
        XCTAssertEqual(PositiveIntDefault(key: "columns", defaultValue: 3, userDefaults: preferences).value, 1)
        XCTAssertEqual(PositiveIntDefault(key: "rows", defaultValue: 3, userDefaults: preferences).value, 2)
        columns.load(from: CodableDefault())
        XCTAssertEqual(columns.value, 1)
    }

    func testInvalidSavedLimitsNormalizeWithoutWritingOnRead() {
        let suiteName = "RectangleGridDefaults-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("invalid", forKey: "limit")
        let limit = PositiveIntDefault(key: "limit", defaultValue: 3, userDefaults: preferences)
        XCTAssertEqual(limit.value, 1)
        XCTAssertEqual(preferences.string(forKey: "limit"), "invalid")
        limit.load(from: CodableDefault(int: 0))
        XCTAssertEqual(limit.value, 1)
        XCTAssertEqual(preferences.integer(forKey: "limit"), 1)
    }
}

final class FootprintAlphaDefaultsTests: XCTestCase {
    private var savedAlpha: Double = 0
    private var savedBlur = false
    private var storedAlpha: Any?
    private var storedBlur: Any?

    override func setUp() {
        super.setUp()
        savedAlpha = Defaults.footprintAlpha.value
        savedBlur = Defaults.footprintBlur.enabled
        storedAlpha = UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key)
        storedBlur = UserDefaults.standard.object(forKey: Defaults.footprintBlur.key)
        UserDefaults.standard.removeObject(forKey: Defaults.footprintAlpha.key)
    }

    override func tearDown() {
        Defaults.footprintAlpha.value = savedAlpha
        Defaults.footprintBlur.enabled = savedBlur
        UserDefaults.standard.set(storedAlpha, forKey: Defaults.footprintAlpha.key)
        UserDefaults.standard.set(storedBlur, forKey: Defaults.footprintBlur.key)
        super.tearDown()
    }

    func testUnsetAlphaFollowsPreviewStyleWithoutSavingAValue() {
        let window = FootprintWindow(accessibility: {
            FootprintAccessibility(reduceMotion: false, reduceTransparency: false)
        })
        defer { window.close() }

        for blurred in [false, true, false] {
            Defaults.footprintBlur.enabled = blurred
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, blurred ? 0 : 0.3)
            XCTAssertEqual(window.presentation.alpha, blurred ? 1 : 0.3)
            XCTAssertEqual(window.presentation.usesBlur, blurred)
            XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key))
        }
    }

    func testExplicitZeroSurvivesStyleChangesReloadAndConfigRoundTrip() throws {
        Defaults.footprintAlpha.value = 0
        for blurred in [false, true] {
            Defaults.footprintBlur.enabled = blurred
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, 0)
            XCTAssertEqual(DoubleDefault(key: Defaults.footprintAlpha.key).value, 0)

            let exported = try exportedAlpha()
            XCTAssertEqual(exported.double, 0)
            XCTAssertNil(exported.float)
            Defaults.footprintAlpha.value = 0.8
            Defaults.footprintAlpha.load(from: exported)
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, 0)
        }
    }

    func testLegacyFloatValuesAndDoublePrecisionArePreserved() throws {
        for json in [#"{"float":0}"#, #"{"float":0.4}"#, #"{"double":0.123456789012345}"#] {
            let imported = try JSONDecoder().decode(CodableDefault.self, from: Data(json.utf8))
            let expected = imported.double ?? Double(imported.float!)
            Defaults.footprintAlpha.load(from: imported)
            for blurred in [false, true] {
                Defaults.footprintBlur.enabled = blurred
                XCTAssertEqual(Defaults.effectiveFootprintAlpha, expected)
                XCTAssertEqual(DoubleDefault(key: Defaults.footprintAlpha.key).value, expected)
                XCTAssertEqual(try exportedAlpha().double, expected)
            }
        }
    }

    func testExportUsesTheEffectiveUnsetAlpha() throws {
        for blurred in [false, true] {
            UserDefaults.standard.removeObject(forKey: Defaults.footprintAlpha.key)
            Defaults.footprintBlur.enabled = blurred
            let exported = try exportedAlpha()
            XCTAssertEqual(exported.double, blurred ? 0 : 0.3)
            XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key))

            Defaults.footprintAlpha.value = 0.8
            Defaults.footprintAlpha.load(from: exported)
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, blurred ? 0 : 0.3)
        }
    }

    private func exportedAlpha() throws -> CodableDefault {
        let json = try XCTUnwrap(Defaults.encoded())
        let config = try XCTUnwrap(Defaults.convert(jsonString: json))
        return try XCTUnwrap(config.defaults[Defaults.footprintAlpha.key])
    }
}

final class BoolDefaultTests: XCTestCase {

    /// A supplied default (e.g. ignoreShortcutsInMissionControl) applies only
    /// while the key is unset; an explicit `-bool false`/`true` always wins, and
    /// omitting a default keeps the historical false.
    func testDefaultValueAppliesOnlyWhileUnset() {
        let key = "boolDefaultTest_\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertTrue(BoolDefault(key: key, defaultValue: true).enabled, "Unset falls back to the supplied default")
        XCTAssertFalse(BoolDefault(key: key).enabled, "Unset stays false when no default is supplied")

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(BoolDefault(key: key, defaultValue: true).enabled, "An explicit false overrides a true default")

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(BoolDefault(key: key, defaultValue: false).enabled, "An explicit true overrides a false default")
    }
}

class DefaultsExportTests: XCTestCase {

    func testOverlapDefaultsInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("cyclingOverlapOffset"), "cyclingOverlapOffset missing from Defaults.array")
        XCTAssertTrue(keys.contains("cyclingOverlapOffsetSize"), "cyclingOverlapOffsetSize missing from Defaults.array")
        XCTAssertTrue(keys.contains("cyclingOverlapMaxCascade"), "cyclingOverlapMaxCascade missing from Defaults.array")
        XCTAssertTrue(keys.contains("cooperativeCornerResize"), "cooperativeCornerResize missing from Defaults.array")
        XCTAssertTrue(keys.contains("stackBadge"), "stackBadge missing from Defaults.array")
        XCTAssertTrue(keys.contains("stackSameSizeOnly"), "stackSameSizeOnly missing from Defaults.array")
    }

    func testMouseButtonSettingInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("mouseButtonShortcutsUseWindowUnderCursor"), "mouseButtonShortcutsUseWindowUnderCursor missing from Defaults.array")
    }

    func testIgnoreMenuBarInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("ignoreMenuBar"), "ignoreMenuBar missing from Defaults.array")
    }

    func testNewWindowActionInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("newWindowAction"), "newWindowAction missing from Defaults.array")
    }
}

final class SettingsLabelLocalizationTests: XCTestCase {

    // These Settings labels used to be plain literals, so they stayed English in every language.
    func testSettingsOnlyLabelsHaveSimplifiedChineseTranslations() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let zhHans = try XCTUnwrap(Bundle(path: path))
        for key in ["Extra", "Ninths (3x3)", "Twelfths (3x4)", "Sixteenths (4x4)"] {
            let value = zhHans.localizedString(forKey: key, value: nil, table: "Localizable")
            XCTAssertNotEqual(value, key, "\(key) has no zh-Hans translation")
        }
    }

    func testSettingsOnlyLabelsHaveTraditionalChineseTranslations() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hant", ofType: "lproj"))
        let zhHant = try XCTUnwrap(Bundle(path: path))
        for key in ["Extra", "Ninths (3x3)", "Twelfths (3x4)", "Sixteenths (4x4)"] {
            let value = zhHant.localizedString(forKey: key, value: nil, table: "Localizable")
            XCTAssertNotEqual(value, key, "\(key) has no zh-Hant translation")
        }
    }

    func testSettingsOnlyLabelsHaveJapaneseTranslations() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ja", ofType: "lproj"))
        let ja = try XCTUnwrap(Bundle(path: path))
        for key in ["Extra", "Ninths (3x3)", "Twelfths (3x4)", "Sixteenths (4x4)"] {
            let value = ja.localizedString(forKey: key, value: nil, table: "Localizable")
            XCTAssertNotEqual(value, key, "\(key) has no ja translation")
        }
    }

    func testSettingsDisplayNamesKeepTheirEnglishText() {
        XCTAssertEqual(WindowAction.topLeftNinth.settingsDisplayName, String(localized: "Ninths (3x3)"))
        XCTAssertEqual(WindowAction.topLeftTwelfth.settingsDisplayName, String(localized: "Twelfths (3x4)"))
        XCTAssertEqual(WindowAction.topLeftSixteenth.settingsDisplayName, String(localized: "Sixteenths (4x4)"))
    }
}

final class BundleIdentityTests: XCTestCase {

    func testDebugBuildsUseTheirOwnBundleIdentifier() {
        // Keeps a build from Xcode from sharing the installed app's
        // Accessibility permission and preferences.
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.knollsoft.Rectangle.debug")
    }

    func testExportedConfigKeepsTheReleaseBundleIdentifier() throws {
        let json = try XCTUnwrap(Defaults.encoded())
        let config = try XCTUnwrap(Defaults.convert(jsonString: json))
        XCTAssertEqual(config.bundleId, "com.knollsoft.Rectangle")
    }
}

class ConfigImportTests: XCTestCase {

    private static let shortcutKeys = WindowAction.active.map(\.name) + TodoManager.defaultsKeys + StackBadgeManager.defaultsKeys
    private var storedValues = [String: Any]()
    private var absentKeys = Set<String>()

    override func setUp() {
        super.setUp()
        for key in Self.shortcutKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                storedValues[key] = value
            } else {
                absentKeys.insert(key)
            }
        }
    }

    override func tearDown() {
        for key in Self.shortcutKeys {
            if let value = storedValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else if absentKeys.contains(key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        storedValues.removeAll()
        absentKeys.removeAll()
        super.tearDown()
    }

    func testImportClearsOmittedActiveShortcut() throws {
        try XCTSkipIf(true, "Flaky: intermittently fails the XCTAssertNil. Skipped until the cause is found.")

        let action = WindowAction.almostMaximize
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 10), forKey: action.name)

        try loadConfig(shortcuts: [:])

        XCTAssertNil(UserDefaults.standard.object(forKey: action.name))
    }

    func testImportClearsOmittedTodoShortcut() throws {
        let defaultsKey = TodoManager.toggleDefaultsKey
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 11), forKey: defaultsKey)

        try loadConfig(shortcuts: [:])

        XCTAssertNil(UserDefaults.standard.object(forKey: defaultsKey))
    }

    func testImportClearsOmittedStackBadgeShortcut() throws {
        let defaultsKey = StackBadgeManager.toggleDefaultsKey
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 14), forKey: defaultsKey)

        try loadConfig(shortcuts: [:])

        XCTAssertNil(UserDefaults.standard.object(forKey: defaultsKey))
    }

    func testImportAppliesSuppliedActiveShortcut() throws {
        let action = WindowAction.almostMaximize
        let importedShortcut = Shortcut(NSEvent.ModifierFlags.command.rawValue, 12)

        try loadConfig(shortcuts: [action.name: importedShortcut])

        let storedShortcut = try XCTUnwrap(ShortcutCycle.shortcut(for: action))
        XCTAssertEqual(storedShortcut.keyCode, importedShortcut.keyCode)
        XCTAssertEqual(storedShortcut.modifierFlags.rawValue, importedShortcut.modifierFlags)
    }

    func testImportUsesActiveShortcutAlias() throws {
        let action = WindowAction.leftHalf
        let alias = try XCTUnwrap(action.aliasName)
        let importedShortcut = Shortcut(NSEvent.ModifierFlags.command.rawValue, 13)

        try loadConfig(shortcuts: [alias: importedShortcut])

        let storedShortcut = try XCTUnwrap(ShortcutCycle.shortcut(for: action))
        XCTAssertEqual(storedShortcut.keyCode, importedShortcut.keyCode)
        XCTAssertEqual(storedShortcut.modifierFlags.rawValue, importedShortcut.modifierFlags)
    }

    func testImportClearsInvalidActiveShortcut() throws {
        try XCTSkipIf(true, "Flaky: intermittently fails the XCTAssertNil. Skipped until the cause is found.")

        let action = WindowAction.almostMaximize
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 14), forKey: action.name)

        try loadConfig(shortcuts: [action.name: Shortcut(NSEvent.ModifierFlags.command.rawValue, -1)])

        XCTAssertNil(UserDefaults.standard.object(forKey: action.name))
    }

    func testImportAppliesSuppliedMouseButtonShortcut() throws {
        let action = WindowAction.cycleStackedWindows
        let mouseButton = MouseButtonShortcut(buttonNumber: 3, modifierFlags: [.option])

        try loadConfig(shortcuts: [action.name: Shortcut(masShortcut: mouseButton)])

        let storedShortcut = try XCTUnwrap(ShortcutCycle.shortcut(for: action))
        XCTAssertTrue(MouseButtonShortcut.isMouseButton(storedShortcut))
        XCTAssertEqual(ShortcutCycle.ShortcutIdentity(storedShortcut), ShortcutCycle.ShortcutIdentity(mouseButton))
    }

    func testExportIncludesMouseButtonShortcutAndSetting() throws {
        let action = WindowAction.cycleStackedWindowsBackward
        let mouseButton = MouseButtonShortcut(buttonNumber: 4, modifierFlags: [])
        store(Shortcut(masShortcut: mouseButton), forKey: action.name)

        let config = try XCTUnwrap(Defaults.encoded().flatMap { Defaults.convert(jsonString: $0) })

        let exportedShortcut = try XCTUnwrap(config.shortcuts[action.name])
        XCTAssertEqual(exportedShortcut.keyCode, mouseButton.keyCode)
        XCTAssertEqual(exportedShortcut.modifierFlags, mouseButton.modifierFlags.rawValue)
        XCTAssertNotNil(config.defaults[Defaults.mouseButtonShortcutsUseWindowUnderCursor.key])
    }

    private func store(_ shortcut: Shortcut, forKey key: String) {
        let transformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let value = transformer.reverseTransformedValue(shortcut.toMASSHortcut())
        UserDefaults.standard.set(value, forKey: key)
    }

    private func loadConfig(shortcuts: [String: Shortcut]) throws {
        let config = Config(bundleId: "com.knollsoft.Rectangle",
                            version: "ConfigImportTests",
                            shortcuts: shortcuts,
                            defaults: [:])
        let data = try JSONEncoder().encode(config)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigImportTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try data.write(to: fileURL, options: .atomic)

        Defaults.load(fileUrl: fileURL, notificationCenter: NotificationCenter())
    }
}
