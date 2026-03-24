//
//  RectangleTests.swift
//  RectangleTests
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import XCTest
@testable import Rectangle

class RectangleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Defaults.installVersion.value = nil
        UserDefaults.standard.removeObject(forKey: "alternateDefaultShortcuts")
    }

    override func tearDown() {
        Defaults.installVersion.value = nil
        UserDefaults.standard.removeObject(forKey: "alternateDefaultShortcuts")
        super.tearDown()
    }

    // MARK: - Twelfths default shortcuts

    let twelfthsMapping: [(WindowAction, Int)] = [
        (.topLeftTwelfth,          kVK_ANSI_1),
        (.topCenterLeftTwelfth,    kVK_ANSI_2),
        (.topCenterRightTwelfth,   kVK_ANSI_3),
        (.topRightTwelfth,         kVK_ANSI_4),
        (.middleLeftTwelfth,       kVK_ANSI_5),
        (.middleCenterLeftTwelfth, kVK_ANSI_6),
        (.middleCenterRightTwelfth,kVK_ANSI_7),
        (.middleRightTwelfth,      kVK_ANSI_8),
        (.bottomLeftTwelfth,       kVK_ANSI_9),
        (.bottomCenterLeftTwelfth, kVK_ANSI_0),
        (.bottomCenterRightTwelfth,kVK_ANSI_Q),
        (.bottomRightTwelfth,      kVK_ANSI_W),
    ]

    func testTwelfthsShortcuts_newInstall_returnsCorrectShortcuts() {
        Defaults.installVersion.value = "95"
        for (action, expectedKeyCode) in twelfthsMapping {
            let shortcut = action.alternateDefault
            XCTAssertNotNil(shortcut, "\(action.name) should have a default shortcut for new installs")
            XCTAssertEqual(shortcut?.keyCode, UInt(expectedKeyCode),
                           "\(action.name) should map to keyCode \(expectedKeyCode)")
            XCTAssertEqual(shortcut?.modifierFlags,
                           NSEvent.ModifierFlags([.control, .option]).rawValue,
                           "\(action.name) should use ctrl+opt modifiers")
        }
    }

    func testTwelfthsShortcuts_oldInstall_returnsNil() {
        Defaults.installVersion.value = "50"
        for (action, _) in twelfthsMapping {
            XCTAssertNil(action.alternateDefault,
                         "\(action.name) should have no default shortcut for installs before v0.95")
        }
    }

    func testTwelfthsShortcuts_noInstallVersion_returnsNil() {
        // installVersion not set — simulates corrupted or legacy state
        for (action, _) in twelfthsMapping {
            XCTAssertNil(action.alternateDefault,
                         "\(action.name) should have no default shortcut when installVersion is absent")
        }
    }

    func testAlternateDefaults_noConflicts() {
        // All non-nil alternateDefault shortcuts must be unique (no two actions share a key combo)
        Defaults.installVersion.value = "95"
        var seen = [String: String]()
        for action in WindowAction.active {
            guard let shortcut = action.alternateDefault else { continue }
            let key = "\(shortcut.modifierFlags)-\(shortcut.keyCode)"
            if let existing = seen[key] {
                XCTFail("Shortcut conflict: \(action.name) and \(existing) both map to modifier=\(shortcut.modifierFlags) key=\(shortcut.keyCode)")
            }
            seen[key] = action.name
        }
    }

    func testAlternateDefaults_existingShortcutsUnchanged() {
        // Regression: existing well-known shortcuts must not be affected by the twelfths addition
        Defaults.installVersion.value = "95"
        let ctrlOpt = NSEvent.ModifierFlags([.control, .option]).rawValue
        let ctrlOptCmd = NSEvent.ModifierFlags([.control, .option, .command]).rawValue

        XCTAssertEqual(WindowAction.firstThird.alternateDefault?.keyCode, UInt(kVK_ANSI_D))
        XCTAssertEqual(WindowAction.firstThird.alternateDefault?.modifierFlags, ctrlOpt)
        XCTAssertEqual(WindowAction.centerThird.alternateDefault?.keyCode, UInt(kVK_ANSI_F))
        XCTAssertEqual(WindowAction.lastThird.alternateDefault?.keyCode, UInt(kVK_ANSI_G))
        XCTAssertEqual(WindowAction.leftHalf.alternateDefault?.keyCode, UInt(kVK_LeftArrow))
        XCTAssertEqual(WindowAction.leftHalf.alternateDefault?.modifierFlags, ctrlOpt)
        XCTAssertEqual(WindowAction.maximize.alternateDefault?.keyCode, UInt(kVK_Return))
        XCTAssertEqual(WindowAction.nextDisplay.alternateDefault?.modifierFlags, ctrlOptCmd)
    }

}
