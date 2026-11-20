/// EnhancedUITests.swift

import XCTest
@testable import Rectangle

class EnhancedUITests: XCTestCase {
    private func adjustmentEvents(
        mode: EnhancedUI,
        bundleIdentifier: String? = "com.google.Chrome",
        builtInAssistiveTechnologyEnabled: Bool = false,
        initialEnhancedUI: Bool?
    ) -> [String] {
        var events = [String]()
        mode.performWindowAdjustment(
            bundleIdentifier: bundleIdentifier,
            builtInAssistiveTechnologyEnabled: builtInAssistiveTechnologyEnabled,
            readEnhancedUI: {
                events.append("read")
                return initialEnhancedUI
            },
            writeEnhancedUI: { events.append("write:\($0)") },
            adjustment: { events.append("adjust") }
        )
        return events
    }

    func testAutomaticModeLeavesEnhancedUIDisabledForChromium() {
        XCTAssertEqual(
            adjustmentEvents(mode: .automatic, initialEnhancedUI: true),
            ["read", "write:false", "adjust"]
        )
    }

    func testAutomaticModeRestoresEnhancedUIForOtherApps() {
        XCTAssertEqual(
            adjustmentEvents(
                mode: .automatic,
                bundleIdentifier: "com.apple.Safari",
                initialEnhancedUI: true
            ),
            ["read", "write:false", "adjust", "write:true"]
        )
        XCTAssertEqual(
            adjustmentEvents(
                mode: .automatic,
                bundleIdentifier: nil,
                initialEnhancedUI: true
            ),
            ["read", "write:false", "adjust", "write:true"]
        )
    }

    func testAutomaticModeRestoresEnhancedUIForBuiltInAssistiveTechnology() {
        XCTAssertEqual(
            adjustmentEvents(
                mode: .automatic,
                builtInAssistiveTechnologyEnabled: true,
                initialEnhancedUI: true
            ),
            ["read", "write:false", "adjust", "write:true"]
        )
    }

    func testExplicitModesKeepTheirExistingRestoreBehavior() {
        XCTAssertEqual(
            adjustmentEvents(mode: .disableEnable, initialEnhancedUI: true),
            ["read", "write:false", "adjust", "write:true"]
        )
        XCTAssertEqual(
            adjustmentEvents(mode: .disableOnly, initialEnhancedUI: true),
            ["read", "write:false", "adjust"]
        )
        XCTAssertEqual(
            adjustmentEvents(mode: .frontmostDisable, initialEnhancedUI: true),
            ["read", "write:false", "adjust"]
        )
    }

    func testDisabledOrUnavailableEnhancedUIDoesNotWrite() {
        XCTAssertEqual(
            adjustmentEvents(mode: .automatic, initialEnhancedUI: false),
            ["read", "adjust"]
        )
        XCTAssertEqual(
            adjustmentEvents(mode: .automatic, initialEnhancedUI: nil),
            ["read", "adjust"]
        )
    }

    func testApplicationActivationPolicy() {
        XCTAssertTrue(
            EnhancedUI.automatic.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: "com.google.Chrome",
                builtInAssistiveTechnologyEnabled: false
            )
        )
        XCTAssertFalse(
            EnhancedUI.automatic.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: "com.google.Chrome",
                builtInAssistiveTechnologyEnabled: true
            )
        )
        XCTAssertFalse(
            EnhancedUI.automatic.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: "com.apple.Safari",
                builtInAssistiveTechnologyEnabled: false
            )
        )
        XCTAssertFalse(
            EnhancedUI.automatic.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: nil,
                builtInAssistiveTechnologyEnabled: false
            )
        )
        XCTAssertTrue(
            EnhancedUI.frontmostDisable.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: "com.apple.Safari",
                builtInAssistiveTechnologyEnabled: true
            )
        )
        XCTAssertFalse(
            EnhancedUI.disableEnable.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: "com.google.Chrome",
                builtInAssistiveTechnologyEnabled: false
            )
        )
        XCTAssertFalse(
            EnhancedUI.disableOnly.disablesEnhancedUIOnApplicationActivation(
                bundleIdentifier: "com.google.Chrome",
                builtInAssistiveTechnologyEnabled: false
            )
        )
    }

    func testKnownChromiumBrowserBundleIdentifiers() {
        let matchingBundleIdentifiers = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.chromium.Chromium",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Beta",
            "com.brave.Browser",
            "com.brave.Browser.nightly",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
            "com.operasoftware.OperaNext",
            "com.operasoftware.OperaDeveloper",
            "com.operasoftware.OperaNightly",
            "com.operasoftware.OperaGX",
            "com.operasoftware.OperaGXNext",
            "com.operasoftware.OperaGXDeveloper",
            "com.operasoftware.OperaGXNightly",
            "company.thebrowser.Browser",
            "company.thebrowser.dia",
            "ai.perplexity.comet",
            "com.openai.atlas"
        ]
        let nonmatchingBundleIdentifiers: [String?] = [
            nil,
            "com.apple.Safari",
            "com.google.Chromecast",
            "com.google.ChromeHelper",
            "com.brave.BrowserHelper"
        ]

        for bundleIdentifier in matchingBundleIdentifiers {
            XCTAssertTrue(EnhancedUI.isKnownChromiumBrowser(bundleIdentifier: bundleIdentifier))
        }
        for bundleIdentifier in nonmatchingBundleIdentifiers {
            XCTAssertFalse(EnhancedUI.isKnownChromiumBrowser(bundleIdentifier: bundleIdentifier))
        }
    }

    func testEnhancedUIPreferenceMigrationAndRawValues() {
        let key = "RectangleTests.enhancedUI.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let absentPreference = IntEnumDefault<EnhancedUI>(
            key: key,
            defaultValue: .automatic,
            invalidValueFallback: .disableEnable
        )
        XCTAssertEqual(absentPreference.value.rawValue, 4)

        UserDefaults.standard.set(0, forKey: key)
        let legacyZeroPreference = IntEnumDefault<EnhancedUI>(
            key: key,
            defaultValue: .automatic,
            invalidValueFallback: .disableEnable
        )
        XCTAssertEqual(legacyZeroPreference.value.rawValue, 1)

        for rawValue in 1...4 {
            UserDefaults.standard.set(rawValue, forKey: key)
            let preference = IntEnumDefault<EnhancedUI>(
                key: key,
                defaultValue: .automatic,
                invalidValueFallback: .disableEnable
            )
            XCTAssertEqual(preference.value.rawValue, rawValue)
        }

        legacyZeroPreference.load(from: CodableDefault(int: 0))
        XCTAssertEqual(legacyZeroPreference.value.rawValue, 1)
    }
}

@MainActor
final class TitleBarTabButtonPressSchedulingTests: XCTestCase {
    private func mouseEvent(_ type: CGEventType, window: CGWindowID = 42) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                        mouseCursorPosition: CGPoint(x: 20, y: 20), mouseButton: .left))
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    func testWindowOwnerLookupRunsOnWorker() throws {
        let worker = DispatchQueue(label: "titlebar-test-owner")
        let key = DispatchSpecificKey<Bool>()
        worker.setSpecific(key: key, value: true)
        let lookedUp = expectation(description: "owner resolved off input thread")
        let press = TitleBarTabButtonPress(worker: worker) { window in
            XCTAssertEqual(window, 42)
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), true)
            XCTAssertFalse(Thread.isMainThread)
            lookedUp.fulfill()
            return nil
        }
        press.handle(try mouseEvent(.leftMouseDown)) { XCTFail("mouse-down must not perform an action") }
        wait(for: [lookedUp], timeout: 1)
        press.stop()
    }

    func testDragCancelsQueuedLookupBeforeItContactsWindowServer() throws {
        let worker = DispatchQueue(label: "titlebar-test-drag")
        let press = TitleBarTabButtonPress(worker: worker) { _ in
            XCTFail("cancelled click must not resolve or hit-test its window")
            return nil
        }
        let down = try mouseEvent(.leftMouseDown)
        let drag = try mouseEvent(.leftMouseDragged)
        worker.suspend()
        press.handle(down) {}
        press.handle(drag) {}
        let drained = expectation(description: "cancelled worker request drained")
        worker.async { drained.fulfill() }
        worker.resume()
        wait(for: [drained], timeout: 1)
        press.stop()
    }

    func testNewClickSkipsOldLookupAndResolvesTheNewEventWindow() throws {
        let worker = DispatchQueue(label: "titlebar-test-replacement")
        let lookedUp = expectation(description: "only replacement click resolved")
        let press = TitleBarTabButtonPress(worker: worker) { window in
            XCTAssertEqual(window, 43)
            lookedUp.fulfill()
            return nil
        }
        let oldDown = try mouseEvent(.leftMouseDown)
        let newDown = try mouseEvent(.leftMouseDown, window: 43)
        worker.suspend()
        press.handle(oldDown) {}
        press.handle(newDown) {}
        worker.resume()
        wait(for: [lookedUp], timeout: 1)
        press.stop()
    }
}

@MainActor
final class TitleBarHitTestApplicationTests: XCTestCase {
    func testOwnWindowNeverStartsAnAccessibilityHitTest() throws {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 320, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }
        let id = CGWindowID(window.windowNumber)
        let owner = try XCTUnwrap(WindowUtil.getWindowList(ids: [id], forceRefresh: true).first { $0.id == id })
        XCTAssertEqual(owner.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertNil(TitleBarManager.hitTestApplication(window: id))
    }

    func testUnknownWindowDoesNotFallBackToSystemWideHitTesting() {
        XCTAssertNil(TitleBarManager.hitTestApplication(window: 0))
        XCTAssertNil(TitleBarManager.hitTestApplication(window: CGWindowID.max))
    }
}

class TitleBarClickSequenceTests: XCTestCase {
    private func startedSequence() -> TitleBarClickSequence {
        let sequence = TitleBarClickSequence()
        sequence.mouseDown(window: 42, point: CGPoint(x: 20, y: 20), time: 1, count: 1, interval: 0.5)
        return sequence
    }

    func testNotificationHandledAfterMouseUpStillVetoesTabClose() throws {
        let sequence = startedSequence()
        sequence.mouseDown(window: 42, point: CGPoint(x: 20, y: 20), time: 1.1, count: 2, interval: 0.5)
        var result: Bool?
        let click = try XCTUnwrap(sequence.finish(window: 42) { result = $0 })
        let read = try XCTUnwrap(sequence.beginRead(at: 1.11, interval: 0.5))
        sequence.endRead(read, positive: true)
        XCTAssertNil(result)
        sequence.settle(click)
        XCTAssertEqual(result, true)
    }

    func testDecisionWaitsForClassificationStartedBeforeMouseUp() throws {
        let sequence = startedSequence()
        let read = try XCTUnwrap(sequence.beginRead(at: 1.01, interval: 0.5))
        var result: Bool?
        let click = try XCTUnwrap(sequence.finish(window: 42) { result = $0 })
        sequence.settle(click)
        XCTAssertNil(result)
        sequence.endRead(read, positive: true)
        XCTAssertEqual(result, true)
    }

    func testOrdinaryTitleBarClickRunsOnceAfterNegativeClassification() throws {
        let sequence = startedSequence()
        let read = try XCTUnwrap(sequence.beginRead(at: 1.01, interval: 0.5))
        var results: [Bool] = []
        let click = try XCTUnwrap(sequence.finish(window: 42) { results.append($0) })
        sequence.settle(click)
        sequence.endRead(read, positive: false)
        sequence.settle(click, timedOut: true)
        XCTAssertEqual(results, [false])
    }

    func testTimeoutDoesNotBlockTitleBarOrApplyLateResult() throws {
        let sequence = startedSequence()
        let read = try XCTUnwrap(sequence.beginRead(at: 1.01, interval: 0.5))
        var results: [Bool] = []
        let click = try XCTUnwrap(sequence.finish(window: 42) { results.append($0) })
        sequence.settle(click, timedOut: true)
        sequence.endRead(read, positive: true)
        XCTAssertEqual(results, [false])
    }

    func testNewClickCancelsOldDecisionAndIgnoresOldClassification() throws {
        let sequence = startedSequence()
        let read = try XCTUnwrap(sequence.beginRead(at: 1.01, interval: 0.5))
        var oldResult: Bool?
        let old = try XCTUnwrap(sequence.finish(window: 42) { oldResult = $0 })
        sequence.mouseDown(window: 43, point: .zero, time: 2, count: 1, interval: 0.5)
        sequence.endRead(read, positive: true)
        sequence.settle(old, timedOut: true)
        XCTAssertNil(oldResult)
        var result: Bool?
        let click = try XCTUnwrap(sequence.finish(window: 43) { result = $0 })
        sequence.settle(click)
        XCTAssertEqual(result, false)
    }

    func testResetCancelsPendingAction() throws {
        let sequence = startedSequence()
        var result: Bool?
        let click = try XCTUnwrap(sequence.finish(window: 42) { result = $0 })
        sequence.reset()
        sequence.settle(click, timedOut: true)
        XCTAssertNil(result)
    }

    func testSecondClickOnDifferentWindowOrOutsideIntervalResetsSequence() {
        for (window, time) in [(CGWindowID(43), 1.1), (CGWindowID(42), 1.6)] {
            let sequence = startedSequence()
            sequence.mouseDown(window: window, point: .zero, time: time, count: 2, interval: 0.5)
            XCTAssertNil(sequence.beginRead(at: time, interval: 0.5))
        }
    }
}

class TitleBarScreenDetectionTests: XCTestCase {
    private final class TestScreen: NSScreen {
        let testFrame: CGRect
        init(_ frame: CGRect) { testFrame = frame; super.init() }
        override var frame: NSRect { testFrame }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    func testClickedScreenPreservesDisplayCountOrderingAndNeighbors() throws {
        let left = TestScreen(CGRect(x: -1000, y: 0, width: 1000, height: 800))
        let right = TestScreen(CGRect(x: 0, y: 0, width: 1000, height: 800))
        let detection = ScreenDetection(screens: { [right, left] })
        let screens = try XCTUnwrap(detection.detectScreens(at: left))
        XCTAssertTrue(screens.currentScreen === left)
        XCTAssertEqual(screens.numScreens, 2)
        XCTAssertEqual(screens.screensOrdered, detection.order(screens: [right, left]))
        XCTAssertTrue(screens.adjacentScreens?.next === right)
        XCTAssertTrue(screens.adjacentScreens?.prev === right)
    }

    func testDisconnectedClickedScreenDoesNotBecomeSingleDisplayTopology() {
        let screen = TestScreen(CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertNil(ScreenDetection(screens: { [] }).detectScreens(at: screen))
    }

    func testClickScreenUsesAppKitCoordinatesIncludingNegativeOrigins() {
        let left = TestScreen(CGRect(x: -1000, y: 0, width: 1000, height: 800))
        let above = TestScreen(CGRect(x: 0, y: 800, width: 1000, height: 800))
        XCTAssertTrue(TitleBarManager.screenForClick(at: CGPoint(x: -50, y: 200), screens: [left, above]) === left)
        XCTAssertTrue(TitleBarManager.screenForClick(at: CGPoint(x: 50, y: 900), screens: [left, above]) === above)
        XCTAssertNil(TitleBarManager.screenForClick(at: CGPoint(x: 5000, y: 0), screens: [left, above]))
    }

    func testTitleBarDoubleClickSkipsIgnoredApps() {
        let slack = "com.tinyspeck.slackmacgap"
        XCTAssertFalse(TitleBarManager.isIgnored(bundleIdentifier: slack, disabledApps: nil, titleBarIgnoredApps: nil))
        XCTAssertTrue(TitleBarManager.isIgnored(bundleIdentifier: slack, disabledApps: [slack], titleBarIgnoredApps: nil))
        XCTAssertTrue(TitleBarManager.isIgnored(bundleIdentifier: slack, disabledApps: nil, titleBarIgnoredApps: [slack]))
        XCTAssertFalse(TitleBarManager.isIgnored(bundleIdentifier: slack, disabledApps: ["com.apple.Safari"],
                                                 titleBarIgnoredApps: ["com.microsoft.Outlook"]))
    }
}
