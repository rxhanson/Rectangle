/// ShortcutTests.swift

import Carbon.HIToolbox
import MASShortcut
import XCTest
@testable import Rectangle

class ShortcutManagerSessionTests: XCTestCase {

    private final class ValueBox<Value> {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private final class BindingStoreSpy: ShortcutBindingStore {
        private(set) var configureCallCount = 0
        private(set) var registeredDefaultKeys = Set<String>()
        private(set) var boundKeys = Set<String>()
        private(set) var bindCallCount = 0
        private(set) var breakBindingCallCount = 0

        func configure() {
            configureCallCount += 1
        }

        func registerDefaultShortcuts(_ shortcuts: [String: MASShortcut]) {
            registeredDefaultKeys.formUnion(shortcuts.keys)
        }

        func bindShortcut(withDefaultsKey defaultsKey: String, toAction action: @escaping () -> Void) {
            bindCallCount += 1
            boundKeys.insert(defaultsKey)
        }

        func breakBinding(withDefaultsKey defaultsKey: String) {
            breakBindingCallCount += 1
            boundKeys.remove(defaultsKey)
        }
    }

    private final class MouseButtonBindingStoreSpy: MouseButtonBindingStore {
        private(set) var actions = [ShortcutCycle.ShortcutIdentity: (MouseButtonPress) -> Void]()

        var boundShortcuts: Set<ShortcutCycle.ShortcutIdentity> {
            Set(actions.keys)
        }

        func bindShortcut(_ shortcut: MASShortcut, toAction action: @escaping (MouseButtonPress) -> Void) {
            actions[ShortcutCycle.ShortcutIdentity(shortcut)] = action
        }

        func breakAllBindings() {
            actions.removeAll()
        }
    }

    private final class SchedulerSpy {
        private var scheduledActions = [() -> Void]()

        var pendingCount: Int {
            scheduledActions.count
        }

        func schedule(_ action: @escaping () -> Void) {
            scheduledActions.append(action)
        }

        func runNext() {
            guard !scheduledActions.isEmpty else {
                XCTFail("Expected a scheduled shortcut rebind")
                return
            }
            scheduledActions.removeFirst()()
        }
    }

    private struct Harness {
        let manager: ShortcutManager
        let bindingStore: BindingStoreSpy
        let mouseButtonBindingStore: MouseButtonBindingStoreSpy
        let notificationCenter: NotificationCenter
        let workspaceNotificationCenter: NotificationCenter
        let shortcuts: ValueBox<[WindowAction: MASShortcut]>
        let appDisabled: ValueBox<Bool>
        let missionControlActive: ValueBox<Bool>
        let ignoreShortcutsInMissionControl: ValueBox<Bool>
        let scheduler: SchedulerSpy
        let todoSessionStates: ValueBox<[Bool]>
    }

    private func shortcut(_ keyCode: Int) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: [.command, .option])
    }

    private func makeHarness(
        initiallyActive: Bool = true,
        appDisabled: Bool = false,
        missionControlActive: Bool = false,
        ignoreShortcutsInMissionControl: Bool = true,
        shortcuts: [WindowAction: MASShortcut]? = nil,
        windowManager: WindowManager = WindowManager(),
        screenDetection: ScreenDetection = ScreenDetection(),
        windowUnderCursor: AccessibilityElement? = nil
    ) -> Harness {
        let bindingStore = BindingStoreSpy()
        let mouseButtonBindingStore = MouseButtonBindingStoreSpy()
        let notificationCenter = NotificationCenter()
        let workspaceNotificationCenter = NotificationCenter()
        let shortcuts = ValueBox(shortcuts ?? [.leftHalf: shortcut(1)])
        let appDisabled = ValueBox(appDisabled)
        let missionControlActive = ValueBox(missionControlActive)
        let ignoreShortcutsInMissionControl = ValueBox(ignoreShortcutsInMissionControl)
        let scheduler = SchedulerSpy()
        let todoSessionStates = ValueBox<[Bool]>([])
        let manager = ShortcutManager(
            windowManager: windowManager,
            screenDetection: screenDetection,
            bindingStore: bindingStore,
            mouseButtonBindingStore: mouseButtonBindingStore,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            shortcutsProvider: { shortcuts.value },
            activeStateProvider: { initiallyActive },
            appDisabledProvider: { appDisabled.value },
            missionControlActiveProvider: { missionControlActive.value },
            ignoreShortcutsInMissionControlProvider: { ignoreShortcutsInMissionControl.value },
            windowUnderCursorProvider: { _ in windowUnderCursor },
            scheduler: { scheduler.schedule($0) },
            todoSessionStateChanged: { todoSessionStates.value.append($0) }
        )

        return Harness(
            manager: manager,
            bindingStore: bindingStore,
            mouseButtonBindingStore: mouseButtonBindingStore,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            shortcuts: shortcuts,
            appDisabled: appDisabled,
            missionControlActive: missionControlActive,
            ignoreShortcutsInMissionControl: ignoreShortcutsInMissionControl,
            scheduler: scheduler,
            todoSessionStates: todoSessionStates
        )
    }

    private func resignSession(_ harness: Harness) {
        harness.workspaceNotificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
    }

    private func activateSession(_ harness: Harness) {
        harness.workspaceNotificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    func testActiveSessionResignThenDelayedActivationRestoresBindings() {
        let harness = makeHarness()
        let expectedKeys: Set<String> = [WindowAction.leftHalf.name]

        XCTAssertEqual(harness.bindingStore.boundKeys, expectedKeys)
        XCTAssertEqual(harness.todoSessionStates.value, [true])

        resignSession(harness)

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        XCTAssertEqual(harness.todoSessionStates.value, [true, false])

        activateSession(harness)

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.scheduler.pendingCount, 1)
        XCTAssertEqual(harness.todoSessionStates.value, [true, false])

        harness.scheduler.runNext()

        XCTAssertEqual(harness.bindingStore.boundKeys, expectedKeys)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        XCTAssertEqual(harness.todoSessionStates.value, [true, false, true])
    }

    func testDuplicateSessionNotificationsAreIdempotent() {
        let harness = makeHarness()

        resignSession(harness)
        let breakCallsAfterFirstResign = harness.bindingStore.breakBindingCallCount

        resignSession(harness)

        XCTAssertEqual(harness.bindingStore.breakBindingCallCount, breakCallsAfterFirstResign)

        activateSession(harness)
        activateSession(harness)

        XCTAssertEqual(harness.scheduler.pendingCount, 1)

        harness.scheduler.runNext()
        let bindCallsAfterActivation = harness.bindingStore.bindCallCount

        activateSession(harness)

        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        XCTAssertEqual(harness.bindingStore.bindCallCount, bindCallsAfterActivation)
        XCTAssertEqual(harness.bindingStore.boundKeys, [WindowAction.leftHalf.name])
    }

    func testActivationRestoresCurrentLogicalShortcutsAfterTheyChangeWhileInactive() {
        let harness = makeHarness()

        resignSession(harness)
        harness.shortcuts.value = [.rightHalf: shortcut(2)]

        activateSession(harness)
        harness.scheduler.runNext()

        XCTAssertEqual(harness.bindingStore.boundKeys, [WindowAction.rightHalf.name])
        XCTAssertFalse(harness.bindingStore.boundKeys.contains(WindowAction.leftHalf.name))
    }

    func testDisabledApplicationBlocksSessionRestore() {
        let harness = makeHarness()

        resignSession(harness)
        harness.appDisabled.value = true

        activateSession(harness)
        harness.scheduler.runNext()

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
    }

    func testRecordingBlocksSessionRestoreUntilRecordingEnds() throws {
        let binder = try XCTUnwrap(MASShortcutBinder.shared())
        let previousBindingOptions = binder.bindingOptions
        binder.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        defer {
            TodoManager.setShortcutBindingsSuspended(false)
            binder.bindingOptions = previousBindingOptions
        }

        let harness = makeHarness()

        harness.notificationCenter.post(name: .shortcutRecording, object: true)
        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)

        resignSession(harness)
        activateSession(harness)
        harness.scheduler.runNext()

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)

        harness.notificationCenter.post(name: .shortcutRecording, object: false)

        XCTAssertEqual(harness.bindingStore.boundKeys, [WindowAction.leftHalf.name])
    }

    func testInitiallyInactiveSessionDoesNotBindUntilActivationCompletes() {
        let harness = makeHarness(initiallyActive: false)

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        XCTAssertEqual(harness.todoSessionStates.value, [false])

        activateSession(harness)

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.scheduler.pendingCount, 1)
        XCTAssertEqual(harness.todoSessionStates.value, [false])

        harness.scheduler.runNext()

        XCTAssertEqual(harness.bindingStore.boundKeys, [WindowAction.leftHalf.name])
        XCTAssertEqual(harness.todoSessionStates.value, [false, true])
    }

    func testResignBeforeQueuedActivationCompletesCancelsRestore() {
        let harness = makeHarness()

        resignSession(harness)
        activateSession(harness)
        XCTAssertEqual(harness.scheduler.pendingCount, 1)

        resignSession(harness)
        harness.scheduler.runNext()

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.scheduler.pendingCount, 0)
        XCTAssertEqual(harness.todoSessionStates.value, [true, false, false])
    }

    private func mouseButtonShortcut(_ buttonNumber: Int, _ flags: NSEvent.ModifierFlags = []) -> MASShortcut {
        MASShortcut(keyCode: MouseButtonShortcut(buttonNumber: buttonNumber, modifierFlags: flags).keyCode, modifierFlags: flags)
    }

    private final class CapturingWindowManager: WindowManager {
        private(set) var executedParameters = [ExecutionParameters]()
        var recordsHistory = false

        override func execute(_ parameters: ExecutionParameters) {
            executedParameters.append(parameters)
            if recordsHistory {
                recordAction(windowId: parameters.windowId, resultingRect: parameters.windowElement?.frame ?? .null,
                             action: parameters.action, subAction: nil)
            }
        }
    }

    private final class TestWindow: AccessibilityElement {
        private let testWindowId: CGWindowID?

        init(windowId: CGWindowID?) {
            testWindowId = windowId
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { CGRect(x: 0, y: 0, width: 400, height: 300) }
        override func getWindowId() -> CGWindowID? { testWindowId }
    }

    /// A window that already fills its screen, which the repeat detection reads as a repeated Maximize.
    private final class ScreenSizedWindow: AccessibilityElement {
        private let testWindowId: CGWindowID?
        private let testSize: CGSize

        init(windowId: CGWindowID?, size: CGSize) {
            testWindowId = windowId
            testSize = size
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { CGRect(origin: .zero, size: testSize) }
        override func getWindowId() -> CGWindowID? { testWindowId }
    }

    private final class AdjacentScreenDetection: ScreenDetection {
        let screen: NSScreen

        init(screen: NSScreen) {
            self.screen = screen
        }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            UsableScreens(currentScreen: screen, adjacentScreens: AdjacentScreens(prev: screen, next: screen), numScreens: 2)
        }
    }

    private final class CursorScreenDetection: ScreenDetection {
        let screen: NSScreen

        init(screen: NSScreen) {
            self.screen = screen
        }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            UsableScreens(currentScreen: screen, adjacentScreens: AdjacentScreens(prev: screen, next: screen), numScreens: 2)
        }

        override func detectScreensAtCursor() -> UsableScreens? {
            UsableScreens(currentScreen: screen, numScreens: 2)
        }
    }

    /// Runs `body` with the settings that decide how a mouse button press
    /// executes, putting the user's back afterwards.
    private func withExecutionSettings(subsequentExecutionMode: SubsequentExecutionMode = .none,
                                       pointerTargeting: Bool, cursorDetection: Bool = false,
                                       _ body: () throws -> Void) rethrows {
        let savedMode = Defaults.subsequentExecutionMode.toCodable()
        let savedPointerTargeting = Defaults.mouseButtonShortcutsUseWindowUnderCursor.enabled
        let savedCursorDetection = Defaults.useCursorScreenDetection.enabled
        Defaults.subsequentExecutionMode.load(from: CodableDefault(int: subsequentExecutionMode.rawValue))
        Defaults.mouseButtonShortcutsUseWindowUnderCursor.enabled = pointerTargeting
        Defaults.useCursorScreenDetection.enabled = cursorDetection
        defer {
            Defaults.subsequentExecutionMode.load(from: savedMode)
            Defaults.mouseButtonShortcutsUseWindowUnderCursor.enabled = savedPointerTargeting
            Defaults.useCursorScreenDetection.enabled = savedCursorDetection
        }
        try body()
    }

    private func press(_ mouseButton: MASShortcut, in harness: Harness) throws {
        let action = try XCTUnwrap(harness.mouseButtonBindingStore.actions[ShortcutCycle.ShortcutIdentity(mouseButton)])
        action(MouseButtonPress(location: .zero, windowId: nil))
    }

    func testMouseButtonPressActsOnTheFocusedWindowByDefault() throws {
        try withExecutionSettings(pointerTargeting: false) {
            let mouseButton = mouseButtonShortcut(4)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(shortcuts: [.rightHalf: mouseButton], windowManager: windowManager,
                                      windowUnderCursor: TestWindow(windowId: 987_000))

            try press(mouseButton, in: harness)

            XCTAssertEqual(windowManager.executedParameters.count, 1)
            let parameters = try XCTUnwrap(windowManager.executedParameters.first)
            XCTAssertEqual(parameters.action, .rightHalf)
            XCTAssertNil(parameters.windowElement)
            XCTAssertFalse(parameters.preservesFocus)
        }
    }

    func testPointerTargetedPressActsOnTheWindowUnderThePointerWithoutTakingFocus() throws {
        try withExecutionSettings(pointerTargeting: true) {
            let mouseButton = mouseButtonShortcut(3)
            let window = TestWindow(windowId: 987_001)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(shortcuts: [.leftHalf: mouseButton], windowManager: windowManager, windowUnderCursor: window)

            try press(mouseButton, in: harness)

            XCTAssertEqual(windowManager.executedParameters.count, 1)
            let parameters = try XCTUnwrap(windowManager.executedParameters.first)
            XCTAssertEqual(parameters.action, .leftHalf)
            XCTAssertTrue(parameters.windowElement === window)
            XCTAssertEqual(parameters.windowId, 987_001)
            XCTAssertTrue(parameters.preservesFocus)
        }
    }

    func testPointerTargetedPressDoesNotNeedAWindowId() throws {
        try withExecutionSettings(pointerTargeting: true) {
            let mouseButton = mouseButtonShortcut(3)
            let window = TestWindow(windowId: nil)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(shortcuts: [.leftHalf: mouseButton], windowManager: windowManager, windowUnderCursor: window)

            try press(mouseButton, in: harness)

            let parameters = try XCTUnwrap(windowManager.executedParameters.first)
            XCTAssertTrue(parameters.windowElement === window)
            XCTAssertNil(parameters.windowId)
            XCTAssertTrue(parameters.preservesFocus)
        }
    }

    func testPointerTargetedDuplicateShortcutCyclesOnTheWindowUnderThePointer() throws {
        try withExecutionSettings(pointerTargeting: true) {
            let mouseButton = mouseButtonShortcut(3, [.option])
            let window = TestWindow(windowId: 987_002)
            defer { AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: 987_002) }
            let windowManager = CapturingWindowManager()
            windowManager.recordsHistory = true
            let harness = makeHarness(shortcuts: [.centerHalf: mouseButton, .centerThird: mouseButton],
                                      windowManager: windowManager, windowUnderCursor: window)

            for _ in 0..<3 {
                try press(mouseButton, in: harness)
            }

            XCTAssertEqual(windowManager.executedParameters.map(\.action), [.centerHalf, .centerThird, .centerHalf])
            XCTAssertTrue(windowManager.executedParameters.allSatisfy { $0.windowElement === window && $0.preservesFocus })
        }
    }

    func testDisplayCycleKeepsPreservingFocus() throws {
        try withExecutionSettings(subsequentExecutionMode: .cycleMonitor, pointerTargeting: true) {
            let window = TestWindow(windowId: 987_003)
            defer { AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: 987_003) }
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(windowManager: windowManager, screenDetection: AdjacentScreenDetection(screen: screen))
            AppDelegate.windowHistory.lastRectangleActions[987_003] = RectangleAction(action: .leftHalf, rect: window.frame)

            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName,
                                            object: ExecutionParameters(.leftHalf, windowElement: window, windowId: 987_003, preservesFocus: true))

            let parameters = try XCTUnwrap(windowManager.executedParameters.first)
            XCTAssertTrue(parameters.screen === screen)
            XCTAssertTrue(parameters.preservesFocus)
        }
    }

    func testDisplayCycleStartsFreshWhenCursorPointsAtAnotherDisplay() throws {
        defer { CursorScreenHistory.shared.screenFrames.removeValue(forKey: 987_004) }
        try withExecutionSettings(subsequentExecutionMode: .cycleMonitor, pointerTargeting: false, cursorDetection: true) {
            let window = TestWindow(windowId: 987_004)
            defer { AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: 987_004) }
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(windowManager: windowManager, screenDetection: CursorScreenDetection(screen: screen))
            AppDelegate.windowHistory.lastRectangleActions[987_004] = RectangleAction(action: .leftHalf, rect: window.frame)

            // The last press happened with the cursor on another display.
            CursorScreenHistory.shared.screenFrames[987_004] = screen.frame.offsetBy(dx: screen.frame.width, dy: 0)
            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName,
                                            object: ExecutionParameters(.leftHalf, windowElement: window, windowId: 987_004))
            XCTAssertNil(try XCTUnwrap(windowManager.executedParameters.last).screen)

            // Pressing again with the cursor where it was last time still cycles.
            CursorScreenHistory.shared.screenFrames[987_004] = screen.frame
            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName,
                                            object: ExecutionParameters(.leftHalf, windowElement: window, windowId: 987_004))
            XCTAssertTrue(try XCTUnwrap(windowManager.executedParameters.last).screen === screen)
        }
    }

    /// Mission Control does not change the frontmost app, so a hotkey pressed
    /// while it is showing would move the window behind the overview.
    func testKeyboardShortcutIsIgnoredWhileMissionControlIsActive() throws {
        try withExecutionSettings(pointerTargeting: false) {
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(missionControlActive: true, windowManager: windowManager)
            var completed = false

            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName,
                                            object: ExecutionParameters(.leftHalf, completion: { completed = true }))
            XCTAssertTrue(windowManager.executedParameters.isEmpty)
            XCTAssertTrue(completed, "An ignored request still gets its completion")

            harness.missionControlActive.value = false
            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName, object: ExecutionParameters(.leftHalf))
            XCTAssertEqual(windowManager.executedParameters.map(\.action), [.leftHalf])
        }
    }

    func testMouseButtonPressIsIgnoredWhileMissionControlIsActive() throws {
        try withExecutionSettings(pointerTargeting: false) {
            let mouseButton = mouseButtonShortcut(4)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(missionControlActive: true, shortcuts: [.rightHalf: mouseButton], windowManager: windowManager)

            try press(mouseButton, in: harness)
            XCTAssertTrue(windowManager.executedParameters.isEmpty)

            harness.missionControlActive.value = false
            try press(mouseButton, in: harness)
            XCTAssertEqual(windowManager.executedParameters.map(\.action), [.rightHalf])
        }
    }

    /// An ignored shortcut is dropped before anything observes it.
    func testIgnoredShortcutIsNotAnnouncedAsExecuting() throws {
        try withExecutionSettings(pointerTargeting: false) {
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(missionControlActive: true, windowManager: windowManager)
            var announced = [WindowAction]()
            let observer = Notification.Name.windowActionWillExecute.onPost { notification in
                if let parameters = notification.object as? ExecutionParameters {
                    announced.append(parameters.action)
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName, object: ExecutionParameters(.leftHalf))
            XCTAssertTrue(announced.isEmpty)

            harness.missionControlActive.value = false
            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName, object: ExecutionParameters(.leftHalf))
            XCTAssertEqual(announced, [.leftHalf])
        }
    }

    /// Menu, URL scheme, title bar and drag-to-snap requests are deliberate,
    /// so only keyboard (and mouse button) shortcuts are held back.
    func testOtherSourcesStillExecuteWhileMissionControlIsActive() throws {
        try withExecutionSettings(pointerTargeting: false) {
            let window = TestWindow(windowId: 987_004)
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(missionControlActive: true, windowManager: windowManager)
            let sources: [ExecutionSource] = [.menuItem, .url, .titleBar, .dragToSnap]

            for source in sources {
                harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName,
                                                object: ExecutionParameters(.leftHalf, screen: screen, windowElement: window,
                                                                            windowId: 987_004, source: source))
            }

            XCTAssertEqual(windowManager.executedParameters.map(\.source), sources)
        }
    }

    /// The guard is opt-out: turning the ignoreShortcutsInMissionControl default
    /// off lets a keyboard shortcut run even while Mission Control is showing,
    /// and turning it back on holds the next one back.
    func testKeyboardShortcutHonorsTheIgnoreInMissionControlDefault() throws {
        try withExecutionSettings(pointerTargeting: false) {
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(missionControlActive: true, ignoreShortcutsInMissionControl: false,
                                      windowManager: windowManager)

            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName, object: ExecutionParameters(.leftHalf))
            XCTAssertEqual(windowManager.executedParameters.map(\.action), [.leftHalf],
                           "With the default disabled the shortcut runs despite Mission Control")

            harness.ignoreShortcutsInMissionControl.value = true
            harness.notificationCenter.post(name: WindowAction.leftHalf.notificationName, object: ExecutionParameters(.leftHalf))
            XCTAssertEqual(windowManager.executedParameters.map(\.action), [.leftHalf],
                           "Re-enabling the default holds the next shortcut back")
        }
    }

    /// Repeated commands set to "cycle through displays" treat a Maximize on an
    /// already screen-sized window as a repeat. A window that opens at that size
    /// must not be sent to another display by its automatic placement.
    func testNewWindowPlacementIsNeverTreatedAsARepeatedCommand() throws {
        try withExecutionSettings(subsequentExecutionMode: .cycleMonitor, pointerTargeting: false) {
            let screen = try XCTUnwrap(NSScreen.screens.first)
            let window = ScreenSizedWindow(windowId: 987_005, size: screen.visibleFrame.size)
            defer { AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: 987_005) }
            let windowManager = CapturingWindowManager()
            let harness = makeHarness(windowManager: windowManager, screenDetection: AdjacentScreenDetection(screen: screen))

            harness.notificationCenter.post(name: WindowAction.maximize.notificationName,
                                            object: ExecutionParameters(.maximize, windowElement: window, windowId: 987_005,
                                                                        source: .newWindow, preservesFocus: true))
            harness.notificationCenter.post(name: WindowAction.maximize.notificationName,
                                            object: ExecutionParameters(.maximize, windowElement: window, windowId: 987_005))

            XCTAssertEqual(windowManager.executedParameters.count, 2)
            XCTAssertNil(windowManager.executedParameters[0].screen, "a new window stays on its own display")
            XCTAssertTrue(windowManager.executedParameters[1].screen === screen, "the same request from a shortcut cycles displays")
        }
    }

    func testMouseButtonShortcutsBindToTheMouseButtonStoreOnly() {
        let mouseButton = mouseButtonShortcut(3)
        let harness = makeHarness(shortcuts: [.leftHalf: shortcut(1), .rightHalf: mouseButton])

        XCTAssertEqual(harness.bindingStore.boundKeys, [WindowAction.leftHalf.name])
        XCTAssertEqual(harness.mouseButtonBindingStore.boundShortcuts, [ShortcutCycle.ShortcutIdentity(mouseButton)])
    }

    func testDuplicateMouseButtonShortcutsBindOnceAsACycle() {
        let mouseButton = mouseButtonShortcut(3, [.option])
        let harness = makeHarness(shortcuts: [.centerHalf: mouseButton, .centerThird: mouseButton])

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.mouseButtonBindingStore.boundShortcuts, [ShortcutCycle.ShortcutIdentity(mouseButton)])
    }

    func testMouseButtonShortcutsStandDownAndReturnWithTheSession() {
        let harness = makeHarness(shortcuts: [.rightHalf: mouseButtonShortcut(4)])

        resignSession(harness)
        XCTAssertTrue(harness.mouseButtonBindingStore.boundShortcuts.isEmpty)

        activateSession(harness)
        XCTAssertTrue(harness.mouseButtonBindingStore.boundShortcuts.isEmpty)

        harness.scheduler.runNext()
        XCTAssertEqual(harness.mouseButtonBindingStore.boundShortcuts.count, 1)
    }

    func testMouseButtonShortcutsStandDownWhileAnIgnoredAppIsFrontmost() {
        let harness = makeHarness(shortcuts: [.rightHalf: mouseButtonShortcut(4)])

        harness.appDisabled.value = true
        harness.manager.unbindShortcuts()
        harness.manager.bindShortcuts()
        XCTAssertTrue(harness.mouseButtonBindingStore.boundShortcuts.isEmpty)

        harness.appDisabled.value = false
        harness.manager.bindShortcuts()
        XCTAssertEqual(harness.mouseButtonBindingStore.boundShortcuts.count, 1)
    }

    func testMouseButtonShortcutsStandDownWhileRecording() throws {
        let binder = try XCTUnwrap(MASShortcutBinder.shared())
        let previousBindingOptions = binder.bindingOptions
        binder.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
        defer {
            TodoManager.setShortcutBindingsSuspended(false)
            binder.bindingOptions = previousBindingOptions
        }

        let harness = makeHarness(shortcuts: [.rightHalf: mouseButtonShortcut(4)])

        harness.notificationCenter.post(name: .shortcutRecording, object: true)
        XCTAssertTrue(harness.mouseButtonBindingStore.boundShortcuts.isEmpty)

        harness.notificationCenter.post(name: .shortcutRecording, object: false)
        XCTAssertEqual(harness.mouseButtonBindingStore.boundShortcuts.count, 1)
    }

    func testChangingAShortcutBetweenKeyAndMouseButtonMovesItsBinding() {
        let harness = makeHarness(shortcuts: [.rightHalf: shortcut(2)])

        harness.shortcuts.value = [.rightHalf: mouseButtonShortcut(4)]
        harness.notificationCenter.post(name: UserDefaults.didChangeNotification, object: nil)

        XCTAssertTrue(harness.bindingStore.boundKeys.isEmpty)
        XCTAssertEqual(harness.mouseButtonBindingStore.boundShortcuts.count, 1)

        harness.shortcuts.value = [.rightHalf: shortcut(2)]
        harness.notificationCenter.post(name: UserDefaults.didChangeNotification, object: nil)

        XCTAssertEqual(harness.bindingStore.boundKeys, [WindowAction.rightHalf.name])
        XCTAssertTrue(harness.mouseButtonBindingStore.boundShortcuts.isEmpty)
    }

    func testMouseButtonShortcutHasNoMenuKeyEquivalent() throws {
        let action = WindowAction.almostMaximize
        let previousValue = UserDefaults.standard.object(forKey: action.name)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: action.name)
            } else {
                UserDefaults.standard.removeObject(forKey: action.name)
            }
        }
        let transformer = try XCTUnwrap(ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)))
        let harness = makeHarness()

        UserDefaults.standard.set(transformer.reverseTransformedValue(mouseButtonShortcut(3, [.option])), forKey: action.name)
        XCTAssertNil(harness.manager.getKeyEquivalent(action: action))

        UserDefaults.standard.set(transformer.reverseTransformedValue(shortcut(3)), forKey: action.name)
        XCTAssertNotNil(harness.manager.getKeyEquivalent(action: action))
    }
}

class MouseButtonShortcutTests: XCTestCase {

    private func buttonPress(_ buttonNumber: Int, flags: CGEventFlags = []) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                            mouseCursorPosition: .zero, mouseButton: .center))
        cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
        cgEvent.flags = flags
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    func testEveryButtonRoundTripsThroughItsKeyCode() {
        for buttonNumber in MouseButtonShortcut.buttonNumbers {
            let shortcut = MouseButtonShortcut(buttonNumber: buttonNumber, modifierFlags: [])
            XCTAssertEqual(shortcut.buttonNumber, buttonNumber)
            XCTAssertEqual(MouseButtonShortcut.buttonNumber(forKeyCode: shortcut.keyCode), buttonNumber)
            XCTAssertTrue(MouseButtonShortcut.isMouseButton(shortcut))
        }
    }

    func testKeyCodesStayClearOfRealKeysEvenWhenTruncated() {
        for keyCode in 0..<0x100 {
            XCTAssertFalse(MouseButtonShortcut.isMouseButton(MASShortcut(keyCode: keyCode, modifierFlags: [])))
        }
        for buttonNumber in MouseButtonShortcut.buttonNumbers {
            let keyCode = MouseButtonShortcut(buttonNumber: buttonNumber, modifierFlags: []).keyCode
            XCTAssertLessThanOrEqual(keyCode, Int(UInt16.max))
            XCTAssertGreaterThanOrEqual(keyCode & 0xFF, 0xC0)
        }
    }

    func testOnlyTheFourShortcutModifiersAreKept() {
        let shortcut = MouseButtonShortcut(buttonNumber: 3, modifierFlags: [.option, .capsLock, .function, .numericPad])
        XCTAssertEqual(shortcut.modifierFlags, [.option])
    }

    func testButtonsAreNumberedFromTheLeftButton() {
        XCTAssertEqual(MouseButtonShortcut(buttonNumber: 2, modifierFlags: []).description, String(localized: "Middle Button"))
        XCTAssertEqual(MouseButtonShortcut(buttonNumber: 3, modifierFlags: []).description, String(localized: "Button \(4)"))
        XCTAssertEqual(MouseButtonShortcut(buttonNumber: 4, modifierFlags: [.command, .option]).description, "⌥⌘ " + String(localized: "Button \(5)"))
        XCTAssertEqual(MouseButtonShortcut(buttonNumber: 4, modifierFlags: []).keyCodeStringForKeyEquivalent, "")
    }

    func testStoredMouseButtonsBecomeDisplayableAndKeysAreLeftAlone() throws {
        let stored = MASShortcut(keyCode: MouseButtonShortcut(buttonNumber: 3, modifierFlags: []).keyCode, modifierFlags: [.shift])
        let displayable = try XCTUnwrap(MouseButtonShortcut.displayable(stored) as? MouseButtonShortcut)
        XCTAssertEqual(displayable.buttonNumber, 3)
        XCTAssertEqual(displayable.modifierFlags, [.shift])

        let key = MASShortcut(keyCode: kVK_ANSI_F, modifierFlags: [.option])
        XCTAssertTrue(MouseButtonShortcut.displayable(key) === key)
    }

    func testShortcutFromAButtonPressKeepsItsModifiers() throws {
        let shortcut = try XCTUnwrap(MouseButtonShortcut(buttonPress: buttonPress(3, flags: [.maskAlternate, .maskAlphaShift])))
        XCTAssertEqual(shortcut.buttonNumber, 3)
        XCTAssertEqual(shortcut.modifierFlags, [.option])
    }

    func testLeftAndRightClicksAreNotShortcuts() throws {
        XCTAssertNil(MouseButtonShortcut(buttonPress: try buttonPress(0)))
        XCTAssertNil(MouseButtonShortcut(buttonPress: try buttonPress(1)))
        XCTAssertNotNil(MouseButtonShortcut(buttonPress: try buttonPress(2)))
    }

    func testMouseButtonShortcutsAreStoredAndCycledLikeKeys() {
        let suiteName = "MouseButtonShortcutTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        let shortcut = MouseButtonShortcut(buttonNumber: 4, modifierFlags: [.control])
        let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let shortcutDict = dictTransformer.reverseTransformedValue(shortcut)
        userDefaults.setValue(shortcutDict, forKey: WindowAction.cycleStackedWindows.name)
        userDefaults.setValue(shortcutDict, forKey: WindowAction.cycleStackedWindowsBackward.name)

        let shortcutsByAction = ShortcutCycle.shortcutsByAction(actions: [.cycleStackedWindows, .cycleStackedWindowsBackward], userDefaults: userDefaults)
        let groups = ShortcutCycle.groups(actions: [.cycleStackedWindows, .cycleStackedWindowsBackward], shortcutsByAction: shortcutsByAction)

        let stored = shortcutsByAction[.cycleStackedWindows]
        XCTAssertTrue(stored.map(MouseButtonShortcut.isMouseButton) == true)
        XCTAssertEqual(stored.map(ShortcutCycle.ShortcutIdentity.init), ShortcutCycle.ShortcutIdentity(shortcut))
        XCTAssertEqual(groups.map(\.actions), [[.cycleStackedWindows, .cycleStackedWindowsBackward]])
    }
}

class MouseButtonShortcutRouterTests: XCTestCase {

    private func identity(_ buttonNumber: Int, _ flags: NSEvent.ModifierFlags = []) -> ShortcutCycle.ShortcutIdentity {
        ShortcutCycle.ShortcutIdentity(MouseButtonShortcut(buttonNumber: buttonNumber, modifierFlags: flags))
    }

    private func route(_ router: inout MouseButtonShortcutRouter, _ type: NSEvent.EventType, _ buttonNumber: Int,
                       _ flags: NSEvent.ModifierFlags = [], bound: Set<ShortcutCycle.ShortcutIdentity>) -> MouseButtonShortcutRouter.Decision {
        router.route(type, buttonNumber: buttonNumber, modifierFlags: flags) { bound.contains($0) }
    }

    func testBoundPressTriggersAndSwallowsItsDragsAndRelease() {
        var router = MouseButtonShortcutRouter()
        let bound: Set = [identity(3)]

        XCTAssertEqual(route(&router, .otherMouseDown, 3, bound: bound), .trigger(identity(3)))
        XCTAssertEqual(route(&router, .otherMouseDragged, 3, bound: bound), .swallow)
        XCTAssertEqual(route(&router, .otherMouseUp, 3, bound: bound), .swallow)
        XCTAssertEqual(route(&router, .otherMouseUp, 3, bound: bound), .passThrough)
        XCTAssertTrue(router.heldButtons.isEmpty)
    }

    func testUnboundButtonsPassThrough() {
        var router = MouseButtonShortcutRouter()
        let bound: Set = [identity(3)]

        XCTAssertEqual(route(&router, .otherMouseDown, 4, bound: bound), .passThrough)
        XCTAssertEqual(route(&router, .otherMouseDragged, 4, bound: bound), .passThrough)
        XCTAssertEqual(route(&router, .otherMouseUp, 4, bound: bound), .passThrough)
    }

    func testModifiersMustMatchExactly() {
        var router = MouseButtonShortcutRouter()
        let bound: Set = [identity(3, [.option])]

        XCTAssertEqual(route(&router, .otherMouseDown, 3, bound: bound), .passThrough)
        XCTAssertEqual(route(&router, .otherMouseDown, 3, [.option, .shift], bound: bound), .passThrough)
        XCTAssertEqual(route(&router, .otherMouseDown, 3, [.option, .capsLock], bound: bound), .trigger(identity(3, [.option])))
    }

    func testReleaseIsSwallowedEvenAfterModifiersAndBindingsChange() {
        var router = MouseButtonShortcutRouter()

        XCTAssertEqual(route(&router, .otherMouseDown, 3, [.option], bound: [identity(3, [.option])]), .trigger(identity(3, [.option])))
        XCTAssertEqual(route(&router, .otherMouseDragged, 3, bound: []), .swallow)
        XCTAssertEqual(route(&router, .otherMouseUp, 3, bound: []), .swallow)
    }

    func testEveryPressTriggers() {
        var router = MouseButtonShortcutRouter()
        let bound: Set = [identity(4)]

        for _ in 0..<3 {
            XCTAssertEqual(route(&router, .otherMouseDown, 4, bound: bound), .trigger(identity(4)))
            XCTAssertEqual(route(&router, .otherMouseUp, 4, bound: bound), .swallow)
        }
    }

    func testPressAfterAMissedReleaseIsRoutedAfresh() {
        var router = MouseButtonShortcutRouter()

        XCTAssertEqual(route(&router, .otherMouseDown, 3, bound: [identity(3)]), .trigger(identity(3)))
        XCTAssertEqual(route(&router, .otherMouseDown, 3, bound: []), .passThrough)
        XCTAssertEqual(route(&router, .otherMouseUp, 3, bound: []), .passThrough)
        XCTAssertTrue(router.heldButtons.isEmpty)
    }

    func testOtherButtonsAndEventsPassThrough() {
        var router = MouseButtonShortcutRouter()
        let bound: Set = [identity(3)]

        XCTAssertEqual(route(&router, .otherMouseDown, 1, bound: bound), .passThrough)
        XCTAssertEqual(route(&router, .leftMouseDown, 3, bound: bound), .passThrough)
        XCTAssertTrue(router.heldButtons.isEmpty)
    }
}

class WindowActionShortcutViewTests: XCTestCase {

    private func buttonPress(_ buttonNumber: Int, flags: CGEventFlags = []) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                            mouseCursorPosition: .zero, mouseButton: .center))
        cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
        cgEvent.flags = flags
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    func testStoredMouseButtonIsShownByName() {
        let view = WindowActionShortcutView()

        view.shortcutValue = MASShortcut(keyCode: MouseButtonShortcut(buttonNumber: 3, modifierFlags: []).keyCode, modifierFlags: [.option])

        XCTAssertTrue(view.shortcutValue is MouseButtonShortcut)
    }

    func testRecordsAMouseButtonOnlyWhileRecording() throws {
        let view = WindowActionShortcutView()
        defer { view.isRecording = false }

        XCTAssertFalse(view.recordMouseButton(try buttonPress(4)))
        XCTAssertNil(view.shortcutValue)

        view.isRecording = true
        XCTAssertTrue(view.recordMouseButton(try buttonPress(4, flags: [.maskCommand])))

        XCTAssertFalse(view.isRecording)
        let recorded = try XCTUnwrap(view.shortcutValue as? MouseButtonShortcut)
        XCTAssertEqual(recorded.buttonNumber, 4)
        XCTAssertEqual(recorded.modifierFlags, [.command])
    }

    func testLeftAndRightClicksAreNotRecorded() throws {
        let view = WindowActionShortcutView()
        defer { view.isRecording = false }

        view.isRecording = true

        XCTAssertFalse(view.recordMouseButton(try buttonPress(0)))
        XCTAssertFalse(view.recordMouseButton(try buttonPress(1)))
        XCTAssertTrue(view.isRecording)
        XCTAssertNil(view.shortcutValue)
    }

    func testRecordingThroughTheAppSavesTheButtonAndKeysStillRecordAfterwards() throws {
        let defaultsKey = "WindowActionShortcutViewTests-\(UUID().uuidString)"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        let view = WindowActionShortcutView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        window.contentView?.addSubview(view)
        view.shortcutValidator = PassthroughShortcutValidator()
        view.setAssociatedUserDefaultsKey(defaultsKey, withTransformerName: MASDictionaryTransformerName)
        defer {
            view.isRecording = false
            view.setAssociatedUserDefaultsKey(nil, withTransformerName: MASDictionaryTransformerName)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }

        // The event factory can't set a button number, so it goes in by way
        // of the CGEvent, which keeps the event's window.
        let windowEvent = try XCTUnwrap(NSEvent.mouseEvent(with: .otherMouseDown, location: .zero, modifierFlags: [.option],
                                                           timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                           eventNumber: 0, clickCount: 1, pressure: 1)?.cgEvent)
        windowEvent.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        view.isRecording = true
        NSApp.sendEvent(try XCTUnwrap(NSEvent(cgEvent: windowEvent)))

        XCTAssertFalse(view.isRecording)
        let storedButton = try XCTUnwrap(ShortcutCycle.shortcut(forDefaultsKey: defaultsKey))
        XCTAssertEqual(MouseButtonShortcut.buttonNumber(forKeyCode: storedButton.keyCode), 3)
        XCTAssertEqual(storedButton.modifierFlags, [.option])

        view.isRecording = true
        NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option],
                                                       timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                       characters: "f", charactersIgnoringModifiers: "f",
                                                       isARepeat: false, keyCode: UInt16(kVK_ANSI_F))))

        XCTAssertFalse(view.isRecording)
        let storedKey = try XCTUnwrap(ShortcutCycle.shortcut(forDefaultsKey: defaultsKey))
        XCTAssertEqual(storedKey.keyCode, kVK_ANSI_F)
        XCTAssertEqual(storedKey.modifierFlags, [.control, .option])
    }

    func testPressesOutsideTheRecordersWindowAreNotRecorded() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [], backing: .buffered, defer: true)
        let view = WindowActionShortcutView()
        window.contentView?.addSubview(view)
        defer { view.isRecording = false }

        view.isRecording = true

        XCTAssertFalse(view.recordMouseButton(try buttonPress(3)))
        XCTAssertTrue(view.isRecording)
        XCTAssertNil(view.shortcutValue)
    }
}

class MouseButtonShortcutMonitorTests: XCTestCase {

    private final class EventMonitorSpy: EventMonitor {
        private(set) var running = false
        var filterer: ((NSEvent) -> Bool)?

        func start() {
            running = true
        }

        func stop() {
            running = false
        }
    }

    private final class Delivery {
        var swallowed = false
    }

    private var eventMonitor: EventMonitorSpy!

    override func setUp() {
        super.setUp()
        eventMonitor = EventMonitorSpy()
    }

    private func makeMonitor() -> MouseButtonShortcutMonitor {
        MouseButtonShortcutMonitor(makeEventMonitor: { [eventMonitor] filterer in
            eventMonitor!.filterer = filterer
            return eventMonitor!
        })
    }

    /// Delivers an event as the tap does, from a thread of its own, and
    /// returns whether it was swallowed. Waits without running the main run
    /// loop, so whatever the event queued on the main thread stays queued.
    private func deliver(_ type: CGEventType, _ buttonNumber: Int) throws -> Bool {
        let cgEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                            mouseCursorPosition: .zero, mouseButton: .center))
        cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        let filterer = try XCTUnwrap(eventMonitor.filterer)
        let delivery = Delivery()
        let delivered = DispatchSemaphore(value: 0)
        let tapThread = Thread {
            delivery.swallowed = filterer(event)
            delivered.signal()
        }
        tapThread.qualityOfService = .userInteractive
        tapThread.start()
        delivered.wait()
        return delivery.swallowed
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testListensOnlyWhileBoundOrUntilASwallowedPressIsReleased() throws {
        let monitor = makeMonitor()
        XCTAssertFalse(eventMonitor.running)

        monitor.bindShortcut(MouseButtonShortcut(buttonNumber: 3, modifierFlags: []), toAction: { _ in })
        XCTAssertTrue(eventMonitor.running)

        XCTAssertTrue(try deliver(.otherMouseDown, 3))
        monitor.breakAllBindings()
        XCTAssertTrue(eventMonitor.running)

        XCTAssertTrue(try deliver(.otherMouseUp, 3))
        drainMainQueue()
        XCTAssertFalse(eventMonitor.running)
    }

    func testBoundPressRunsItsActionOnce() throws {
        let monitor = makeMonitor()
        var presses = 0
        monitor.bindShortcut(MouseButtonShortcut(buttonNumber: 3, modifierFlags: []), toAction: { _ in presses += 1 })

        XCTAssertTrue(try deliver(.otherMouseDown, 3))
        XCTAssertTrue(try deliver(.otherMouseUp, 3))
        XCTAssertFalse(try deliver(.otherMouseDown, 4))
        drainMainQueue()

        XCTAssertEqual(presses, 1)
    }

    func testPressQueuedBeforeShortcutsStandDownDoesNotRun() throws {
        let monitor = makeMonitor()
        var presses = 0
        monitor.bindShortcut(MouseButtonShortcut(buttonNumber: 3, modifierFlags: []), toAction: { _ in presses += 1 })

        XCTAssertTrue(try deliver(.otherMouseDown, 3))
        monitor.breakAllBindings()
        drainMainQueue()

        XCTAssertEqual(presses, 0)
        XCTAssertTrue(try deliver(.otherMouseUp, 3))
    }

    func testQueuedStopDoesNotOutliveANewBinding() throws {
        let monitor = makeMonitor()
        let shortcut = MouseButtonShortcut(buttonNumber: 3, modifierFlags: [])
        monitor.bindShortcut(shortcut, toAction: { _ in })

        XCTAssertTrue(try deliver(.otherMouseDown, 3))
        monitor.breakAllBindings()
        XCTAssertTrue(try deliver(.otherMouseUp, 3))
        monitor.bindShortcut(shortcut, toAction: { _ in })
        drainMainQueue()

        XCTAssertTrue(eventMonitor.running)
    }
}

class ShortcutCycleTests: XCTestCase {

    private func shortcut(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: flags)
    }

    func testSideShortcutActionsKeepLegacyDefaultsKeys() {
        XCTAssertEqual(WindowAction.leftHalf.name, "leftHalf")
        XCTAssertEqual(WindowAction.rightHalf.name, "rightHalf")
        XCTAssertEqual(WindowAction.centerHalf.name, "centerHalf")
        XCTAssertEqual(WindowAction.topHalf.name, "topHalf")
        XCTAssertEqual(WindowAction.bottomHalf.name, "bottomHalf")
    }

    func testRenamedSideShortcutAliasSyncWritesLegacyDefaultsKey() {
        let suiteName = "ShortcutCycleTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let centerSectionShortcut = shortcut(1, [.option, .command])
        let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let shortcutDict = dictTransformer.reverseTransformedValue(centerSectionShortcut)
        userDefaults.setValue(shortcutDict, forKey: "centerSection")

        MASShortcutMigration.syncRenamedSideShortcutAliases(userDefaults: userDefaults)

        XCTAssertNil(userDefaults.object(forKey: "centerSection"))
        XCTAssertNotNil(userDefaults.object(forKey: "centerHalf"))
        XCTAssertNotNil(ShortcutCycle.shortcut(for: .centerHalf, userDefaults: userDefaults))

        let updatedCenterHalfShortcut = shortcut(2, [.option, .command])
        let updatedShortcutDict = dictTransformer.reverseTransformedValue(updatedCenterHalfShortcut)
        userDefaults.setValue(updatedShortcutDict, forKey: "centerHalf")

        MASShortcutMigration.syncRenamedSideShortcutAliases(userDefaults: userDefaults)
        XCTAssertEqual(ShortcutCycle.shortcut(for: .centerHalf, userDefaults: userDefaults)?.keyCode, updatedCenterHalfShortcut.keyCode)
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
