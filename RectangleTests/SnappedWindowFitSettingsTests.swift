import XCTest
@testable import Rectangle

final class SnappedWindowFitSettingsTests: XCTestCase {
    func testFitTogglePersistsAndExports() throws {
        let setting = Defaults.fitBesideSnappedWindows
        let savedValue = setting.enabled
        let savedObject = UserDefaults.standard.object(forKey: setting.key)
        defer {
            setting.enabled = savedValue
            UserDefaults.standard.set(savedObject, forKey: setting.key)
        }

        setting.enabled = false
        let model = BehaviorSettingsViewModel()
        XCTAssertFalse(model.fitBesideSnappedWindows)
        model.fitBesideSnappedWindows = true
        XCTAssertTrue(BehaviorSettingsViewModel().fitBesideSnappedWindows)

        let json = try XCTUnwrap(Defaults.encoded())
        let config = try XCTUnwrap(Defaults.convert(jsonString: json))
        let exported = try XCTUnwrap(config.defaults["fitBesideSnappedWindows"])
        XCTAssertEqual(exported.bool, true)

        setting.enabled = false
        setting.load(from: exported)
        XCTAssertTrue(setting.enabled)
    }
}
