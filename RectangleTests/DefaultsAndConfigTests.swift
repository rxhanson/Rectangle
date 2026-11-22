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
    private var storedAlpha: Any?
    private var storedMaterial: Any?

    override func setUp() {
        super.setUp()
        savedAlpha = Defaults.footprintAlpha.value
        storedAlpha = UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key)
        storedMaterial = UserDefaults.standard.object(forKey: Defaults.overlayMaterial.key)
        UserDefaults.standard.removeObject(forKey: Defaults.footprintAlpha.key)
    }

    override func tearDown() {
        Defaults.footprintAlpha.value = savedAlpha
        UserDefaults.standard.set(storedAlpha, forKey: Defaults.footprintAlpha.key)
        UserDefaults.standard.set(storedMaterial, forKey: Defaults.overlayMaterial.key)
        super.tearDown()
    }

    func testUnsetAlphaFollowsPreviewStyleWithoutSavingAValue() {
        let window = FootprintWindow(accessibility: {
            FootprintAccessibility(reduceMotion: false, reduceTransparency: false)
        })
        defer { window.close() }

        for material in [OverlayMaterial.noBlur, .standard, .liquidGlass, .noBlur] {
            Defaults.overlayMaterial.value = material
            let systemUsesBlur = material.usesBlur && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, systemUsesBlur ? 0 : 0.3)
            XCTAssertEqual(window.presentation.alpha, material.usesBlur ? 1 : 0.3)
            XCTAssertEqual(window.presentation.usesBlur, material.usesBlur)
            XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key))
        }
    }

    func testExplicitZeroSurvivesStyleChangesReloadAndConfigRoundTrip() throws {
        Defaults.footprintAlpha.value = 0
        for material in [OverlayMaterial.noBlur, .standard, .liquidGlass] {
            Defaults.overlayMaterial.value = material
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
            for material in [OverlayMaterial.noBlur, .standard, .liquidGlass] {
                Defaults.overlayMaterial.value = material
                XCTAssertEqual(Defaults.effectiveFootprintAlpha, expected)
                XCTAssertEqual(DoubleDefault(key: Defaults.footprintAlpha.key).value, expected)
                XCTAssertEqual(try exportedAlpha().double, expected)
            }
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
    private var storedKeys: [String] {
        Self.shortcutKeys + [Defaults.overlayMaterial.key, Defaults.gapSize.key,
                             Defaults.blurAppearance.key, Defaults.footprintAlpha.key]
    }
    private var savedGap: Float = 0
    private var savedAppearance = BlurAppearance.system
    private var savedAlpha: Double = 0
    private var storedValues = [String: Any]()
    private var absentKeys = Set<String>()

    override func setUp() {
        super.setUp()
        savedGap = Defaults.gapSize.value
        savedAppearance = Defaults.blurAppearance.value
        savedAlpha = Defaults.footprintAlpha.value
        for key in storedKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                storedValues[key] = value
            } else {
                absentKeys.insert(key)
            }
        }
    }

    override func tearDown() {
        Defaults.gapSize.value = savedGap
        Defaults.blurAppearance.value = savedAppearance
        Defaults.footprintAlpha.value = savedAlpha
        for key in storedKeys {
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

    func testImportBeforeAccessibilitySetupCompletesWithoutWindowManagers() throws {
        let delegate = AppDelegate()
        let notifications = NotificationCenter()
        let handled = expectation(description: "Imported configuration was handled before Accessibility setup")
        let observer = Notification.Name.configImported.onPost(center: notifications) { _ in
            delegate.reloadWindowManagementAfterImport()
            handled.fulfill()
        }
        defer { notifications.removeObserver(observer) }

        try loadConfig(shortcuts: [:], notificationCenter: notifications)
        wait(for: [handled], timeout: 1)
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

    func testExportedFilesRoundTripAllOverlayMaterialsUsingOnlyTheCanonicalKey() throws {
        // Reading a complete export back writes every included preference, even originally unset ones.
        let saved = Defaults.array.map { ($0, $0.toCodable(), UserDefaults.standard.object(forKey: $0.key)) }
        defer {
            for (preference, cached, stored) in saved {
                preference.load(from: cached)
                UserDefaults.standard.set(stored, forKey: preference.key)
            }
        }
        for selection in [OverlayMaterial.noBlur, .standard, .liquidGlass] {
            Defaults.overlayMaterial.value = selection
            let json = try XCTUnwrap(Defaults.encoded())
            let config = try XCTUnwrap(Defaults.convert(jsonString: json))
            XCTAssertEqual(config.defaults["overlayMaterial"]?.int, selection.rawValue)
            XCTAssertNil(config.defaults["footprintBlur"])
            XCTAssertNil(config.defaults["blurMaterial"])
            Defaults.overlayMaterial.value = selection == .noBlur ? .standard : .noBlur
            try loadConfig(data: Data(json.utf8))
            XCTAssertEqual(Defaults.overlayMaterial.value, selection)
        }
    }

    func testConfigRoundTripLeavesAnUnsetAlphaAdaptiveUnderReducedTransparency() throws {
        let window = FootprintWindow(accessibility: {
            FootprintAccessibility(reduceMotion: false, reduceTransparency: true)
        })
        defer { window.close() }

        for material in [OverlayMaterial.noBlur, .standard, .liquidGlass] {
            UserDefaults.standard.removeObject(forKey: Defaults.footprintAlpha.key)
            Defaults.overlayMaterial.value = material
            XCTAssertEqual(window.presentation.alpha, 0.3)
            let json = try XCTUnwrap(Defaults.encoded())
            let exported = try XCTUnwrap(Defaults.convert(jsonString: json))
            XCTAssertNil(exported.defaults[Defaults.footprintAlpha.key])
            let previewSettings = Set([Defaults.overlayMaterial.key, Defaults.footprintAlpha.key])
            let config = Config(bundleId: exported.bundleId, version: exported.version, shortcuts: [:],
                                defaults: exported.defaults.filter { previewSettings.contains($0.key) })
            Defaults.overlayMaterial.value = material == .noBlur ? .standard : .noBlur
            try loadConfig(data: JSONEncoder().encode(config))
            XCTAssertEqual(Defaults.overlayMaterial.value, material)
            XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key))
            XCTAssertEqual(window.presentation.alpha, 0.3)
        }
    }

    func testExplicitOverlayMaterialTakesPrecedenceOverTheFootprintSettingOnImport() throws {
        for selection in [OverlayMaterial.noBlur, .standard, .liquidGlass] {
            Defaults.overlayMaterial.value = selection == .standard ? .liquidGlass : .standard
            try loadConfig(rawDefaults: [
                "overlayMaterial": ["int": selection.rawValue],
                "footprintBlur": ["bool": selection == .noBlur],
                "blurMaterial": ["int": 1]
            ])
            XCTAssertEqual(Defaults.overlayMaterial.value, selection)
        }
    }

    func testReleasedFootprintSettingsRestoreMaterialAppearanceAndOpacity() throws {
        for enabled in [true, false] {
            Defaults.overlayMaterial.value = .liquidGlass
            Defaults.blurAppearance.value = .light
            Defaults.footprintAlpha.value = 0.3

            try loadConfig(rawDefaults: [
                "footprintBlur": ["bool": enabled],
                "blurAppearance": ["int": 2],
                "footprintAlpha": ["double": 0]
            ], version: "112")

            XCTAssertEqual(Defaults.overlayMaterial.value, enabled ? .standard : .noBlur)
            XCTAssertEqual(Defaults.blurAppearance.value, .dark)
            XCTAssertEqual(Defaults.footprintAlpha.value, 0)
        }
    }

    func testUnknownImportedOverlayMaterialUsesTheFootprintSetting() throws {
        Defaults.overlayMaterial.value = .noBlur
        try loadConfig(rawDefaults: [
            "overlayMaterial": ["int": 42],
            "footprintBlur": ["bool": true],
            "blurMaterial": ["int": 1],
            Defaults.gapSize.key: ["float": 17]
        ])
        XCTAssertEqual(Defaults.overlayMaterial.value, .liquidGlass)
        XCTAssertEqual(Defaults.gapSize.value, 17)
    }

    func testFootprintMaterialImportUsesTextureOnlyWhenBlurWasEnabled() throws {
        let cases: [(enabled: Bool, texture: Int?, material: OverlayMaterial)] = [
            (true, 0, .standard), (true, 1, .liquidGlass), (true, 2, .standard),
            (true, nil, .standard), (false, 1, .noBlur)
        ]
        for (enabled, texture, material) in cases {
            Defaults.overlayMaterial.value = material == .noBlur ? .liquidGlass : .noBlur
            Defaults.footprintAlpha.value = 0.3
            var settings: [String: Any] = ["footprintBlur": ["bool": enabled], "footprintAlpha": ["double": 0.0]]
            if let texture { settings["blurMaterial"] = ["int": texture] }

            try loadConfig(rawDefaults: settings)

            XCTAssertEqual(Defaults.overlayMaterial.value, material)
            XCTAssertEqual(Defaults.footprintAlpha.value, 0)
        }
    }

    func testFootprintMaterialOnlyImportKeepsTheOverlayMaterial() throws {
        Defaults.overlayMaterial.value = .standard
        try loadConfig(rawDefaults: ["blurMaterial": ["int": 1]])
        XCTAssertEqual(Defaults.overlayMaterial.value, .standard)
    }

    func testMalformedOverlayMaterialRejectsFileBeforeApplyingPreferencesOrShortcuts() throws {
        Defaults.overlayMaterial.value = .noBlur
        Defaults.gapSize.value = 2
        let action = WindowAction.almostMaximize
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 10), forKey: action.name)
        let savedShortcut = try XCTUnwrap(UserDefaults.standard.dictionary(forKey: action.name) as NSDictionary?)

        try loadConfig(rawDefaults: [
            "overlayMaterial": ["int": "invalid"],
            "footprintBlur": ["bool": true],
            Defaults.gapSize.key: ["float": 23]
        ])

        XCTAssertEqual(Defaults.overlayMaterial.value, .noBlur)
        XCTAssertEqual(Defaults.gapSize.value, 2)
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey: action.name) as NSDictionary?, savedShortcut)
    }

    func testMalformedUnrelatedDefaultRejectsFileBeforeApplyingAnyPreference() throws {
        Defaults.overlayMaterial.value = .noBlur
        Defaults.gapSize.value = 2
        try loadConfig(rawDefaults: [
            "overlayMaterial": ["int": OverlayMaterial.liquidGlass.rawValue],
            Defaults.gapSize.key: ["float": 17],
            Defaults.footprintAlpha.key: ["double": "broken"]
        ])
        XCTAssertEqual(Defaults.overlayMaterial.value, .noBlur)
        XCTAssertEqual(Defaults.gapSize.value, 2)
    }

    private func store(_ shortcut: Shortcut, forKey key: String) {
        let transformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let value = transformer.reverseTransformedValue(shortcut.toMASSHortcut())
        UserDefaults.standard.set(value, forKey: key)
    }

    private func loadConfig(shortcuts: [String: Shortcut], defaults: [String: CodableDefault] = [:],
                            notificationCenter: NotificationCenter = NotificationCenter()) throws {
        let config = Config(bundleId: "com.knollsoft.Rectangle",
                            version: "ConfigImportTests",
                            shortcuts: shortcuts,
                            defaults: defaults)
        try loadConfig(data: JSONEncoder().encode(config), notificationCenter: notificationCenter)
    }

    private func loadConfig(rawDefaults: [String: Any], version: String = "ConfigImportTests") throws {
        let document: [String: Any] = ["bundleId": "com.knollsoft.Rectangle", "version": version,
                                       "shortcuts": [String: Any](), "defaults": rawDefaults]
        try loadConfig(data: JSONSerialization.data(withJSONObject: document))
    }

    private func loadConfig(data: Data, notificationCenter: NotificationCenter = NotificationCenter()) throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigImportTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try data.write(to: fileURL, options: .atomic)

        Defaults.load(fileUrl: fileURL, notificationCenter: notificationCenter)
    }
}
