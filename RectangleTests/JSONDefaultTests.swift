/// JSONDefaultTests.swift

import XCTest
@testable import Rectangle

class JSONDefaultTests: XCTestCase {

    /// `systemWideMouseDownApps` / `doubleClickToolBarIgnoredApps` are only customizable via
    /// `defaults write` (there is no in-app UI). They are declared through
    /// `JSONDefault.init(key:defaultValue:)`, which must honor a value the user persisted for the
    /// key and fall back to the default only when nothing is stored. These tests guard that contract
    /// using a dedicated test key against the real `UserDefaults.standard` suite `JSONDefault` reads.
    private static let testKey = "testJSONDefaultStoredValueRoundTrip"

    private func writeJSON<T: Encodable>(_ value: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(value)
        UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: key)
    }

    func testStoredValueIsHonoredOverDefault() throws {
        let key = Self.testKey
        let storedValue: Set<String> = ["com.example.customApp", "org.something.other"]
        let defaultValue: Set<String> = ["org.languagetool.desktop", "com.microsoft.teams2"]

        try writeJSON(storedValue, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let jsonDefault = JSONDefault<Set<String>>(key: key, defaultValue: defaultValue)
        XCTAssertEqual(jsonDefault.typedValue, storedValue)
    }

    func testMissingValueFallsBackToDefault() throws {
        let key = Self.testKey
        let defaultValue: Set<String> = ["org.languagetool.desktop", "com.microsoft.teams2"]

        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let jsonDefault = JSONDefault<Set<String>>(key: key, defaultValue: defaultValue)
        XCTAssertEqual(jsonDefault.typedValue, defaultValue)
    }

    func testInvalidJSONFallsBackToDefault() throws {
        let key = Self.testKey
        let defaultValue: Set<String> = ["org.languagetool.desktop", "com.microsoft.teams2"]

        UserDefaults.standard.set("not valid json", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let jsonDefault = JSONDefault<Set<String>>(key: key, defaultValue: defaultValue)
        XCTAssertEqual(jsonDefault.typedValue, defaultValue)
    }
}
