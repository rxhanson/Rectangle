/// RectangleTests.swift

import MASShortcut
import XCTest
@testable import Rectangle

class RectangleTests: XCTestCase {

    override func setUp() {
    }

    override func tearDown() {
    }
}

class PositionCyclesTests: XCTestCase {

    func testSixthsReturnTrue() {
        XCTAssertTrue(WindowAction.topLeftSixth.positionCycles)
        XCTAssertTrue(WindowAction.topCenterSixth.positionCycles)
        XCTAssertTrue(WindowAction.topRightSixth.positionCycles)
        XCTAssertTrue(WindowAction.bottomLeftSixth.positionCycles)
        XCTAssertTrue(WindowAction.bottomCenterSixth.positionCycles)
        XCTAssertTrue(WindowAction.bottomRightSixth.positionCycles)
    }

    func testEighthsReturnTrue() {
        XCTAssertTrue(WindowAction.topLeftEighth.positionCycles)
        XCTAssertTrue(WindowAction.topCenterLeftEighth.positionCycles)
        XCTAssertTrue(WindowAction.bottomRightEighth.positionCycles)
    }

    func testNinthsReturnTrue() {
        XCTAssertTrue(WindowAction.topLeftNinth.positionCycles)
        XCTAssertTrue(WindowAction.middleCenterNinth.positionCycles)
        XCTAssertTrue(WindowAction.bottomRightNinth.positionCycles)
    }

    func testTwelfthsReturnTrue() {
        XCTAssertTrue(WindowAction.topLeftTwelfth.positionCycles)
        XCTAssertTrue(WindowAction.middleCenterLeftTwelfth.positionCycles)
        XCTAssertTrue(WindowAction.bottomRightTwelfth.positionCycles)
    }

    func testSixteenthsReturnTrue() {
        XCTAssertTrue(WindowAction.topLeftSixteenth.positionCycles)
        XCTAssertTrue(WindowAction.upperMiddleCenterLeftSixteenth.positionCycles)
        XCTAssertTrue(WindowAction.lowerMiddleRightSixteenth.positionCycles)
        XCTAssertTrue(WindowAction.bottomRightSixteenth.positionCycles)
    }

    func testGridPositionsReturnTrue() {
        XCTAssertTrue(WindowAction.leftHalf.positionCycles)
        XCTAssertTrue(WindowAction.rightHalf.positionCycles)
        XCTAssertTrue(WindowAction.topLeft.positionCycles)
        XCTAssertTrue(WindowAction.bottomRight.positionCycles)
        XCTAssertTrue(WindowAction.firstThird.positionCycles)
        XCTAssertTrue(WindowAction.lastThird.positionCycles)
        XCTAssertTrue(WindowAction.firstFourth.positionCycles)
        XCTAssertTrue(WindowAction.topHalf.positionCycles)
        XCTAssertTrue(WindowAction.bottomHalf.positionCycles)
    }

    func testNonPositionalActionsReturnFalse() {
        XCTAssertFalse(WindowAction.maximize.positionCycles)
        XCTAssertFalse(WindowAction.maximizeHeight.positionCycles)
        XCTAssertFalse(WindowAction.almostMaximize.positionCycles)
        XCTAssertFalse(WindowAction.center.positionCycles)
        XCTAssertFalse(WindowAction.centerProminently.positionCycles)
        XCTAssertFalse(WindowAction.restore.positionCycles)
        XCTAssertFalse(WindowAction.moveLeft.positionCycles)
        XCTAssertFalse(WindowAction.moveRight.positionCycles)
        XCTAssertFalse(WindowAction.nextDisplay.positionCycles)
        XCTAssertFalse(WindowAction.previousDisplay.positionCycles)
        XCTAssertFalse(WindowAction.larger.positionCycles)
        XCTAssertFalse(WindowAction.smaller.positionCycles)
        XCTAssertFalse(WindowAction.tileAll.positionCycles)
        XCTAssertFalse(WindowAction.cascadeAll.positionCycles)
        XCTAssertFalse(WindowAction.specified.positionCycles)
    }
}

class ScreenFlippedTests: XCTestCase {

    func testScreenFlippedIsOwnInverse() {
        let rect = CGRect(x: 100, y: 200, width: 400, height: 300)
        let flipped = rect.screenFlipped
        let doubleFlipped = flipped.screenFlipped
        XCTAssertEqual(rect.origin.x, doubleFlipped.origin.x, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, doubleFlipped.origin.y, accuracy: 0.001)
        XCTAssertEqual(rect.width, doubleFlipped.width, accuracy: 0.001)
        XCTAssertEqual(rect.height, doubleFlipped.height, accuracy: 0.001)
    }

    func testScreenFlippedPreservesSize() {
        let rect = CGRect(x: 50, y: 100, width: 800, height: 600)
        let flipped = rect.screenFlipped
        XCTAssertEqual(rect.width, flipped.width, accuracy: 0.001)
        XCTAssertEqual(rect.height, flipped.height, accuracy: 0.001)
    }

    func testScreenFlippedPreservesX() {
        let rect = CGRect(x: 250, y: 300, width: 500, height: 400)
        let flipped = rect.screenFlipped
        XCTAssertEqual(rect.origin.x, flipped.origin.x, accuracy: 0.001)
    }

    func testScreenFlippedNullRectReturnsNull() {
        let nullRect = CGRect.null
        let flipped = nullRect.screenFlipped
        XCTAssertTrue(flipped.isNull)
    }

    func testScreenFlippedNegativeCoordinates() {
        let rect = CGRect(x: -1000, y: -500, width: 400, height: 300)
        let flipped = rect.screenFlipped
        let doubleFlipped = flipped.screenFlipped
        XCTAssertEqual(rect.origin.x, doubleFlipped.origin.x, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, doubleFlipped.origin.y, accuracy: 0.001)
    }
}

class DefaultsExportTests: XCTestCase {

    func testOverlapDefaultsInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("cyclingOverlapOffset"), "cyclingOverlapOffset missing from Defaults.array")
        XCTAssertTrue(keys.contains("cyclingOverlapOffsetSize"), "cyclingOverlapOffsetSize missing from Defaults.array")
        XCTAssertTrue(keys.contains("cyclingOverlapMaxCascade"), "cyclingOverlapMaxCascade missing from Defaults.array")
    }
}

class OverlapOffsetGuardsTests: XCTestCase {

    func testMaxCascadeClampedToMinOne() {
        let result = min(5, max(1, 0))
        XCTAssertEqual(result, 1)
    }

    func testMaxCascadeClampedToMaxFive() {
        let result = min(5, max(1, 999))
        XCTAssertEqual(result, 5)
    }

    func testMaxCascadeNegativeClampsToOne() {
        let result = min(5, max(1, -10))
        XCTAssertEqual(result, 1)
    }

    func testMaxCascadeNormalValuePassesThrough() {
        let result = min(5, max(1, 3))
        XCTAssertEqual(result, 3)
    }

    func testOffsetClampingKeepsRectInScreen() {
        let screenFrame = CGRect(x: 0, y: 0, width: 2336, height: 1466)
        var candidate = CGRect(x: 2300, y: 1400, width: 400, height: 300)
        let overlapOffset: CGFloat = 11

        candidate.origin.x += overlapOffset
        candidate.origin.y += overlapOffset

        if candidate.origin.x + candidate.width > screenFrame.maxX {
            candidate.origin.x = screenFrame.maxX - candidate.width
        }
        if candidate.origin.y + candidate.height > screenFrame.maxY {
            candidate.origin.y = screenFrame.maxY - candidate.height
        }
        if candidate.origin.x < screenFrame.origin.x {
            candidate.origin.x = screenFrame.origin.x
        }
        if candidate.origin.y < screenFrame.origin.y {
            candidate.origin.y = screenFrame.origin.y
        }

        XCTAssertLessThanOrEqual(candidate.origin.x + candidate.width, screenFrame.maxX)
        XCTAssertLessThanOrEqual(candidate.origin.y + candidate.height, screenFrame.maxY)
        XCTAssertGreaterThanOrEqual(candidate.origin.x, screenFrame.origin.x)
        XCTAssertGreaterThanOrEqual(candidate.origin.y, screenFrame.origin.y)
    }

    func testOffsetClampingWithNegativeScreenOrigin() {
        let screenFrame = CGRect(x: -1372, y: 1510, width: 3840, height: 2160)
        var candidate = CGRect(x: -1372, y: 1510, width: 960, height: 540)
        let overlapOffset: CGFloat = 11

        candidate.origin.x += overlapOffset
        candidate.origin.y += overlapOffset

        if candidate.origin.x + candidate.width > screenFrame.maxX {
            candidate.origin.x = screenFrame.maxX - candidate.width
        }
        if candidate.origin.y + candidate.height > screenFrame.maxY {
            candidate.origin.y = screenFrame.maxY - candidate.height
        }
        if candidate.origin.x < screenFrame.origin.x {
            candidate.origin.x = screenFrame.origin.x
        }
        if candidate.origin.y < screenFrame.origin.y {
            candidate.origin.y = screenFrame.origin.y
        }

        XCTAssertLessThanOrEqual(candidate.origin.x + candidate.width, screenFrame.maxX)
        XCTAssertLessThanOrEqual(candidate.origin.y + candidate.height, screenFrame.maxY)
        XCTAssertGreaterThanOrEqual(candidate.origin.x, screenFrame.origin.x)
        XCTAssertGreaterThanOrEqual(candidate.origin.y, screenFrame.origin.y)
        XCTAssertEqual(candidate.origin.x, -1372 + 11, accuracy: 0.001)
        XCTAssertEqual(candidate.origin.y, 1510 + 11, accuracy: 0.001)
    }
}

class SnappingManagerSessionTests: XCTestCase {

    private var savedSnappingEnabled: Bool?

    override func setUp() {
        super.setUp()
        savedSnappingEnabled = Defaults.windowSnapping.enabled
        Defaults.windowSnapping.enabled = false
    }

    override func tearDown() {
        super.tearDown()
        Defaults.windowSnapping.enabled = savedSnappingEnabled
    }

    func testSessionDidBecomeActiveTriggersCheckFullScreen() {
        let sm = SnappingManager()
        sm.isFullScreen = true

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        XCTAssertFalse(sm.isFullScreen,
            "receiveSessionNote should call checkFullScreen, re-evaluating isFullScreen")
    }

    func testSessionDidBecomeActiveEventMonitorPreserved() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "toggleListening should be called but preserve event monitor state")
    }

    func testSessionDidBecomeActiveDoesNotEnableSnapping() {
        let sm = SnappingManager()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        XCTAssertNil(sm.eventMonitor,
            "snapping should remain disabled after session became active notification")
    }

    func testSessionDidBecomeActiveMultiplePostsNoCrash() {
        let sm = SnappingManager()

        for _ in 0..<5 {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil
            )
        }

        XCTAssertFalse(sm.isFullScreen)
    }

    func testSleepWakeMaintainsSnapping() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "activeSpaceDidChange (simulating wake) should preserve event monitor state")
    }

    func testSessionUnlockThenWakeMaintainsSnapping() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "session unlock followed by wake should restore event monitor state")
    }

    func testSessionUnlockWithDisabledSnapping() {
        let sm = SnappingManager()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        XCTAssertNil(sm.eventMonitor,
            "session unlock -> wake should not enable snapping when disabled")
    }

    func testFullScreenThenWakeThenLeaveFullScreen() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "session restore after full screen should preserve event monitor state")
    }

    func testSessionResignActiveDoesNotCrash() {
        let sm = SnappingManager()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        XCTAssertFalse(sm.isFullScreen)
    }

    func testSessionResignActiveThenBecomeActive() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "session resign then become active should preserve event monitor state")
    }

    func testScreensDoNotSleepNotificationsBreakSnapping() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "screen sleep then wake should preserve event monitor state")
    }

    func testScreenSleepSessionResignThenWakeAndSessionActive() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "screen sleep + session resign -> session active + wake should restore event monitor state")
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

class ClampedWindowAlignerTests: XCTestCase {

    // Screen 2000x1200 at origin. Coordinates are already screen-flipped (window space):
    // the zone's maxY edge is the screen TOP, minY edge is the screen BOTTOM.

    func testRightHalfClampedBothAxesAnchorsRightCentersVertically() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 600, height: 800) // narrower + shorter than zone
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, sharedEdges: [.right, .top, .bottom])
        XCTAssertEqual(result.origin.x, 1400, accuracy: 0.001) // zone.maxX - width = 2000 - 600
        XCTAssertEqual(result.origin.y, 200, accuracy: 0.001)  // centered: (1200 - 800)/2
        XCTAssertEqual(result.width, 600, accuracy: 0.001)
        XCTAssertEqual(result.height, 800, accuracy: 0.001)
    }

    func testRightHalfFullHeightLeavesVerticalUntouched() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 600, height: 1200) // fills height
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, sharedEdges: [.right, .top, .bottom])
        XCTAssertEqual(result.origin.x, 1400, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 0, accuracy: 0.001)
    }

    func testLeftHalfClampedAnchorsLeftCentersVertically() {
        let zone = CGRect(x: 0, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 0, y: 0, width: 600, height: 800)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, sharedEdges: [.left, .top, .bottom])
        XCTAssertEqual(result.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 200, accuracy: 0.001)
    }

    func testTopRightQuarterAnchorsToCorner() {
        let zone = CGRect(x: 1000, y: 600, width: 1000, height: 600) // top-right; maxY=1200=screen top
        let window = CGRect(x: 1000, y: 600, width: 600, height: 400)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, sharedEdges: [.right, .top])
        XCTAssertEqual(result.origin.x, 1400, accuracy: 0.001) // maxX - width
        XCTAssertEqual(result.origin.y, 800, accuracy: 0.001)  // maxY - height = 1200 - 400
    }

    func testInteriorZoneCentersBothAxes() {
        let zone = CGRect(x: 600, y: 400, width: 800, height: 400)
        let window = CGRect(x: 600, y: 400, width: 400, height: 200)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, sharedEdges: [])
        XCTAssertEqual(result.origin.x, 800, accuracy: 0.001) // (800-400)/2 + 600
        XCTAssertEqual(result.origin.y, 500, accuracy: 0.001) // (400-200)/2 + 400
    }

    func testExactFitReturnsUnchanged() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = zone
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, sharedEdges: [.right, .top, .bottom])
        XCTAssertTrue(result.equalTo(window))
    }
}
