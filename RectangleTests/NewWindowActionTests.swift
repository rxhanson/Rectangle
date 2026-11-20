/// NewWindowActionTests.swift

import XCTest
@testable import Rectangle

final class NewWindowActionPolicyTests: XCTestCase {

    func testValuesFollowTheUrlSchemeShortcutNamesAndAliases() {
        XCTAssertEqual(NewWindowActionPolicy.action(named: "maximize"), .maximize)
        XCTAssertEqual(NewWindowActionPolicy.action(named: "left-half"), .leftHalf)
        XCTAssertEqual(NewWindowActionPolicy.action(named: "leftHalf"), .leftHalf)
        XCTAssertEqual(NewWindowActionPolicy.action(named: "left-side"), .leftHalf)
        XCTAssertEqual(NewWindowActionPolicy.action(named: " Almost-Maximize "), .almostMaximize)
    }

    func testUnsetOrUnknownValuesDisableTheFeature() {
        XCTAssertNil(NewWindowActionPolicy.action(named: nil))
        XCTAssertNil(NewWindowActionPolicy.action(named: ""))
        XCTAssertNil(NewWindowActionPolicy.action(named: "none"))
        XCTAssertNil(NewWindowActionPolicy.action(named: "full-screen"))
    }

    func testActionsThatArrangeOtherWindowsOrMoveDisplaysAreNotAccepted() {
        for name in ["tile-all", "cascade-all", "cascade-active-app", "tileRows", "reverse-all",
                     "cycle-stacked-windows", "left-todo", "restore",
                     "next-display", "previous-display", "display-two"] {
            XCTAssertNil(NewWindowActionPolicy.action(named: name), name)
        }
        XCTAssertEqual(NewWindowActionPolicy.action(named: "center-half"), .centerHalf)
    }

    private func candidate(pid: pid_t = 42, bundleIdentifier: String? = "com.example.app", windowId: CGWindowID? = 7,
                           isStandardWindow: Bool? = true, isSheet: Bool? = false, isMinimized: Bool? = false,
                           isFullScreen: Bool? = false, hasFrame: Bool = true) -> NewWindowActionPolicy.Candidate {
        NewWindowActionPolicy.Candidate(pid: pid, bundleIdentifier: bundleIdentifier, windowId: windowId,
                                        isStandardWindow: isStandardWindow, isSheet: isSheet,
                                        isMinimized: isMinimized, isFullScreen: isFullScreen, hasFrame: hasFrame)
    }

    private func applies(_ candidate: NewWindowActionPolicy.Candidate,
                         ignored: Set<String> = [], handled: Set<CGWindowID> = []) -> Bool {
        NewWindowActionPolicy.shouldApply(candidate, ownPid: 1,
                                          isIgnoredApp: { ignored.contains($0) },
                                          alreadyHandled: { handled.contains($0) })
    }

    func testAnOrdinaryWindowOfAnotherAppQualifies() {
        XCTAssertTrue(applies(candidate()))
    }

    func testOnlyStandardWindowsQualify() {
        XCTAssertFalse(applies(candidate(isStandardWindow: false)), "dialogs and palettes")
        XCTAssertFalse(applies(candidate(isStandardWindow: nil)), "unknown subrole")
        XCTAssertFalse(applies(candidate(isSheet: true)))
    }

    func testMinimizedFullScreenAndVanishedWindowsAreSkipped() {
        XCTAssertFalse(applies(candidate(isMinimized: true)))
        XCTAssertFalse(applies(candidate(isFullScreen: true)))
        XCTAssertFalse(applies(candidate(hasFrame: false)))
    }

    func testRectanglesOwnWindowsIgnoredAppsAndHandledWindowsAreSkipped() {
        XCTAssertFalse(applies(candidate(pid: 1)))
        XCTAssertFalse(applies(candidate(), ignored: ["com.example.app"]))
        XCTAssertFalse(applies(candidate(), handled: [7]))
    }

    func testAWindowWithoutAnIdIsStillHandled() {
        XCTAssertTrue(applies(candidate(windowId: nil), handled: [7]))
    }
}

final class NewWindowActionManagerTests: XCTestCase {

    private final class ValueBox<Value> {
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private final class TestWindow: AccessibilityElement {
        var standard: Bool? = true
        var sheet: Bool? = false
        var minimized: Bool? = false
        var fullScreen: Bool? = false
        var testFrame = CGRect(x: 20, y: 40, width: 640, height: 480)
        private let id: CGWindowID?

        init(id: CGWindowID?) {
            self.id = id
            super.init(AXUIElementCreateSystemWide())
        }

        override var isStandardWindow: Bool? { standard }
        override var isSheet: Bool? { sheet }
        override var isMinimized: Bool? { minimized }
        override var isFullScreen: Bool? { fullScreen }
        override var frame: CGRect { testFrame }
        override func getWindowId() -> CGWindowID? { id }
        // Wraps the system-wide element, so a timeout set here would become the process default.
        override func setMessagingTimeout(_ seconds: Float) {}
    }

    private final class ObserverSpy: WindowCreationObserving {
        private final class Token {}
        private(set) var attachedPids = [pid_t]()
        private var handlers = [pid_t: (AccessibilityElement) -> Void]()
        private var pendingReadiness = [pid_t: () -> Void]()
        private var failures = [pid_t: () -> Void]()
        var readyImmediately = true

        func observeWindowCreation(pid: pid_t, onReady: @escaping () -> Void,
                                   onWindowCreated: @escaping (AccessibilityElement) -> Void,
                                   onFailed: @escaping () -> Void) -> AnyObject? {
            attachedPids.append(pid)
            handlers[pid] = onWindowCreated
            failures[pid] = onFailed
            if readyImmediately {
                onReady()
            } else {
                pendingReadiness[pid] = onReady
            }
            return Token()
        }

        func becomeReady(_ pid: pid_t) {
            pendingReadiness.removeValue(forKey: pid)?()
        }

        func fail(_ pid: pid_t) {
            pendingReadiness.removeValue(forKey: pid)
            failures.removeValue(forKey: pid)?()
        }

        func failureHandler(for pid: pid_t) -> (() -> Void)? {
            failures[pid]
        }

        func windowCreated(_ window: AccessibilityElement, in pid: pid_t) {
            handlers[pid]?(window)
        }
    }

    private typealias App = NewWindowActionManager.Application

    private struct Harness {
        let manager: NewWindowActionManager
        let spy: ObserverSpy
        let actionName: ValueBox<String?>
        let executed: ValueBox<[ExecutionParameters]>
        let existingWindows: ValueBox<[pid_t: [AccessibilityElement]]>
        let ignoredApps: ValueBox<Set<String>>
        let mouseButtonDown: ValueBox<Bool>
        let notificationCenter: NotificationCenter
    }

    private func makeHarness(actionName: String? = "maximize",
                             apps: [App] = [App(pid: 100, bundleIdentifier: "com.example.one")],
                             existingWindows: [pid_t: [AccessibilityElement]] = [:],
                             readyImmediately: Bool = true) -> Harness {
        let spy = ObserverSpy()
        spy.readyImmediately = readyImmediately
        let actionName = ValueBox<String?>(actionName)
        let executed = ValueBox<[ExecutionParameters]>([])
        let existing = ValueBox(existingWindows)
        let ignored = ValueBox(Set<String>())
        let mouseButtonDown = ValueBox(false)
        let notificationCenter = NotificationCenter()
        let manager = NewWindowActionManager(
            ownPid: 1,
            delay: 0,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: NotificationCenter(),
            observers: spy,
            actionProvider: { NewWindowActionPolicy.action(named: actionName.value) },
            runningApplications: { apps },
            existingWindows: { existing.value[$0] ?? [] },
            isIgnoredApp: { ignored.value.contains($0) },
            execute: { executed.value.append($0) },
            schedule: { _, body in body() },
            isPrimaryMouseButtonDown: { mouseButtonDown.value }
        )
        return Harness(manager: manager, spy: spy, actionName: actionName, executed: executed,
                       existingWindows: existing, ignoredApps: ignored, mouseButtonDown: mouseButtonDown,
                       notificationCenter: notificationCenter)
    }

    func testNothingIsObservedWithoutAConfiguredAction() {
        let harness = makeHarness(actionName: nil)

        XCTAssertNil(harness.manager.action)
        XCTAssertTrue(harness.spy.attachedPids.isEmpty)
    }

    func testRegularAppsAreObservedExceptRectangleItself() {
        let harness = makeHarness(apps: [App(pid: 100, bundleIdentifier: "com.example.one"),
                                         App(pid: 200, bundleIdentifier: "com.example.menubar", isRegular: false),
                                         App(pid: 1, bundleIdentifier: "com.knollsoft.Rectangle")])

        XCTAssertEqual(harness.spy.attachedPids, [100])
        XCTAssertEqual(harness.manager.observedProcessIdentifiers, [100])
    }

    func testWindowsThatAlreadyExistAtStartupAreLeftAlone() {
        let harness = makeHarness(existingWindows: [100: [TestWindow(id: 5)]])

        XCTAssertTrue(harness.executed.value.isEmpty)
    }

    func testANewWindowGetsTheConfiguredAction() throws {
        let harness = makeHarness()
        let window = TestWindow(id: 7)

        harness.spy.windowCreated(window, in: 100)

        XCTAssertEqual(harness.executed.value.count, 1)
        let parameters = try XCTUnwrap(harness.executed.value.first)
        XCTAssertEqual(parameters.action, .maximize)
        XCTAssertTrue(parameters.windowElement === window)
        XCTAssertEqual(parameters.windowId, 7)
        XCTAssertEqual(parameters.source, .newWindow)
        XCTAssertTrue(parameters.preservesFocus)
    }

    func testEachWindowIsHandledOnce() {
        let harness = makeHarness()
        let window = TestWindow(id: 7)

        harness.spy.windowCreated(window, in: 100)
        harness.spy.windowCreated(window, in: 100)

        XCTAssertEqual(harness.executed.value.count, 1)
    }

    func testDialogsMinimizedFullScreenAndVanishedWindowsAreSkipped() {
        let harness = makeHarness()
        let dialog = TestWindow(id: 8)
        dialog.standard = false
        let minimized = TestWindow(id: 9)
        minimized.minimized = true
        let fullScreen = TestWindow(id: 10)
        fullScreen.fullScreen = true
        let vanished = TestWindow(id: 11)
        vanished.testFrame = .null

        for window in [dialog, minimized, fullScreen, vanished] {
            harness.spy.windowCreated(window, in: 100)
        }

        XCTAssertTrue(harness.executed.value.isEmpty)
    }

    func testIgnoredAppsAreSkipped() {
        let harness = makeHarness()
        harness.ignoredApps.value = ["com.example.one"]

        harness.spy.windowCreated(TestWindow(id: 7), in: 100)

        XCTAssertTrue(harness.executed.value.isEmpty)
    }

    func testWindowsALaunchingAppRestoresCountAsNew() {
        let harness = makeHarness(readyImmediately: false)
        let restored = [TestWindow(id: 31), TestWindow(id: 32)]
        harness.existingWindows.value[300] = restored

        harness.manager.applicationDidLaunch(App(pid: 300, bundleIdentifier: "com.example.three"))
        XCTAssertTrue(harness.executed.value.isEmpty, "nothing until the observer is attached")

        harness.spy.becomeReady(300)
        XCTAssertEqual(harness.executed.value.map(\.windowId), [31, 32])

        harness.spy.windowCreated(restored[0], in: 300)
        XCTAssertEqual(harness.executed.value.count, 2, "a window reported again is not placed twice")
    }

    func testTerminatedAppsAreNoLongerObserved() {
        let harness = makeHarness()

        harness.manager.applicationDidTerminate(pid: 100)
        harness.spy.windowCreated(TestWindow(id: 7), in: 100)

        XCTAssertTrue(harness.executed.value.isEmpty)
        XCTAssertTrue(harness.manager.observedProcessIdentifiers.isEmpty)
    }

    func testImportingAConfigReloadsTheSetting() {
        let harness = makeHarness(actionName: nil)
        XCTAssertTrue(harness.spy.attachedPids.isEmpty)

        harness.actionName.value = "center"
        harness.notificationCenter.post(name: .configImported, object: nil)

        XCTAssertEqual(harness.manager.action, .center)
        XCTAssertEqual(harness.spy.attachedPids, [100])
    }

    func testAFailedObserverIsAttachedAgainWhenTheAppIsNextActivated() {
        let harness = makeHarness(readyImmediately: false)
        let app = App(pid: 100, bundleIdentifier: "com.example.one")
        harness.existingWindows.value[100] = [TestWindow(id: 5)]

        harness.spy.fail(100)
        XCTAssertTrue(harness.manager.observedProcessIdentifiers.isEmpty)

        harness.manager.applicationDidActivate(app)
        harness.spy.becomeReady(100)
        XCTAssertEqual(harness.spy.attachedPids, [100, 100])
        XCTAssertTrue(harness.executed.value.isEmpty, "the windows it already has are the user's")

        harness.spy.windowCreated(TestWindow(id: 7), in: 100)
        XCTAssertEqual(harness.executed.value.map(\.windowId), [7])
    }

    func testActivatingAnObservedAppChangesNothing() {
        let harness = makeHarness()

        harness.manager.applicationDidActivate(App(pid: 100, bundleIdentifier: "com.example.one"))

        XCTAssertEqual(harness.spy.attachedPids, [100])
    }

    func testAppsStillLaunchingAtStartupWaitForTheirLaunchNotification() {
        let launching = App(pid: 100, bundleIdentifier: "com.example.one", isFinishedLaunching: false)
        let harness = makeHarness(apps: [launching], existingWindows: [100: [TestWindow(id: 5)]])
        XCTAssertTrue(harness.spy.attachedPids.isEmpty)

        harness.manager.applicationDidLaunch(App(pid: 100, bundleIdentifier: "com.example.one"))

        XCTAssertEqual(harness.spy.attachedPids, [100])
        XCTAssertEqual(harness.executed.value.map(\.windowId), [5], "windows restored while launching count as new")
    }

    func testAWindowThatAppearsDuringAMouseDragIsLeftAlone() {
        let harness = makeHarness()
        let tornOff = TestWindow(id: 7)

        harness.mouseButtonDown.value = true
        harness.spy.windowCreated(tornOff, in: 100)
        XCTAssertTrue(harness.executed.value.isEmpty)

        harness.mouseButtonDown.value = false
        harness.spy.windowCreated(TestWindow(id: 8), in: 100)
        XCTAssertEqual(harness.executed.value.map(\.windowId), [8])
    }

    /// An app the user opens is activated before it finishes launching; the launch
    /// notification must still bring in the windows it restored.
    func testWindowsOfAnAppActivatedWhileStillLaunchingCountAsNew() {
        let harness = makeHarness(readyImmediately: false)
        harness.existingWindows.value[300] = [TestWindow(id: 31)]

        harness.manager.applicationDidActivate(App(pid: 300, bundleIdentifier: "com.example.three", isFinishedLaunching: false))
        harness.manager.applicationDidLaunch(App(pid: 300, bundleIdentifier: "com.example.three"))
        XCTAssertTrue(harness.executed.value.isEmpty, "nothing until the observer is attached")

        harness.spy.becomeReady(300)

        XCTAssertEqual(harness.spy.attachedPids, [100, 300], "the launch notification upgrades the observation instead of attaching again")
        XCTAssertEqual(harness.executed.value.map(\.windowId), [31])
    }

    func testALaunchNotificationAfterTheObserverIsReadyPlacesTheRestoredWindows() {
        let harness = makeHarness()

        harness.manager.applicationDidActivate(App(pid: 300, bundleIdentifier: "com.example.three", isFinishedLaunching: false))
        XCTAssertTrue(harness.executed.value.isEmpty)

        harness.existingWindows.value[300] = [TestWindow(id: 31), TestWindow(id: 32)]
        harness.manager.applicationDidLaunch(App(pid: 300, bundleIdentifier: "com.example.three"))

        XCTAssertEqual(harness.spy.attachedPids, [100, 300])
        XCTAssertEqual(harness.executed.value.map(\.windowId), [31, 32])
    }

    func testAStaleFailureDoesNotDropAReplacedObservation() {
        let harness = makeHarness(readyImmediately: false)
        let stale = harness.spy.failureHandler(for: 100)

        harness.notificationCenter.post(name: .configImported, object: nil)
        XCTAssertEqual(harness.spy.attachedPids, [100, 100])

        stale?()

        XCTAssertEqual(harness.manager.observedProcessIdentifiers, [100])
    }
}
