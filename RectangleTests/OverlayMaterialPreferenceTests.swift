import XCTest
@testable import Rectangle

final class OverlayMaterialPreferenceTests: XCTestCase {
    private let canonical = "overlayMaterial"
    private let footprint = "footprintBlur"
    private let footprintMaterial = "blurMaterial"
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RectangleOverlayMaterialTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testUnconfiguredProfileCanBeReadExportedAndPartiallyImportedWithoutWriting() {
        let preference = OverlayMaterialPreference(defaults: defaults)
        preference.migrateFootprintSetting()
        XCTAssertEqual(preference.value, .noBlur)
        XCTAssertEqual(preference.toCodable().int, 2)

        preference.importSelection(from: [:])
        preference.importSelection(from: [canonical: CodableDefault(int: 14)])
        preference.load(from: CodableDefault(bool: true))

        XCTAssertNil(defaults.object(forKey: canonical))
        XCTAssertEqual(OverlayMaterialPreference(defaults: defaults).value, .noBlur)
        XCTAssertNil(defaults.object(forKey: canonical))
    }

    func testStoredFootprintSettingSelectsTheMatchingMaterial() {
        assertMigration([footprint: true], produces: .standard)
        assertMigration([footprint: false], produces: .noBlur)
        assertMigration([footprint: 1], produces: .standard)
        assertMigration([footprint: 0], produces: .noBlur)
    }

    func testStoredFootprintMaterialSelectsItsTextureWhenBlurIsOn() {
        assertMigration([footprint: true, footprintMaterial: 0], produces: .standard)
        assertMigration([footprint: true, footprintMaterial: 1], produces: .liquidGlass)
        assertMigration([footprint: true, footprintMaterial: 1.0], produces: .liquidGlass)
        assertMigration([footprint: true, footprintMaterial: Float(1)], produces: .liquidGlass)
        assertMigration([footprint: 1, footprintMaterial: 1], produces: .liquidGlass)
        assertMigration([footprint: false, footprintMaterial: 1], produces: .noBlur)
    }

    func testInvalidFootprintMaterialUsesStandardBlur() {
        for invalid in [true, 1.5, "1", -1, 2, 99] as [Any] {
            assertMigration([footprint: true, footprintMaterial: invalid], produces: .standard)
        }
    }

    func testInvalidStoredMaterialFallsBackToFootprintSetting() {
        assertMigration([canonical: true, footprint: true], produces: .standard)
        assertMigration([canonical: 99, footprint: false], produces: .noBlur)
    }

    func testSelectingMaterialReplacesAnInvalidStoredValue() {
        defaults.setPersistentDomain([canonical: true], forName: suiteName)
        let preference = OverlayMaterialPreference(defaults: defaults)
        XCTAssertEqual(preference.value, .noBlur)
        preference.value = .liquidGlass
        XCTAssertEqual(OverlayMaterialPreference(defaults: defaults).value, .liquidGlass)
    }

    func testStoredMaterialTakesPrecedenceAndResetsToNoBlur() {
        assertMigration([canonical: 1.0, footprint: false, footprintMaterial: 0], produces: .liquidGlass)
        for (raw, selection): (Int, OverlayMaterial) in [(0, .standard), (1, .liquidGlass), (2, .noBlur)] {
            assertMigration([canonical: raw, footprint: selection == .noBlur, footprintMaterial: 1], produces: selection)
            defaults.removeObject(forKey: canonical)
            let preference = OverlayMaterialPreference(defaults: defaults)
            preference.migrateFootprintSetting()
            XCTAssertEqual(preference.value, .noBlur)
            XCTAssertNil(defaults.object(forKey: canonical))
        }
    }

    func testStartupMigrationEstablishesMaterialBeforeImport() {
        defaults.set(true, forKey: footprint)
        let preference = OverlayMaterialPreference(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: canonical))

        preference.migrateFootprintSetting()
        XCTAssertEqual(preference.value, .standard)
        XCTAssertNil(defaults.object(forKey: footprint))

        preference.importSelection(from: [canonical: CodableDefault(int: OverlayMaterial.liquidGlass.rawValue)])
        preference.migrateFootprintSetting()
        XCTAssertEqual(preference.value, .liquidGlass)
    }

    func testPartialImportKeepsTheSavedMaterial() {
        let preference = OverlayMaterialPreference(defaults: defaults)
        preference.value = .liquidGlass
        preference.importSelection(from: [:])
        XCTAssertEqual(preference.value, .liquidGlass)
    }

    func testStoredFootprintMaterialAloneLeavesTheOverlayMaterialUnset() {
        defaults.set(1, forKey: footprintMaterial)
        let preference = OverlayMaterialPreference(defaults: defaults)
        preference.migrateFootprintSetting()

        XCTAssertEqual(preference.value, .noBlur)
        XCTAssertNil(defaults.object(forKey: canonical))
    }

    func testSystemFallbacksPreserveTheStoredSelection() {
        let preference = OverlayMaterialPreference(defaults: defaults)
        for selection: OverlayMaterial in [.noBlur, .standard, .liquidGlass] {
            preference.value = selection
            XCTAssertEqual(selection.effective(supportsLiquidGlass: true, reduceTransparency: false), selection)
            let legacy: OverlayMaterial = selection == .liquidGlass ? .standard : selection
            XCTAssertEqual(selection.effective(supportsLiquidGlass: false, reduceTransparency: false), legacy)
            for supported in [false, true] {
                XCTAssertEqual(selection.effective(supportsLiquidGlass: supported, reduceTransparency: true), .noBlur)
            }
            XCTAssertEqual(OverlayMaterialPreference(defaults: defaults).value, selection)
        }
    }

    private func assertMigration(_ entries: [String: Any], produces expected: OverlayMaterial,
                                 file: StaticString = #filePath, line: UInt = #line) {
        defaults.removePersistentDomain(forName: suiteName)
        for (key, value) in entries { defaults.set(value, forKey: key) }

        let preference = OverlayMaterialPreference(defaults: defaults)
        preference.migrateFootprintSetting()
        XCTAssertEqual(preference.value, expected, file: file, line: line)
        XCTAssertEqual(defaults.object(forKey: canonical) as? Int, expected.rawValue, file: file, line: line)
        XCTAssertNil(defaults.object(forKey: footprint), file: file, line: line)
        XCTAssertNil(defaults.object(forKey: footprintMaterial), file: file, line: line)
        XCTAssertEqual(OverlayMaterialPreference(defaults: defaults).value, expected, file: file, line: line)
    }
}
