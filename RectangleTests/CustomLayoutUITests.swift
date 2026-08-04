/// CustomLayoutUITests.swift
///
/// M3 unit tests for the non-UI logic: percent↔NormalizedRect, the shared conflict
/// helpers, the record-time validator, and the binding-status text. The window UI
/// itself is verified by the manual run smoke test.

import XCTest
import MASShortcut
@testable import Rectangle

final class CustomLayoutPercentTests: XCTestCase {
    func testValidPercents() {
        let r = NormalizedRect.fromPercents(x: 0, y: 0, w: 50, h: 100)
        XCTAssertEqual(r, NormalizedRect(x: 0, y: 0, w: 0.5, h: 1))
        let p = r!.percents
        XCTAssertEqual(p.x, 0); XCTAssertEqual(p.y, 0); XCTAssertEqual(p.w, 50); XCTAssertEqual(p.h, 100)
    }
    func testInvalidPercentsRejected() {
        XCTAssertNil(NormalizedRect.fromPercents(x: 80, y: 0, w: 50, h: 100), "x+w > 100")
        XCTAssertNil(NormalizedRect.fromPercents(x: 150, y: 0, w: 10, h: 10), "x out of range")
        XCTAssertNil(NormalizedRect.fromPercents(x: 0, y: 0, w: 0, h: 100), "zero width")
    }
}

final class CustomLayoutConflictHelperTests: XCTestCase {
    private var suiteName: String!
    private var conflicts: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.perg593.chiva.m3conf.\(UUID().uuidString)"
        conflicts = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() { conflicts.removePersistentDomain(forName: suiteName); super.tearDown() }

    private func chord(_ k: Int, _ f: NSEvent.ModifierFlags = [.command, .control, .option]) -> MASShortcut {
        MASShortcut(keyCode: k, modifierFlags: f)
    }
    private func injectWindowAction(_ s: MASShortcut, _ a: WindowAction) {
        let t = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        conflicts.set(t.reverseTransformedValue(s), forKey: a.name)
    }
    private func layout(_ id: UUID, _ s: MASShortcut?) -> CustomLayout {
        CustomLayout(id: id, name: "L", rect: NormalizedRect(x: 0, y: 0, w: 0.5, h: 1), hotkey: s.map { HotkeyData($0) })
    }

    func testWindowActionName() {
        injectWindowAction(chord(123, [.control, .option]), .leftHalf)
        XCTAssertEqual(CustomLayoutConflict.windowActionName(for: chord(123, [.control, .option]), in: conflicts),
                       WindowAction.leftHalf.name)
        XCTAssertNil(CustomLayoutConflict.windowActionName(for: chord(96), in: conflicts))
    }

    func testCustomLayoutIdFirstMatchInListOrder() {
        let a = UUID(), b = UUID()
        let layouts = [layout(a, chord(96)), layout(b, chord(96))]   // both same chord
        XCTAssertEqual(CustomLayoutConflict.customLayoutId(for: chord(96), in: layouts), a, "first in list order")
        XCTAssertNil(CustomLayoutConflict.customLayoutId(for: chord(99), in: layouts))
    }

    func testValidator() {
        injectWindowAction(chord(123, [.control, .option]), .leftHalf)
        let editedId = UUID(), otherId = UUID()
        let editedChord = chord(96)
        let all = [layout(editedId, editedChord), layout(otherId, chord(97))]
        let validator = CustomLayoutShortcutValidator(
            conflictDefaults: conflicts,
            otherLayouts: { all.filter { $0.id != editedId } })

        XCTAssertTrue(validator.isShortcutValid(chord(98)), "free, base-valid chord is valid")
        XCTAssertTrue(validator.isShortcutValid(editedChord), "re-recording the edited row's own chord is allowed")
        XCTAssertFalse(validator.isShortcutValid(chord(97)), "matches another layout → invalid")
        XCTAssertFalse(validator.isShortcutValid(chord(123, [.control, .option])), "matches a WindowAction → invalid")
        XCTAssertFalse(validator.isShortcutValid(MASShortcut(keyCode: 0, modifierFlags: [])),
                       "base-invalid (no modifier) chord still rejected via super")
    }
}

final class CustomLayoutStatusTextTests: XCTestCase {
    func testStatusText() {
        let id = UUID()
        let resolver: (UUID) -> String? = { $0 == id ? "First" : nil }
        XCTAssertEqual(CustomLayoutShortcutManager.BindOutcome.registered.statusText(nameForId: resolver), "Active")
        XCTAssertEqual(CustomLayoutShortcutManager.BindOutcome.conflictWindowAction("leftHalf").statusText(nameForId: resolver),
                       "Conflicts with leftHalf")
        XCTAssertEqual(CustomLayoutShortcutManager.BindOutcome.conflictCustomLayout(id).statusText(nameForId: resolver),
                       "Conflicts with First")
        XCTAssertEqual(CustomLayoutShortcutManager.BindOutcome.monitorRegistrationFailed.statusText(nameForId: resolver),
                       "Registration failed")
        XCTAssertEqual(CustomLayoutShortcutManager.BindOutcome.noHotkey.statusText(nameForId: resolver), "Unbound")
        XCTAssertEqual(CustomLayoutShortcutManager.BindOutcome.suppressed.statusText(nameForId: resolver), "Paused")
    }

    func testDefaultNewLayoutIsValid() {
        let l = CustomLayout(name: "New Layout", rect: NormalizedRect(x: 0, y: 0, w: 0.5, h: 1))
        XCTAssertTrue(l.rect.isValid)
        XCTAssertNil(l.hotkey)
    }
}
