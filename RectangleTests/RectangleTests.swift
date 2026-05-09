//
//  RectangleTests.swift
//  RectangleTests
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import MASShortcut
import XCTest
@testable import Rectangle

class RectangleTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

class ShortcutCycleTests: XCTestCase {

    private func shortcut(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: flags)
    }

    func testUniqueShortcutsProduceSingletonGroups() {
        let groups = ShortcutCycle.groups(
            actions: [.centerHalf, .centerThird],
            shortcutsByAction: [
                .centerHalf: shortcut(1, [.option, .command]),
                .centerThird: shortcut(2, [.option, .command])
            ]
        )

        XCTAssertEqual(groups.map(\.actions), [[.centerHalf], [.centerThird]])
        XCTAssertFalse(groups.contains { $0.isCycle })
    }

    func testDuplicateShortcutsFollowWindowActionActiveOrder() {
        let groups = ShortcutCycle.groups(
            actions: WindowAction.active,
            shortcutsByAction: [
                .centerHalf: shortcut(1, [.option, .command]),
                .centerThird: shortcut(1, [.option, .command])
            ]
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.actions, [.centerHalf, .centerThird])
    }

    func testDuplicateShortcutStartsAtFirstActionWithoutPreviousAction() {
        let group = ShortcutCycle.Group(shortcut: shortcut(1, [.option, .command]), actions: [.centerHalf, .centerThird])

        XCTAssertEqual(group.action(after: nil), .centerHalf)
    }

    func testDuplicateShortcutSelectsNextActionAndWraps() {
        let group = ShortcutCycle.Group(shortcut: shortcut(1, [.option, .command]), actions: [.centerHalf, .centerThird])

        XCTAssertEqual(group.action(after: .centerHalf), .centerThird)
        XCTAssertEqual(group.action(after: .centerThird), .centerHalf)
    }

    func testDuplicateShortcutStartsAtFirstActionWhenPreviousActionIsOutsideGroup() {
        let group = ShortcutCycle.Group(shortcut: shortcut(1, [.option, .command]), actions: [.centerHalf, .centerThird])

        XCTAssertEqual(group.action(after: .maximize), .centerHalf)
    }

    func testStaleWindowHistoryIsIgnoredForCycleSelection() {
        let group = ShortcutCycle.Group(shortcut: shortcut(1, [.option, .command]), actions: [.centerHalf, .centerThird])
        let lastAction = RectangleAction(
            action: .centerHalf,
            subAction: nil,
            rect: CGRect(x: 0, y: 0, width: 500, height: 500),
            count: 1
        )

        let selectedAction = ShortcutCycle.action(
            in: group,
            lastAction: lastAction,
            currentWindowRect: CGRect(x: 20, y: 20, width: 500, height: 500)
        )

        XCTAssertEqual(selectedAction, .centerHalf)
    }

    func testDuplicateShortcutAssignmentsRemainReadableFromUserDefaults() {
        let suiteName = "ShortcutCycleTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let duplicatedShortcut = shortcut(1, [.option, .command])
        let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let shortcutDict = dictTransformer.reverseTransformedValue(duplicatedShortcut)
        userDefaults.setValue(shortcutDict, forKey: WindowAction.centerHalf.name)
        userDefaults.setValue(shortcutDict, forKey: WindowAction.centerThird.name)

        let shortcutsByAction = ShortcutCycle.shortcutsByAction(actions: [.centerHalf, .centerThird], userDefaults: userDefaults)
        let groups = ShortcutCycle.groups(actions: [.centerHalf, .centerThird], shortcutsByAction: shortcutsByAction)

        XCTAssertNotNil(ShortcutCycle.shortcut(for: .centerHalf, userDefaults: userDefaults))
        XCTAssertNotNil(ShortcutCycle.shortcut(for: .centerThird, userDefaults: userDefaults))
        XCTAssertEqual(groups.map(\.actions), [[.centerHalf, .centerThird]])
        XCTAssertEqual(groups.first?.representativeAction, .centerHalf)
    }
}

class TodoShortcutValidatorTests: XCTestCase {

    private func shortcut(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: flags)
    }

    private func save(_ shortcut: MASShortcut, forKey key: String, in userDefaults: UserDefaults) {
        let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let shortcutDict = dictTransformer.reverseTransformedValue(shortcut)
        userDefaults.set(shortcutDict, forKey: key)
    }

    private func userDefaultsSuite() -> (String, UserDefaults) {
        let suiteName = "TodoShortcutValidatorTests.\(UUID().uuidString)"
        return (suiteName, UserDefaults(suiteName: suiteName)!)
    }

    func testInvalidatesShortcutUsedByWindowActionWithoutAlreadyTakenError() {
        let (suiteName, userDefaults) = userDefaultsSuite()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let duplicateShortcut = shortcut(1, [.option, .command])
        save(duplicateShortcut, forKey: WindowAction.centerHalf.name, in: userDefaults)
        let validator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey, userDefaults: userDefaults)
        var explanation: NSString?

        let isTaken = validator.isShortcutAlreadyTaken(bySystem: duplicateShortcut, explanation: &explanation)

        XCTAssertFalse(validator.isShortcutValid(duplicateShortcut))
        XCTAssertFalse(isTaken)
        XCTAssertNil(explanation)
    }

    func testInvalidatesShortcutUsedByOtherTodoActionWithoutAlreadyTakenError() {
        let (suiteName, userDefaults) = userDefaultsSuite()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let duplicateShortcut = shortcut(1, [.option, .command])
        save(duplicateShortcut, forKey: TodoManager.reflowDefaultsKey, in: userDefaults)
        let validator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey, userDefaults: userDefaults)
        var explanation: NSString?

        let isTaken = validator.isShortcutAlreadyTaken(bySystem: duplicateShortcut, explanation: &explanation)

        XCTAssertFalse(validator.isShortcutValid(duplicateShortcut))
        XCTAssertFalse(isTaken)
        XCTAssertNil(explanation)
    }

    func testAllowsExistingShortcutForSameTodoAction() {
        let (suiteName, userDefaults) = userDefaultsSuite()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let existingShortcut = shortcut(1, [.option, .command])
        save(existingShortcut, forKey: TodoManager.toggleDefaultsKey, in: userDefaults)
        let validator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey, userDefaults: userDefaults)

        XCTAssertTrue(validator.isShortcutValid(existingShortcut))
        XCTAssertFalse(validator.isShortcutAlreadyTaken(bySystem: existingShortcut, explanation: nil))
    }
}
