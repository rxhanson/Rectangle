/// CustomLayoutTests.swift
///
/// M1 unit tests for the custom-layout model + store (Divvy-2).

import XCTest
import MASShortcut
@testable import Rectangle

// MARK: - Pixel mapping over a synthetic display matrix

class NormalizedRectMappingTests: XCTestCase {

    /// Synthetic visibleFrames standing in for the §3.4 display matrix (no real displays).
    private let frames: [(String, CGRect)] = [
        ("primary",            CGRect(x: 0,     y: 0,  width: 1920, height: 1080)),
        ("secondary +offset",  CGRect(x: 1920,  y: 0,  width: 1440, height: 900)),
        ("secondary -origin",  CGRect(x: -1440, y: 0,  width: 1440, height: 900)),
        ("notched/menu-bar",   CGRect(x: 0,     y: 25, width: 1512, height: 930)),
        ("dock inset",         CGRect(x: 0,     y: 70, width: 1920, height: 1010)),
    ]

    func testFullScreenEqualsVisibleFrame() {
        for (name, f) in frames {
            let r = NormalizedRect(x: 0, y: 0, w: 1, h: 1).pixelRect(in: f)
            XCTAssertEqual(r, f, "full-screen should equal the visibleFrame on \(name)")
        }
    }

    func testLeftRightHalvesAbutNoGapOrOverlap() {
        for (name, f) in frames {
            let left = NormalizedRect(x: 0, y: 0, w: 0.5, h: 1).pixelRect(in: f)
            let right = NormalizedRect(x: 0.5, y: 0, w: 0.5, h: 1).pixelRect(in: f)
            XCTAssertEqual(left.maxX, right.minX, "halves must share the seam on \(name)")
            XCTAssertEqual(left.minX, f.minX, "left starts at frame minX on \(name)")
            XCTAssertEqual(right.maxX, f.maxX, "right ends at frame maxX on \(name)")
        }
    }

    func testSixtyFortyTilesExactly() {
        for (name, f) in frames {
            let left = NormalizedRect(x: 0, y: 0, w: 0.6, h: 1).pixelRect(in: f)
            let right = NormalizedRect(x: 0.6, y: 0, w: 0.4, h: 1).pixelRect(in: f)
            XCTAssertEqual(left.maxX, right.minX, "60/40 share the seam on \(name)")
            XCTAssertEqual(left.width + right.width, f.width, "60/40 widths sum to frame width on \(name)")
        }
    }

    func testThirdsTileWithoutSeams() {
        for (name, f) in frames {
            let t0 = NormalizedRect(x: 0,       y: 0, w: 1.0/3, h: 1).pixelRect(in: f)
            let t1 = NormalizedRect(x: 1.0/3,   y: 0, w: 1.0/3, h: 1).pixelRect(in: f)
            let t2 = NormalizedRect(x: 2.0/3,   y: 0, w: 1.0/3, h: 1).pixelRect(in: f)
            XCTAssertEqual(t0.minX, f.minX, name)
            XCTAssertEqual(t0.maxX, t1.minX, "thirds seam 0-1 on \(name)")
            XCTAssertEqual(t1.maxX, t2.minX, "thirds seam 1-2 on \(name)")
            XCTAssertEqual(t2.maxX, f.maxX, "thirds end at frame maxX on \(name)")
        }
    }

    func testTopHalfIsUpperBottomHalfIsLower() {
        for (name, f) in frames {
            let top = NormalizedRect(x: 0, y: 0, w: 1, h: 0.5).pixelRect(in: f)
            let bottom = NormalizedRect(x: 0, y: 0.5, w: 1, h: 0.5).pixelRect(in: f)
            // AppKit bottom-left: the upper half has the LARGER origin.y.
            XCTAssertGreaterThan(top.origin.y, bottom.origin.y, "top half is upper on \(name)")
            XCTAssertEqual(bottom.origin.y, f.minY, "bottom half sits at frame minY on \(name)")
            XCTAssertEqual(top.maxY, f.maxY, "top half reaches frame maxY on \(name)")
            XCTAssertEqual(top.minY, bottom.maxY, "top/bottom share the horizontal seam on \(name)")
        }
    }

    func testOutputsAreIntegerAndWithinFrame() {
        for (name, f) in frames {
            for nr in [NormalizedRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
                       NormalizedRect(x: 0, y: 0, w: 1, h: 1),
                       NormalizedRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5)] {
                let r = nr.pixelRect(in: f)
                XCTAssertEqual(r.minX, r.minX.rounded(), "integer x on \(name)")
                XCTAssertEqual(r.minY, r.minY.rounded(), "integer y on \(name)")
                XCTAssertEqual(r.width, r.width.rounded(), "integer w on \(name)")
                XCTAssertEqual(r.height, r.height.rounded(), "integer h on \(name)")
                XCTAssertGreaterThanOrEqual(r.minX, f.minX - 0.5, name)
                XCTAssertLessThanOrEqual(r.maxX, f.maxX + 0.5, name)
                XCTAssertGreaterThanOrEqual(r.minY, f.minY - 0.5, name)
                XCTAssertLessThanOrEqual(r.maxY, f.maxY + 0.5, name)
            }
        }
    }

    func testOffOriginPreservesOffset() {
        let f = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let r = NormalizedRect(x: 0, y: 0, w: 0.5, h: 1).pixelRect(in: f)
        XCTAssertEqual(r.minX, 1920)
        XCTAssertEqual(r.width, 720)
    }
}

// MARK: - NormalizedRect validation

class NormalizedRectValidationTests: XCTestCase {

    func testValidRects() {
        XCTAssertTrue(NormalizedRect(x: 0, y: 0, w: 1, h: 1).isValid)
        XCTAssertTrue(NormalizedRect(x: 0.5, y: 0, w: 0.5, h: 1).isValid)
        XCTAssertTrue(NormalizedRect(x: 0.1, y: 0.1, w: 0.8, h: 0.8).isValid)
    }

    func testInvalidRects() {
        XCTAssertFalse(NormalizedRect(x: -0.1, y: 0, w: 0.5, h: 1).isValid, "negative x")
        XCTAssertFalse(NormalizedRect(x: 0.6, y: 0, w: 0.5, h: 1).isValid, "x+w > 1")
        XCTAssertFalse(NormalizedRect(x: 0, y: 0, w: 0, h: 1).isValid, "zero width")
        XCTAssertFalse(NormalizedRect(x: 0, y: 0, w: 1, h: 0).isValid, "zero height")
        XCTAssertFalse(NormalizedRect(x: .nan, y: 0, w: 1, h: 1).isValid, "NaN")
        XCTAssertFalse(NormalizedRect(x: 0, y: 0, w: .infinity, h: 1).isValid, "inf")
    }

    func testClampedProducesValid() {
        XCTAssertTrue(NormalizedRect(x: 1.5, y: 0, w: 0.5, h: 1).clamped().isValid)
        XCTAssertTrue(NormalizedRect(x: -1, y: -1, w: 5, h: 5).clamped().isValid)
        XCTAssertTrue(NormalizedRect(x: .nan, y: 0, w: .infinity, h: 1).clamped().isValid)
        XCTAssertTrue(NormalizedRect(x: 0, y: 0, w: 0, h: 0).clamped().isValid)
    }
}

// MARK: - HotkeyData serialization

class HotkeyDataTests: XCTestCase {

    func testMASShortcutRoundTrip() {
        let s = MASShortcut(keyCode: 124, modifierFlags: [.command, .shift])
        let hk = HotkeyData(s)
        XCTAssertEqual(hk.keyCode, s.keyCode)
        XCTAssertEqual(hk.modifierFlags, s.modifierFlags.rawValue)
        let back = hk.toMASShortcut()
        XCTAssertEqual(back.keyCode, s.keyCode)
        XCTAssertEqual(back.modifierFlags, s.modifierFlags)
    }

    func testJSONRoundTrip() throws {
        let hk = HotkeyData(keyCode: 40, modifierFlags: 1_048_576)
        let data = try JSONEncoder().encode(hk)
        let decoded = try JSONDecoder().decode(HotkeyData.self, from: data)
        XCTAssertEqual(decoded, hk)
    }
}

// MARK: - Store CRUD + persistence + robustness

class CustomLayoutStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.perg593.chiva.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func layout(_ name: String = "L", _ id: UUID = UUID()) -> CustomLayout {
        CustomLayout(id: id, name: name, rect: NormalizedRect(x: 0, y: 0, w: 0.5, h: 1))
    }

    func testAddUpdateDeleteSurviveReload() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let id = UUID()
        XCTAssertTrue(store.add(layout("first", id)))
        XCTAssertEqual(store.layouts.count, 1)

        var l = store.layout(id: id)!
        l.name = "renamed"
        XCTAssertTrue(store.update(l))
        XCTAssertTrue(store.setHotkey(HotkeyData(keyCode: 1, modifierFlags: 256), for: id))

        // New store instance on the same suite must see the persisted state.
        let reloaded = CustomLayoutStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.layouts.count, 1)
        XCTAssertEqual(reloaded.layout(id: id)?.name, "renamed")
        XCTAssertEqual(reloaded.layout(id: id)?.hotkey, HotkeyData(keyCode: 1, modifierFlags: 256))

        XCTAssertTrue(reloaded.delete(id: id))
        XCTAssertEqual(CustomLayoutStore(userDefaults: defaults).layouts.count, 0)
    }

    func testAbsentIdAndDuplicateIdReturnFalse() {
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertFalse(store.update(layout("x")), "update absent id")
        XCTAssertFalse(store.delete(id: UUID()), "delete absent id")
        XCTAssertFalse(store.setHotkey(nil, for: UUID()), "setHotkey absent id")
        let id = UUID()
        XCTAssertTrue(store.add(layout("a", id)))
        XCTAssertFalse(store.add(layout("b", id)), "duplicate id rejected")
        XCTAssertEqual(store.layouts.count, 1)
    }

    func testInvalidRectRejectedByAdd() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let bad = CustomLayout(name: "bad", rect: NormalizedRect(x: 0.6, y: 0, w: 0.5, h: 1))
        XCTAssertFalse(store.add(bad))
        XCTAssertEqual(store.layouts.count, 0)
    }

    func testPersistedSchemaVersionIsCurrent() throws {
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertTrue(store.add(layout()))
        let data = defaults.data(forKey: CustomLayoutStore.defaultsKey)!
        let env = try JSONDecoder().decode(CustomLayoutsEnvelope.self, from: data)
        XCTAssertEqual(env.schemaVersion, CustomLayoutStore.currentSchemaVersion)
    }

    func testNotificationFiresOnSuccessNotOnNoOp() {
        let store = CustomLayoutStore(userDefaults: defaults)
        let success = expectation(forNotification: .customLayoutsChanged, object: nil)
        XCTAssertTrue(store.add(layout()))
        wait(for: [success], timeout: 1)

        let noop = expectation(forNotification: .customLayoutsChanged, object: nil)
        noop.isInverted = true
        XCTAssertFalse(store.delete(id: UUID()))  // no-op
        wait(for: [noop], timeout: 0.3)
    }

    // MARK: load tolerance vs future schema

    func testCorruptJSONLoadsEmptyAndPreservesBytes() {
        let bytes = Data("not json at all".utf8)
        defaults.set(bytes, forKey: CustomLayoutStore.defaultsKey)
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertEqual(store.layouts.count, 0)
        XCTAssertFalse(store.isReadOnlyFutureSchema)
        XCTAssertEqual(defaults.data(forKey: CustomLayoutStore.defaultsKey), bytes, "bad bytes not overwritten")
    }

    func testTolerantLoadDropsInvalidKeepsValid() {
        // One valid + one invalid (x+w>1) layout in the stored envelope.
        let json = """
        {"schemaVersion":1,"layouts":[
          {"id":"\(UUID().uuidString)","name":"ok","rect":{"x":0,"y":0,"w":0.5,"h":1}},
          {"id":"\(UUID().uuidString)","name":"bad","rect":{"x":0.8,"y":0,"w":0.5,"h":1}}
        ]}
        """
        defaults.set(Data(json.utf8), forKey: CustomLayoutStore.defaultsKey)
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertEqual(store.layouts.count, 1)
        XCTAssertEqual(store.layouts.first?.name, "ok")
    }

    func testFutureSchemaIsReadOnlyAndNeverDowngrades() {
        let valid = """
        {"schemaVersion":\(CustomLayoutStore.currentSchemaVersion + 1),"layouts":[
          {"id":"\(UUID().uuidString)","name":"future","rect":{"x":0,"y":0,"w":1,"h":1}}
        ]}
        """
        let bytes = Data(valid.utf8)
        defaults.set(bytes, forKey: CustomLayoutStore.defaultsKey)
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertTrue(store.isReadOnlyFutureSchema)
        XCTAssertFalse(store.add(layout()), "mutator no-op while read-only")
        XCTAssertFalse(store.delete(id: UUID()))
        XCTAssertEqual(defaults.data(forKey: CustomLayoutStore.defaultsKey), bytes, "future data not downgraded")
    }

    func testFutureSchemaWithUndecodableLayoutsStillReadOnly() {
        // schemaVersion is readable, but layouts shape is alien to v1.
        let future = """
        {"schemaVersion":\(CustomLayoutStore.currentSchemaVersion + 1),"layouts":[{"totallyDifferent":true}]}
        """
        let bytes = Data(future.utf8)
        defaults.set(bytes, forKey: CustomLayoutStore.defaultsKey)
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertTrue(store.isReadOnlyFutureSchema, "header-first decode drives the read-only gate")
        XCTAssertFalse(store.add(layout()))
        XCTAssertEqual(defaults.data(forKey: CustomLayoutStore.defaultsKey), bytes, "not overwritten")
    }

    // MARK: import strictness (atomic)

    func testImportHappyPathReplacesAll() {
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertTrue(store.add(layout("old")))
        let payload = store.exportJSON()  // round-trip our own export
        // build a fresh payload of 2 layouts
        let env = CustomLayoutsEnvelope(schemaVersion: 1, layouts: [layout("a"), layout("b")])
        let data = try! JSONEncoder().encode(env)
        _ = payload
        let result = store.importJSON(data)
        XCTAssertEqual(result, .success(2))
        XCTAssertEqual(store.layouts.count, 2)
        XCTAssertEqual(CustomLayoutStore(userDefaults: defaults).layouts.count, 2, "persisted")
    }

    func testImportFailuresLeaveStoreUnchanged() {
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertTrue(store.add(layout("keep")))
        let before = defaults.data(forKey: CustomLayoutStore.defaultsKey)
        let snapshot = store.layouts

        func assertUnchanged(_ r: Result<Int, CustomLayoutImportError>, _ expected: CustomLayoutImportError) {
            XCTAssertEqual(r, .failure(expected))
            XCTAssertEqual(store.layouts, snapshot, "in-memory unchanged on \(expected)")
            XCTAssertEqual(defaults.data(forKey: CustomLayoutStore.defaultsKey), before, "defaults unchanged on \(expected)")
        }

        assertUnchanged(store.importJSON(Data("garbage".utf8)), .decode)

        let future = CustomLayoutsEnvelope(schemaVersion: 99, layouts: [])
        assertUnchanged(store.importJSON(try! JSONEncoder().encode(future)), .unsupportedSchema)

        let invalid = CustomLayoutsEnvelope(schemaVersion: 1,
            layouts: [CustomLayout(name: "bad", rect: NormalizedRect(x: 0.9, y: 0, w: 0.5, h: 1))])
        assertUnchanged(store.importJSON(try! JSONEncoder().encode(invalid)), .invalidLayout)

        let dupId = UUID()
        let dup = CustomLayoutsEnvelope(schemaVersion: 1, layouts: [layout("a", dupId), layout("b", dupId)])
        assertUnchanged(store.importJSON(try! JSONEncoder().encode(dup)), .duplicateId)
    }

    func testImportClearsReadOnlyFutureSchema() {
        let future = "{\"schemaVersion\":\(CustomLayoutStore.currentSchemaVersion + 1),\"layouts\":[]}"
        defaults.set(Data(future.utf8), forKey: CustomLayoutStore.defaultsKey)
        let store = CustomLayoutStore(userDefaults: defaults)
        XCTAssertTrue(store.isReadOnlyFutureSchema)
        let env = CustomLayoutsEnvelope(schemaVersion: 1, layouts: [layout("recovered")])
        XCTAssertEqual(store.importJSON(try! JSONEncoder().encode(env)), .success(1))
        XCTAssertFalse(store.isReadOnlyFutureSchema)
        XCTAssertTrue(store.add(layout("now-writable")))
    }
}
