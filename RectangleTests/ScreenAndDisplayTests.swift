/// ScreenAndDisplayTests.swift

import XCTest
@testable import Rectangle

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

final class DockVisibleFrameTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visibleWithoutDock = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testAddsMissingBottomDockInset() {
        let dock = CGRect(x: 400, y: 8, width: 640, height: 62)

        XCTAssertEqual(
            corrected(visibleFrame: visibleWithoutDock, dockFrame: dock),
            CGRect(x: 0, y: 70, width: 1440, height: 805)
        )
    }

    func testAddsMissingLeftDockInset() {
        let dock = CGRect(x: 8, y: 180, width: 62, height: 540)

        XCTAssertEqual(
            corrected(visibleFrame: visibleWithoutDock, dockFrame: dock),
            CGRect(x: 70, y: 0, width: 1370, height: 875)
        )
    }

    func testAddsMissingRightDockInset() {
        let dock = CGRect(x: 1370, y: 180, width: 62, height: 540)

        XCTAssertEqual(
            corrected(visibleFrame: visibleWithoutDock, dockFrame: dock),
            CGRect(x: 0, y: 0, width: 1370, height: 875)
        )
    }

    func testPreservesAccurateAppKitInsetWhenDockFrameDiffersSlightly() {
        let reportedVisibleFrame = CGRect(x: 0, y: 60, width: 1440, height: 815)
        let dock = CGRect(x: 30, y: 10, width: 1380, height: 53)

        XCTAssertEqual(
            corrected(visibleFrame: reportedVisibleFrame, dockFrame: dock),
            reportedVisibleFrame
        )
    }

    func testPreservesPlausibleAppKitInsetWhenAXDiffersMaterially() {
        let reportedVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)
        let dock = CGRect(x: 400, y: 8, width: 640, height: 32)

        XCTAssertEqual(
            corrected(visibleFrame: reportedVisibleFrame, dockFrame: dock),
            reportedVisibleFrame
        )
    }

    func testReclaimsPhantomInsetAfterDockMovesToAnotherDisplay() {
        let externalScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let dock = CGRect(x: 1740, y: 8, width: 1320, height: 62)
        let staleVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)

        XCTAssertEqual(
            corrected(
                visibleFrame: staleVisibleFrame,
                screenFrames: [screen, externalScreen],
                dockFrame: dock
            ),
            visibleWithoutDock
        )
    }

    func testCorrectsNewDockDisplayAfterMove() {
        let externalScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let externalVisibleFrame = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let dock = CGRect(x: 1740, y: 8, width: 1320, height: 62)

        XCTAssertEqual(
            DockUtil.correctedVisibleFrame(
                screenFrame: externalScreen,
                visibleFrame: externalVisibleFrame,
                screenFrames: [screen, externalScreen],
                dockFrame: dock,
                dockAutoHideEnabled: false
            ),
            CGRect(x: 1440, y: 70, width: 1920, height: 985)
        )
    }

    func testAutoHideReclaimsStaleInsetAndPreservesSmallRevealBoundary() {
        let reportedVisibleFrame = CGRect(x: 70, y: 4, width: 1370, height: 871)

        XCTAssertEqual(
            corrected(
                visibleFrame: reportedVisibleFrame,
                dockFrame: nil,
                dockAutoHideEnabled: true
            ),
            CGRect(x: 0, y: 4, width: 1440, height: 871)
        )
    }

    func testAutoHideReclaimsStaleBottomInset() {
        let reportedVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)

        XCTAssertEqual(
            corrected(
                visibleFrame: reportedVisibleFrame,
                dockFrame: nil,
                dockAutoHideEnabled: true
            ),
            visibleWithoutDock
        )
    }

    func testLiveDockClearsStaleWrongEdgeInset() {
        let staleLeftDockFrame = CGRect(x: 4, y: 0, width: 1436, height: 875)
        let currentBottomDock = CGRect(x: 400, y: 8, width: 640, height: 62)

        XCTAssertEqual(
            corrected(visibleFrame: staleLeftDockFrame, dockFrame: currentBottomDock),
            CGRect(x: 0, y: 70, width: 1440, height: 805)
        )
    }

    func testUnreadableDockKeepsReportedFrame() {
        let reportedVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)

        XCTAssertEqual(
            corrected(visibleFrame: reportedVisibleFrame, dockFrame: nil),
            reportedVisibleFrame
        )
    }

    func testCenteredDockFrameIsIgnored() {
        let reportedVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)
        let invalidDock = CGRect(x: 400, y: 300, width: 640, height: 62)

        XCTAssertEqual(
            corrected(visibleFrame: reportedVisibleFrame, dockFrame: invalidDock),
            reportedVisibleFrame
        )
    }

    func testOversizedDockFrameIsIgnoredBeforeReclaimingAnotherDisplay() {
        let externalScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let invalidDock = CGRect(x: 1440, y: 0, width: 1920, height: 500)
        let reportedVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)

        XCTAssertEqual(
            corrected(
                visibleFrame: reportedVisibleFrame,
                screenFrames: [screen, externalScreen],
                dockFrame: invalidDock
            ),
            reportedVisibleFrame
        )
    }

    func testCorrectsDockOnNegativeOriginDisplay() {
        let externalScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let externalVisibleFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let dock = CGRect(x: -1912, y: 240, width: 62, height: 600)

        XCTAssertEqual(
            DockUtil.correctedVisibleFrame(
                screenFrame: externalScreen,
                visibleFrame: externalVisibleFrame,
                screenFrames: [externalScreen, screen],
                dockFrame: dock,
                dockAutoHideEnabled: false
            ),
            CGRect(x: -1850, y: 0, width: 1850, height: 1055)
        )
    }

    func testAmbiguousDockHostIsIgnored() {
        let upperScreen = CGRect(x: 0, y: 900, width: 1440, height: 900)
        let ambiguousDock = CGRect(x: 400, y: 870, width: 640, height: 60)
        let reportedVisibleFrame = CGRect(x: 0, y: 75, width: 1440, height: 800)

        XCTAssertEqual(
            corrected(
                visibleFrame: reportedVisibleFrame,
                screenFrames: [screen, upperScreen],
                dockFrame: ambiguousDock
            ),
            reportedVisibleFrame
        )
    }

    func testCombinedDisplayFrameRetainsOuterBottomDockInset() {
        let combinedScreen = CGRect(x: 0, y: 0, width: 3360, height: 1080)
        let combinedVisibleFrame = CGRect(x: 0, y: 0, width: 3360, height: 1055)
        let dock = CGRect(x: 400, y: 8, width: 640, height: 62)

        XCTAssertEqual(
            DockUtil.correctedVisibleFrame(
                screenFrame: combinedScreen,
                visibleFrame: combinedVisibleFrame,
                screenFrames: [combinedScreen],
                dockFrame: dock,
                dockAutoHideEnabled: false
            ),
            CGRect(x: 0, y: 70, width: 3360, height: 985)
        )
    }

    private func corrected(visibleFrame: CGRect,
                           screenFrames: [CGRect]? = nil,
                           dockFrame: CGRect?,
                           dockAutoHideEnabled: Bool = false) -> CGRect {
        DockUtil.correctedVisibleFrame(
            screenFrame: screen,
            visibleFrame: visibleFrame,
            screenFrames: screenFrames ?? [screen],
            dockFrame: dockFrame,
            dockAutoHideEnabled: dockAutoHideEnabled
        )
    }
}

final class ScreenEdgeGapTests: XCTestCase {
    private let notchedScreen = TestScreen(notchHeight: 32)
    private let screenWithoutNotch = TestScreen(notchHeight: 0)
    private var savedDefaults: [(Default, CodableDefault)] = []

    override func setUp() {
        super.setUp()
        let settings: [(Default, CodableDefault)] = [
            (Defaults.combinedDisplayMode, CodableDefault(int: 2)),
            (Defaults.screenEdgeGapsOnMainScreenOnly, CodableDefault(bool: false)),
            (Defaults.screenEdgeGapTop, CodableDefault(float: 30)),
            (Defaults.screenEdgeGapTopNotch, CodableDefault(double: -1))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        super.tearDown()
    }

    func testUnsetNotchGapFallsBackToTopGap() {
        XCTAssertEqual(topGap(on: notchedScreen), 30)
        XCTAssertEqual(topGap(on: screenWithoutNotch), 30)
    }

    func testZeroNotchGapRemovesTopGapOnNotchedScreensOnly() {
        Defaults.screenEdgeGapTopNotch.value = 0

        XCTAssertEqual(topGap(on: notchedScreen), 0)
        XCTAssertEqual(topGap(on: screenWithoutNotch), 30)
    }

    func testNotchGapReplacesTopGapOnNotchedScreensOnly() {
        Defaults.screenEdgeGapTopNotch.value = 10

        XCTAssertEqual(topGap(on: notchedScreen), 10)
        XCTAssertEqual(topGap(on: screenWithoutNotch), 30)
    }

    func testFreshInstallTreatsNotchGapAsUnset() {
        let key = Defaults.screenEdgeGapTopNotch.key
        let stored = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(stored, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(DoubleDefault(key: key, defaultValue: -1).value, -1)
    }

    func testUnsetAndZeroNotchGapSurviveReloadAndConfigRoundTrip() throws {
        let notchGap = Defaults.screenEdgeGapTopNotch
        XCTAssertEqual(DoubleDefault(key: notchGap.key, defaultValue: -1).value, -1)
        let exportedUnset = try exportedNotchGap()
        XCTAssertEqual(exportedUnset.double, -1)

        notchGap.value = 0
        XCTAssertEqual(DoubleDefault(key: notchGap.key, defaultValue: -1).value, 0)
        let exportedZero = try exportedNotchGap()
        XCTAssertEqual(exportedZero.double, 0)

        notchGap.load(from: exportedUnset)
        XCTAssertEqual(notchGap.value, -1)
        XCTAssertEqual(topGap(on: notchedScreen), 30)

        notchGap.load(from: exportedZero)
        XCTAssertEqual(notchGap.value, 0)
        XCTAssertEqual(topGap(on: notchedScreen), 0)
    }

    func testLegacyFloatZeroStillFallsBackToTopGap() {
        let notchGap = Defaults.screenEdgeGapTopNotch
        notchGap.value = 10

        notchGap.load(from: CodableDefault(float: 0))
        XCTAssertEqual(notchGap.value, -1)
        XCTAssertEqual(topGap(on: notchedScreen), 30)

        notchGap.load(from: CodableDefault(float: 5))
        XCTAssertEqual(notchGap.value, 5)
        XCTAssertEqual(topGap(on: notchedScreen), 5)
    }

    private func topGap(on screen: NSScreen) -> CGFloat {
        screen.visibleFrame.maxY - screen.adjustedVisibleFrame().maxY
    }

    private func exportedNotchGap() throws -> CodableDefault {
        let json = try XCTUnwrap(Defaults.encoded())
        let config = try XCTUnwrap(Defaults.convert(jsonString: json))
        return try XCTUnwrap(config.defaults[Defaults.screenEdgeGapTopNotch.key])
    }

    private final class TestScreen: NSScreen {
        private let notchHeight: CGFloat

        init(notchHeight: CGFloat) {
            self.notchHeight = notchHeight
            super.init()
        }

        override var frame: NSRect { CGRect(x: 0, y: 0, width: 1512, height: 982) }
        override var visibleFrame: NSRect { CGRect(x: 0, y: 0, width: 1512, height: 950) }
        override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets(top: notchHeight, left: 0, bottom: 0, right: 0) }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }
}

final class MenuBarUtilTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private let visibleBelowMenuBar = CGRect(x: 0, y: 0, width: 1280, height: 777)

    func testExtendsFrameToTopOfScreen() {
        XCTAssertEqual(extended(visibleBelowMenuBar), screen)
    }

    func testStopsBelowNotch() {
        let notchedScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 918)

        XCTAssertEqual(
            extended(visibleFrame, screenFrame: notchedScreen, topSafeAreaInset: 32),
            CGRect(x: 0, y: 0, width: 1512, height: 950)
        )
    }

    func testLeavesFrameAlreadyAtTopOfScreenAlone() {
        XCTAssertEqual(extended(screen), screen)
    }

    func testLeavesFrameAlreadyBelowNotchAlone() {
        let notchedScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 950)

        XCTAssertEqual(extended(visibleFrame, screenFrame: notchedScreen, topSafeAreaInset: 32), visibleFrame)
    }

    func testNeverShrinksFrame() {
        let tallerThanScreen = CGRect(x: 0, y: 0, width: 1280, height: 820)

        XCTAssertEqual(extended(tallerThanScreen), tallerThanScreen)
    }

    func testPreservesDockInsets() {
        let bottomDock = CGRect(x: 0, y: 70, width: 1280, height: 707)
        XCTAssertEqual(extended(bottomDock), CGRect(x: 0, y: 70, width: 1280, height: 730))

        let sideDocks = CGRect(x: 70, y: 0, width: 1140, height: 777)
        XCTAssertEqual(extended(sideDocks), CGRect(x: 70, y: 0, width: 1140, height: 800))
    }

    func testKeepsOriginOfSecondaryDisplays() {
        let rightScreen = CGRect(x: 1280, y: 0, width: 1920, height: 1080)
        let rightVisibleFrame = CGRect(x: 1280, y: 0, width: 1920, height: 1055)
        XCTAssertEqual(extended(rightVisibleFrame, screenFrame: rightScreen), rightScreen)

        let upperScreen = CGRect(x: 0, y: 800, width: 1920, height: 1080)
        let upperVisibleFrame = CGRect(x: 0, y: 800, width: 1920, height: 1055)
        XCTAssertEqual(extended(upperVisibleFrame, screenFrame: upperScreen), upperScreen)
    }

    func testNullFramesPassThrough() {
        XCTAssertTrue(extended(.null).isNull)
        XCTAssertEqual(extended(visibleBelowMenuBar, screenFrame: .null), visibleBelowMenuBar)
    }

    private func extended(_ visibleFrame: CGRect,
                          screenFrame: CGRect? = nil,
                          topSafeAreaInset: CGFloat = 0) -> CGRect {
        MenuBarUtil.frameIgnoringMenuBar(visibleFrame, screenFrame: screenFrame ?? screen, topSafeAreaInset: topSafeAreaInset)
    }
}

final class IgnoreMenuBarTests: XCTestCase {
    private let screen = TestScreen(notchHeight: 0)
    private let notchedScreen = TestScreen(notchHeight: 32)
    private var savedDefaults: [(Default, CodableDefault)] = []
    private var storedIgnoreMenuBar: Any?

    override func setUp() {
        super.setUp()
        storedIgnoreMenuBar = UserDefaults.standard.object(forKey: Defaults.ignoreMenuBar.key)
        let settings: [(Default, CodableDefault)] = [
            (Defaults.combinedDisplayMode, CodableDefault(int: 2)),
            (Defaults.screenEdgeGapsOnMainScreenOnly, CodableDefault(bool: false)),
            (Defaults.screenEdgeGapTop, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapTopNotch, CodableDefault(double: -1)),
            (Defaults.ignoreMenuBar, CodableDefault(int: 0))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        UserDefaults.standard.set(storedIgnoreMenuBar, forKey: Defaults.ignoreMenuBar.key)
        super.tearDown()
    }

    func testMenuBarStaysReservedByDefault() {
        XCTAssertEqual(topEdge(of: screen), 777)
        XCTAssertEqual(topEdge(of: notchedScreen), 950)
    }

    func testEnabledOptionUsesFullScreenHeight() {
        Defaults.ignoreMenuBar.enabled = true

        XCTAssertEqual(topEdge(of: screen), 800)
    }

    func testEnabledOptionStopsBelowNotch() {
        Defaults.ignoreMenuBar.enabled = true

        XCTAssertEqual(topEdge(of: notchedScreen), 950)
    }

    func testDisabledOptionKeepsMenuBarReserved() {
        Defaults.ignoreMenuBar.enabled = false

        XCTAssertEqual(topEdge(of: screen), 777)
    }

    func testTopGapAppliesOnTopOfFullHeight() {
        Defaults.ignoreMenuBar.enabled = true
        Defaults.screenEdgeGapTop.value = 10

        XCTAssertEqual(topEdge(of: screen), 790)
    }

    func testNotchGapAppliesBelowNotch() {
        Defaults.ignoreMenuBar.enabled = true
        Defaults.screenEdgeGapTop.value = 10
        Defaults.screenEdgeGapTopNotch.value = 4

        XCTAssertEqual(topEdge(of: notchedScreen), 946)
        XCTAssertEqual(topEdge(of: screen), 790)
    }

    func testTerminalBoolValueEnablesOption() {
        let key = Defaults.ignoreMenuBar.key
        let stored = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(stored, forKey: key) }

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(OptionalBoolDefault(key: key).userEnabled)

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(OptionalBoolDefault(key: key).userEnabled)

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(OptionalBoolDefault(key: key).notSet)
    }

    func testOptionSurvivesConfigRoundTrip() throws {
        let option = Defaults.ignoreMenuBar
        option.enabled = true
        let exportedEnabled = try exportedIgnoreMenuBar()
        XCTAssertEqual(exportedEnabled.int, 1)

        option.enabled = nil
        XCTAssertEqual(topEdge(of: screen), 777)

        option.load(from: exportedEnabled)
        XCTAssertTrue(option.userEnabled)
        XCTAssertEqual(topEdge(of: screen), 800)
    }

    // The Dock correction runs against the live Dock, so only the top edge is asserted here;
    // MenuBarUtilTests cover the rest of the rect.
    private func topEdge(of screen: NSScreen) -> CGFloat {
        screen.adjustedVisibleFrame(true, true).maxY
    }

    private func exportedIgnoreMenuBar() throws -> CodableDefault {
        let json = try XCTUnwrap(Defaults.encoded())
        let config = try XCTUnwrap(Defaults.convert(jsonString: json))
        return try XCTUnwrap(config.defaults[Defaults.ignoreMenuBar.key])
    }

    private final class TestScreen: NSScreen {
        private let notchHeight: CGFloat

        init(notchHeight: CGFloat) {
            self.notchHeight = notchHeight
            super.init()
        }

        override var frame: NSRect {
            notchHeight > 0 ? CGRect(x: 0, y: 0, width: 1512, height: 982) : CGRect(x: 0, y: 0, width: 1280, height: 800)
        }
        override var visibleFrame: NSRect {
            // Notched displays reserve exactly the notch band for the menu bar.
            notchHeight > 0 ? CGRect(x: 0, y: 0, width: 1512, height: 950) : CGRect(x: 0, y: 0, width: 1280, height: 777)
        }
        override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets(top: notchHeight, left: 0, bottom: 0, right: 0) }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }
}

class DisplayMoveFocusTests: XCTestCase {

    private final class FocusTrackingElement: AccessibilityElement {
        private(set) var bringToFrontCalls = 0

        init() {
            super.init(AXUIElementCreateSystemWide())
        }

        override func bringToFront(force: Bool = false) {
            bringToFrontCalls += 1
        }
    }

    func testMovingAcrossDisplaysBringsTheWindowForwardUnlessFocusIsPreserved() throws {
        let previousMoveCursor = Defaults.moveCursorAcrossDisplays.enabled
        Defaults.moveCursorAcrossDisplays.enabled = false
        defer { Defaults.moveCursorAcrossDisplays.enabled = previousMoveCursor }
        let manager = WindowManager()
        let window = FocusTrackingElement()

        let screen = try XCTUnwrap(NSScreen.screens.first)

        manager.windowMovedAcrossDisplays(windowElement: window, windowId: nil, resultingRect: .zero,
                                          destination: screen, preservesFocus: true)
        XCTAssertEqual(window.bringToFrontCalls, 0)

        manager.windowMovedAcrossDisplays(windowElement: window, windowId: nil, resultingRect: .zero,
                                          destination: screen, preservesFocus: false)
        XCTAssertEqual(window.bringToFrontCalls, 1)
    }
}

final class CrossDisplayResizeTests: XCTestCase {
    func testDisplayCycleRetriesWidthUntilWindowFillsRightHalf() {
        let settings: [(Default, CodableDefault)] = [
            (Defaults.subsequentExecutionMode, CodableDefault(int: SubsequentExecutionMode.cycleMonitor.rawValue)),
            (Defaults.cooperativeCornerResize, CodableDefault(bool: false)),
            (Defaults.horizontalSplitRatio, CodableDefault(float: 50)),
            (Defaults.moveFixedSizeToEdge, CodableDefault(int: EdgeAlignment.edgesAndCorners.rawValue)),
            (Defaults.gapSize, CodableDefault(float: 0)),
            (Defaults.stageSize, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapLeft, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapRight, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapTop, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapBottom, CodableDefault(float: 0)),
            (Defaults.combinedDisplayMode, CodableDefault(int: 2)),
            (Defaults.todo, CodableDefault(int: 2))
        ]
        let savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        defer {
            savedDefaults.forEach { $0.0.load(from: $0.1) }
            ActiveSideSplitRatios.shared.resetAll()
        }
        settings.forEach { $0.0.load(from: $0.1) }

        let laptop = TestScreen(frame: CGRect(x: 0, y: 0, width: 2056, height: 1329))
        let monitor = TestScreen(frame: CGRect(x: -702, y: 1329, width: 3440, height: 1440))
        let target = CGRect(x: 1018, y: 1329, width: 1720, height: 1440).screenFlipped
        let window = ClampingWindow(target: target)
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: laptop))
        let finished = expectation(description: "Display-cycle resize completed")
        var completedFrames: [CGRect] = []
        manager.didFinish = { result, frame in
            XCTAssertTrue(result.usableScreens.currentScreen === laptop)
            completedFrames.append(frame)
            finished.fulfill()
        }

        // Repeated shortcuts pass the destination explicitly. Simulate macOS accepting
        // the height but clamping the width on the initial move and immediate retry.
        manager.execute(ExecutionParameters(.rightHalf, screen: monitor, windowElement: window))

        XCTAssertEqual(window.resizeAttempts, 2)
        XCTAssertEqual(window.frame.maxX, target.maxX)
        XCTAssertEqual(window.frame.minX, target.minX + 400)
        XCTAssertTrue(completedFrames.isEmpty)

        wait(for: [finished], timeout: 1)
        XCTAssertEqual(window.resizeAttempts, 3)
        XCTAssertEqual(window.frame, target)
        XCTAssertEqual(completedFrames, [target])
    }

    private final class TestScreen: NSScreen {
        private let testFrame: CGRect

        init(frame: CGRect) {
            testFrame = frame
            super.init()
        }

        override var frame: NSRect { testFrame }
        override var visibleFrame: NSRect { testFrame }
        override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
        override var hash: Int { ObjectIdentifier(self).hashValue }

        // AppKit's equality implementation requires a real display ID.
        override func isEqual(_ object: Any?) -> Bool {
            (object as AnyObject?) === self
        }
    }

    private final class TestScreenDetection: ScreenDetection {
        let source: NSScreen

        init(source: NSScreen) {
            self.source = source
        }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            UsableScreens(currentScreen: source, numScreens: 2)
        }
    }

    private final class ClampingWindow: AccessibilityElement {
        private var currentFrame = CGRect(x: 1028, y: 0, width: 1028, height: 645).screenFlipped
        private let target: CGRect
        private(set) var resizeAttempts = 0

        init(target: CGRect) {
            self.target = target
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { currentFrame }
        override var isSheet: Bool? { false }
        override var isSystemDialog: Bool? { false }
        override var minimumSize: CGSize? { nil }
        override func getWindowId() -> CGWindowID? { nil }
        override func isResizable() -> Bool { true }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: ImmediateWindowPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            currentFrame = CGRect(origin: adjustPosition ? frame.origin : currentFrame.origin, size: frame.size)
            if frame.size == target.size {
                resizeAttempts += 1
                if resizeAttempts <= 2 {
                    currentFrame.size.width -= 400
                }
            }
        }
    }

    private final class TestWindowManager: WindowManager {
        var didFinish: ((ResultParameters, CGRect) -> Void)?

        override func windowMovedAcrossDisplays(windowElement: AccessibilityElement, windowId: CGWindowID?,
                                                resultingRect: CGRect, destination: NSScreen, preservesFocus: Bool) {}

        override func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
            didFinish?(result, resultingRect)
        }
    }
}

final class NextPrevDisplayMappingTests: XCTestCase {
    // The opt-in is NOT needed to test the pure helper; setUp/tearDown still save & restore it
    // so the wiring tests below are isolated from host state.
    private var savedOptIn: Bool?

    override func setUp() {
        super.setUp()
        savedOptIn = Defaults.attemptMatchOnNextPrevDisplay.enabled
        Defaults.attemptMatchOnNextPrevDisplay.enabled = true
    }

    override func tearDown() {
        Defaults.attemptMatchOnNextPrevDisplay.enabled = savedOptIn
        super.tearDown()
    }

    // --- Helper-level: RED until relativePositionedRect exists, then GREEN ---

    func testRelativePositionedRectMapsRightThirdToRightThird() {
        // Issue #1723 repro geometry: a window pinned to the right third (full height) of a
        // 3000x2000 source must land at the right third of a 1500x1000 destination.
        let source      = CGRect(x: 0,    y: 0,    width: 3000, height: 2000)
        let window      = CGRect(x: 2000, y: 0,    width: 1000, height: 2000)
        let destination = CGRect(x: 0,    y: 0,    width: 1500, height: 1000)

        XCTAssertEqual(
            NextPrevDisplayCalculation.relativePositionedRect(window: window, source: source, destination: destination),
            CGRect(x: 1000, y: 0, width: 500, height: 1000)
        )
    }

    func testRelativePositionedRectPreservesCenteredQuarter() {
        // A centered-quarter window stays a centered quarter after the cross-display map.
        let source      = CGRect(x: 0,   y: 0,   width: 2560, height: 1440)
        let window      = CGRect(x: 960, y: 360, width: 640,  height: 720)   // centered quarter
        let destination = CGRect(x: 0,   y: 0,   width: 1280, height: 720)

        XCTAssertEqual(
            NextPrevDisplayCalculation.relativePositionedRect(window: window, source: source, destination: destination),
            CGRect(x: 480, y: 180, width: 320, height: 360)
        )
    }

    func testRelativePositionedRectClampsOverflowIntoDestination() {
        // Window occupies 60% width starting at the 50% mark on a 1000x1000 source.
        // Mapped onto a 500x500 destination: width 300 @ x 250 -> maxX 550 > 500 -> clamp to x 200.
        let source      = CGRect(x: 0,   y: 0, width: 1000, height: 1000)
        let window      = CGRect(x: 500, y: 0, width: 600,  height: 1000)
        let destination = CGRect(x: 0,   y: 0, width: 500,  height: 500)

        XCTAssertEqual(
            NextPrevDisplayCalculation.relativePositionedRect(window: window, source: source, destination: destination),
            CGRect(x: 200, y: 0, width: 300, height: 500)
        )
    }

    func testRelativePositionedRectIsIdentityWhenSourceEqualsDestination() {
        let frame = CGRect(x: 0,   y: 0,   width: 2000, height: 1000)
        let window = CGRect(x: 300, y: 200, width: 500, height: 600)

        XCTAssertEqual(
            NextPrevDisplayCalculation.relativePositionedRect(window: window, source: frame, destination: frame),
            window
        )
    }
}

final class ScreenOrderingTests: XCTestCase {
    private final class TestScreen: NSScreen {
        let testFrame: CGRect
        init(_ frame: CGRect) { testFrame = frame; super.init() }
        override var frame: NSRect { testFrame }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    private func withYThenMinX(_ body: () -> Void) {
        let saved = Defaults.screensOrderedByX.value
        Defaults.screensOrderedByX.value = .yThenMinX
        defer { Defaults.screensOrderedByX.value = saved }
        body()
    }

    /// NSScreen.screens is not guaranteed to enumerate displays in any spatial order, so
    /// ordering a fixed physical layout must not depend on the order the screens arrive in.
    func testYThenMinXOrderingIsIndependentOfEnumerationOrder() {
        withYThenMinX {
            // A diagonal/staircase layout: A overlaps B in Y and B overlaps C in Y, but A and
            // C do not overlap. This is the case the old comparator ordered by X for some
            // pairs and by Y for others, making it intransitive.
            let a = TestScreen(CGRect(x: 0,    y: 0,    width: 1000, height: 1000))
            let b = TestScreen(CGRect(x: 1000, y: 500,  width: 1000, height: 1000))
            let c = TestScreen(CGRect(x: 2000, y: 1000, width: 1000, height: 1000))
            let detection = ScreenDetection(screens: { [a, b, c] })

            let ordered = detection.order(screens: [a, b, c]).map(\.frame)
            XCTAssertEqual(detection.order(screens: [c, b, a]).map(\.frame), ordered)
            XCTAssertEqual(detection.order(screens: [b, a, c]).map(\.frame), ordered)
            XCTAssertEqual(detection.order(screens: [c, a, b]).map(\.frame), ordered)
        }
    }

    /// The connected staircase forms one vertical band, so the displays read left-to-right.
    func testYThenMinXGivesADeterministicOrderForADiagonalLayout() {
        withYThenMinX {
            let a = TestScreen(CGRect(x: 0,    y: 0,    width: 1000, height: 1000))
            let b = TestScreen(CGRect(x: 1000, y: 500,  width: 1000, height: 1000))
            let c = TestScreen(CGRect(x: 2000, y: 1000, width: 1000, height: 1000))
            let detection = ScreenDetection(screens: { [a, b, c] })
            XCTAssertEqual(detection.order(screens: [c, b, a]).map(\.frame),
                           [a, b, c].map(\.frame))
        }
    }

    /// A 2x2 grid still reads top-to-bottom, left-to-right (unchanged from before the fix).
    func testYThenMinXOrdersAGridTopToBottomLeftToRight() {
        withYThenMinX {
            let topLeft     = TestScreen(CGRect(x: 0,    y: 1000, width: 1000, height: 1000))
            let topRight    = TestScreen(CGRect(x: 1000, y: 1000, width: 1000, height: 1000))
            let bottomLeft  = TestScreen(CGRect(x: 0,    y: 0,    width: 1000, height: 1000))
            let bottomRight = TestScreen(CGRect(x: 1000, y: 0,    width: 1000, height: 1000))
            let detection = ScreenDetection(screens: { [bottomRight, topLeft, bottomLeft, topRight] })
            XCTAssertEqual(
                detection.order(screens: [bottomRight, topLeft, bottomLeft, topRight]).map(\.frame),
                [topLeft, topRight, bottomLeft, bottomRight].map(\.frame))
        }
    }

    /// Two displays sharing a desk, bottoms aligned but different heights, are one band, so
    /// they stay left-to-right rather than being reordered by height.
    func testYThenMinXKeepsAMixedHeightRowLeftToRight() {
        withYThenMinX {
            let short = TestScreen(CGRect(x: 0,    y: 0, width: 1000, height: 1000))
            let tall  = TestScreen(CGRect(x: 1000, y: 0, width: 1000, height: 1400))
            let detection = ScreenDetection(screens: { [tall, short] })
            XCTAssertEqual(detection.order(screens: [tall, short]).map(\.frame),
                           [short, tall].map(\.frame))
        }
    }
}

final class EdgeActionsAcrossDisplaysTests: XCTestCase {
    private final class TestScreen: NSScreen {
        private let testFrame: CGRect

        init(frame: CGRect) {
            testFrame = frame
            super.init()
        }

        override var frame: NSRect { testFrame }
        override var visibleFrame: NSRect { testFrame }
        override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
        override var backingScaleFactor: CGFloat { 1 }
        override func convertRectToBacking(_ rect: NSRect) -> NSRect { rect }
        override func convertRectFromBacking(_ rect: NSRect) -> NSRect { rect }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    private let left = TestScreen(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
    private let right = TestScreen(frame: CGRect(x: 1200, y: 0, width: 1200, height: 800))
    private var savedMode: SubsequentExecutionMode = .resize
    private var savedFlag = CodableDefault(int: 0)
    private var storedFlag: Any?

    // Same save/restore as IgnoreMenuBarTests: the in-memory value and the raw UserDefaults entry.
    override func setUp() {
        super.setUp()
        savedMode = Defaults.subsequentExecutionMode.value
        storedFlag = UserDefaults.standard.object(forKey: Defaults.thirdsAndFourthsAcrossDisplays.key)
        savedFlag = Defaults.thirdsAndFourthsAcrossDisplays.toCodable()
        Defaults.thirdsAndFourthsAcrossDisplays.enabled = true
    }

    override func tearDown() {
        Defaults.subsequentExecutionMode.value = savedMode
        Defaults.thirdsAndFourthsAcrossDisplays.load(from: savedFlag)
        // Written last: nil removes the key, so an unset flag stays unset (load(from:) writes 0).
        UserDefaults.standard.set(storedFlag, forKey: Defaults.thirdsAndFourthsAcrossDisplays.key)
        super.tearDown()
    }

    /// Runs the action on `current` with the previous run having left the window at `previous`
    /// (nil for a first run), the way WindowManager does. `traversesSingleScreen` mirrors
    /// ScreenDetection when one display is its own adjacent screen.
    private func calculate(_ action: WindowAction, on current: NSScreen, previous: WindowCalculationResult?,
                           singleScreen: Bool = false, traversesSingleScreen: Bool = false) -> WindowCalculationResult? {
        let other = current === left ? right : left
        let adjacent: AdjacentScreens?
        if singleScreen {
            adjacent = traversesSingleScreen ? AdjacentScreens(prev: current, next: current) : nil
        } else {
            adjacent = AdjacentScreens(prev: other, next: other)
        }
        let params = WindowCalculationParameters(
            window: Window(id: 1, rect: previous?.rect ?? current.frame.insetBy(dx: 100, dy: 100)),
            usableScreens: UsableScreens(currentScreen: current, adjacentScreens: adjacent, numScreens: singleScreen ? 1 : 2, screensOrdered: singleScreen ? [current] : [left, right]),
            action: action,
            lastAction: previous.map { RectangleAction(action: action, subAction: $0.resultingSubAction, rect: $0.rect.screenFlipped, count: 1) },
            ignoreTodo: false)
        return WindowCalculationFactory.calculationsByAction[action]!.calculate(params)
    }

    func testRepeatedEdgeActionsMoveToTheOppositeEdgeOfTheAdjacentDisplay() throws {
        Defaults.subsequentExecutionMode.value = .acrossMonitor
        let cases: [(WindowAction, WindowAction, NSScreen, NSScreen, CGFloat)] = [
            (.firstThird, .lastThird, left, right, 3),
            (.lastThird, .firstThird, right, left, 3),
            (.firstFourth, .lastFourth, left, right, 4),
            (.lastFourth, .firstFourth, right, left, 4),
        ]
        for (action, opposite, from, to, parts) in cases {
            let first = try XCTUnwrap(calculate(action, on: from, previous: nil))
            XCTAssertTrue(first.screen === from)
            XCTAssertEqual(first.resultingAction, action)

            let repeated = try XCTUnwrap(calculate(action, on: from, previous: first))
            XCTAssertTrue(repeated.screen === to, "\(action) should move to the other display")
            XCTAssertEqual(repeated.resultingAction, opposite)
            XCTAssertEqual(repeated.rect.width, floor(to.frame.width / parts))
            XCTAssertEqual(repeated.rect.minX, opposite == .lastThird || opposite == .lastFourth ? to.frame.maxX - repeated.rect.width : to.frame.minX)
        }
    }

    func testOtherModesStillCycleThroughPositionsOnTheSameDisplay() throws {
        Defaults.subsequentExecutionMode.value = .resize
        let first = try XCTUnwrap(calculate(.firstThird, on: left, previous: nil))
        let repeated = try XCTUnwrap(calculate(.firstThird, on: left, previous: first))
        XCTAssertTrue(repeated.screen === left)
        XCTAssertEqual(repeated.resultingSubAction, .centerVerticalThird)
    }

    func testAcrossMonitorStillCyclesOnASingleDisplay() throws {
        Defaults.subsequentExecutionMode.value = .acrossMonitor
        let first = try XCTUnwrap(calculate(.firstThird, on: left, previous: nil, singleScreen: true))
        let repeated = try XCTUnwrap(calculate(.firstThird, on: left, previous: first, singleScreen: true))
        XCTAssertTrue(repeated.screen === left)
        XCTAssertEqual(repeated.resultingSubAction, .centerVerticalThird)
    }

    func testFlagOnWithTraverseSingleScreenStillCyclesOnOneDisplay() throws {
        Defaults.subsequentExecutionMode.value = .acrossMonitor
        let cases: [(WindowAction, WindowAction)] = [(.firstThird, .lastThird), (.firstFourth, .lastFourth)]
        for (action, opposite) in cases {
            let first = try XCTUnwrap(calculate(action, on: left, previous: nil, singleScreen: true, traversesSingleScreen: true))
            let repeated = try XCTUnwrap(calculate(action, on: left, previous: first, singleScreen: true, traversesSingleScreen: true))
            XCTAssertTrue(repeated.screen === left, "\(action) should stay on the one display")
            XCTAssertNotEqual(repeated.resultingAction, opposite)
        }
    }

    func testWithTheFlagOffRepeatedLeftThirdStillCyclesOnTheSameDisplay() throws {
        Defaults.thirdsAndFourthsAcrossDisplays.enabled = nil
        Defaults.subsequentExecutionMode.value = .acrossMonitor
        let first = try XCTUnwrap(calculate(.firstThird, on: left, previous: nil))
        let repeated = try XCTUnwrap(calculate(.firstThird, on: left, previous: first))
        XCTAssertTrue(repeated.screen === left)
        XCTAssertEqual(repeated.resultingSubAction, .centerVerticalThird)
    }
}

final class VerticalDisplayTraversalTests: XCTestCase {
    private let laptop = RepeatedMaximizeTestScreen(frame: CGRect(x: 0, y: 0, width: 1500, height: 900))
    private let above = RepeatedMaximizeTestScreen(frame: CGRect(x: -500, y: 900, width: 2500, height: 1400))
    private let below = RepeatedMaximizeTestScreen(frame: CGRect(x: 0, y: -900, width: 1500, height: 900))
    private var savedMode: SubsequentExecutionMode = .resize
    private var savedPreserveOtherAxis = false

    override func setUp() {
        super.setUp()
        savedMode = Defaults.subsequentExecutionMode.value
        savedPreserveOtherAxis = Defaults.halvesPreserveOtherAxisSize.enabled
        Defaults.halvesPreserveOtherAxisSize.enabled = false
    }

    override func tearDown() {
        Defaults.subsequentExecutionMode.value = savedMode
        Defaults.halvesPreserveOtherAxisSize.enabled = savedPreserveOtherAxis
        super.tearDown()
    }

    private func calculate(_ action: WindowAction, source: NSScreen, screens: [NSScreen],
                           repeated: Bool = true, moved: Bool = false,
                           mode: SubsequentExecutionMode = .acrossMonitor,
                           previous: WindowCalculationResult? = nil) -> WindowCalculationResult? {
        Defaults.subsequentExecutionMode.value = mode
        let calculation = WindowCalculationFactory.calculationsByAction[action]!
        let sourceFrame = source.adjustedVisibleFrame(true)
        let rect = previous?.rect ?? calculation.calculateRect(RectCalculationParameters(window: Window(id: nil, rect: sourceFrame),
                                                                       visibleFrameOfScreen: sourceFrame,
                                                                       action: action, lastAction: nil)).rect
        let lastAction = repeated ? RectangleAction(action: previous?.resultingAction ?? action, rect: rect.screenFlipped) : nil
        return calculation.calculate(WindowCalculationParameters(
            window: Window(id: nil, rect: moved ? rect.offsetBy(dx: 20, dy: 0) : rect),
            usableScreens: UsableScreens(currentScreen: source, numScreens: screens.count, screensOrdered: screens),
            action: action, lastAction: lastAction, ignoreTodo: true))
    }

    func testRepeatedTopHalfMovesToBottomHalfOfDisplayAbove() throws {
        let result = try XCTUnwrap(calculate(.topHalf, source: laptop, screens: [above, laptop]))
        XCTAssertTrue(result.screen === above)
        XCTAssertEqual(result.resultingAction, .bottomHalf)
        XCTAssertEqual(result.rect.minY, above.adjustedVisibleFrame(true).minY)
        XCTAssertEqual(result.rect.width, above.adjustedVisibleFrame(true).width)
    }

    func testRepeatedBottomHalfMovesToTopHalfOfDisplayBelow() throws {
        let result = try XCTUnwrap(calculate(.bottomHalf, source: above, screens: [above, laptop]))
        XCTAssertTrue(result.screen === laptop)
        XCTAssertEqual(result.resultingAction, .topHalf)
        XCTAssertEqual(result.rect.maxY, laptop.adjustedVisibleFrame(true).maxY)
    }

    func testFirstExecutionAndManuallyMovedWindowStayOnCurrentDisplay() {
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop, above], repeated: false)?.screen === laptop)
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop, above], moved: true)?.screen === laptop)
    }

    func testSideBySideAndCornerOnlyDisplaysAreNotAbove() {
        let right = RepeatedMaximizeTestScreen(frame: CGRect(x: 1500, y: 0, width: 1500, height: 900))
        let diagonal = RepeatedMaximizeTestScreen(frame: CGRect(x: 1500, y: 900, width: 1500, height: 900))
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop, right, diagonal])?.screen === laptop)
    }

    func testNearestDisplayAboveWinsRegardlessOfScreenOrdering() {
        let farther = RepeatedMaximizeTestScreen(frame: CGRect(x: 0, y: 2300, width: 1500, height: 900))
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [farther, above, laptop])?.screen === above)
    }

    func testEqualDistancePrefersGreaterHorizontalOverlap() {
        let offset = RepeatedMaximizeTestScreen(frame: CGRect(x: 1400, y: 900, width: 1500, height: 900))
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [offset, laptop, above])?.screen === above)
    }

    func testVerticalTraversalWrapsAtBothEnds() {
        XCTAssertTrue(calculate(.topHalf, source: above, screens: [laptop, above])?.screen === laptop)
        XCTAssertTrue(calculate(.bottomHalf, source: laptop, screens: [laptop, above])?.screen === above)
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop])?.screen === laptop)
    }

    func testWrapChoosesOppositeEndOfThreeDisplayStack() {
        let screens: [NSScreen] = [laptop, above, below]
        XCTAssertTrue(calculate(.topHalf, source: above, screens: screens)?.screen === below)
        XCTAssertTrue(calculate(.bottomHalf, source: below, screens: screens)?.screen === above)
    }

    func testAcrossAndResizeKeepsCyclingSizesAtVerticalBoundaries() {
        XCTAssertTrue(calculate(.topHalf, source: above, screens: [laptop, above], mode: .acrossAndResize)?.screen === above)
        XCTAssertTrue(calculate(.bottomHalf, source: laptop, screens: [laptop, above], mode: .acrossAndResize)?.screen === laptop)
    }

    func testRepeatedTopHalfCyclesThroughThreeDisplaysTwice() throws {
        try assertCycle(.topHalf, screens: [laptop, above, below],
                        expected: [(above, .bottomHalf), (above, .topHalf),
                                   (below, .bottomHalf), (below, .topHalf),
                                   (laptop, .bottomHalf), (laptop, .topHalf)])
    }

    func testRepeatedBottomHalfCyclesThroughThreeDisplaysTwice() throws {
        try assertCycle(.bottomHalf, screens: [above, below, laptop],
                        expected: [(below, .topHalf), (below, .bottomHalf),
                                   (above, .topHalf), (above, .bottomHalf),
                                   (laptop, .topHalf), (laptop, .bottomHalf)])
    }

    private func assertCycle(_ action: WindowAction, screens: [NSScreen],
                             expected: [(NSScreen, WindowAction)],
                             file: StaticString = #filePath, line: UInt = #line) throws {
        var result = try XCTUnwrap(calculate(action, source: laptop, screens: screens, repeated: false))
        for _ in 0..<2 {
            for (screen, resultingAction) in expected {
                result = try XCTUnwrap(calculate(action, source: result.screen, screens: screens, previous: result))
                XCTAssertTrue(result.screen === screen, file: file, line: line)
                XCTAssertEqual(result.resultingAction, resultingAction, file: file, line: line)
            }
        }
    }

    func testTraversalRequiresAcrossDisplaysMode() {
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop, above], mode: .none)?.screen === laptop)
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop, above], mode: .resize)?.screen === laptop)
        XCTAssertTrue(calculate(.topHalf, source: laptop, screens: [laptop, above], mode: .acrossAndResize)?.screen === above)
    }
}

final class CursorScreenDetectionExecutionTests: XCTestCase {
    private let windowId: CGWindowID = 523_001
    private var savedDefaults: [(Default, CodableDefault)] = []
    private var savedActions: [CGWindowID: RectangleAction] = [:]
    private var savedCursorScreenFrames: [CGWindowID: CGRect] = [:]
    private var savedCursorActions: [CGWindowID: WindowAction] = [:]
    private var savedLogging = false

    private let left = TestScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
    private let right = TestScreen(frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))

    override func setUp() {
        super.setUp()
        let settings: [(Default, CodableDefault)] = [
            (Defaults.useCursorScreenDetection, CodableDefault(bool: true)),
            (Defaults.moveCursorAcrossDisplays, CodableDefault(int: 2)),
            (Defaults.moveCursor, CodableDefault(int: 2)),
            (Defaults.subsequentExecutionMode, CodableDefault(int: SubsequentExecutionMode.none.rawValue)),
            (Defaults.cooperativeCornerResize, CodableDefault(bool: false)),
            (Defaults.experimentalWindowAnimations, CodableDefault(bool: false)),
            (Defaults.moveFixedSizeToEdge, CodableDefault(int: EdgeAlignment.edgesAndCorners.rawValue)),
            (Defaults.horizontalSplitRatio, CodableDefault(float: 50)),
            (Defaults.verticalSplitRatio, CodableDefault(float: 50)),
            (Defaults.halvesPreserveOtherAxisSize, CodableDefault(bool: false)),
            (Defaults.cycleSizesIsChanged, CodableDefault(bool: false)),
            (Defaults.attemptMatchOnNextPrevDisplay, CodableDefault(int: 2)),
            (Defaults.centerAcrossDisplays, CodableDefault(int: 2)),
            (Defaults.gapSize, CodableDefault(float: 0)),
            (Defaults.stageSize, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapLeft, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapRight, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapTop, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapBottom, CodableDefault(float: 0)),
            (Defaults.cyclingOverlapOffset, CodableDefault(int: 2)),
            (Defaults.combinedDisplayMode, CodableDefault(int: 2)),
            (Defaults.todo, CodableDefault(int: 2))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
        savedActions = AppDelegate.windowHistory.lastRectangleActions
        savedCursorScreenFrames = CursorScreenHistory.shared.screenFrames
        savedCursorActions = CursorScreenHistory.shared.actions
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        CursorScreenHistory.shared.screenFrames.removeValue(forKey: windowId)
        CursorScreenHistory.shared.actions.removeValue(forKey: windowId)
        savedLogging = Logger.logging
        Logger.logging = false
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        AppDelegate.windowHistory.lastRectangleActions = savedActions
        CursorScreenHistory.shared.screenFrames = savedCursorScreenFrames
        CursorScreenHistory.shared.actions = savedCursorActions
        Logger.logging = savedLogging
        ActiveSideSplitRatios.shared.resetAll()
        super.tearDown()
    }

    func testCommandMovesWindowToCursorDisplay() {
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: right)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))

        XCTAssertEqual(window.frame, leftHalf(of: right))
    }

    func testPointingAtAnotherDisplayIsNotARepeatWhenRepeatsCrossDisplays() {
        Defaults.subsequentExecutionMode.value = .acrossMonitor
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: left)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
        XCTAssertEqual(window.frame, leftHalf(of: left))

        detection.cursorScreen = right
        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))

        // Treated as a repeat, this used to bounce the window to the right half of `left`.
        XCTAssertEqual(window.frame, leftHalf(of: right))
    }

    func testPointingAtAnotherDisplayIsNotARepeatWhenRepeatsCycleSizes() {
        Defaults.subsequentExecutionMode.value = .resize
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: left)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
        detection.cursorScreen = right
        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))

        XCTAssertEqual(window.frame, leftHalf(of: right))
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.count, 1)
    }

    func testRepeatWithoutMovingCursorStillCrossesDisplays() {
        Defaults.subsequentExecutionMode.value = .acrossMonitor
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: left)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
        XCTAssertEqual(window.frame, rightHalf(of: right))

        // The window has left the cursor's display, but the walk continues from where it is.
        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
        XCTAssertEqual(window.frame, leftHalf(of: right))
    }

    func testRepeatWithoutMovingCursorWalksDisplaysLikeWithTheSettingOff() {
        Defaults.subsequentExecutionMode.value = .acrossMonitor

        // An app that sizes its window in rows never lands exactly on the target,
        // so Rectangle forgets its last action between presses.
        func walk(cursorDetection: Bool) -> [CGRect] {
            Defaults.useCursorScreenDetection.enabled = cursorDetection
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            CursorScreenHistory.shared.screenFrames.removeValue(forKey: windowId)
            CursorScreenHistory.shared.actions.removeValue(forKey: windowId)
            let window = TestWindow(frame: leftHalf(of: right), heightStep: 7)
            let detection = TestScreenDetection(screens: [left, right], cursorScreen: right)
            let manager = TestWindowManager(screenDetection: detection)
            return (0..<6).map { _ in
                manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
                return window.frame
            }
        }

        let expected = walk(cursorDetection: false)
        XCTAssertEqual(Set(expected.map(\.minX)).count, 4, "the walk should visit both halves of both displays")
        XCTAssertEqual(walk(cursorDetection: true), expected)
    }

    func testRepeatWithoutMovingCursorStillCyclesSizes() {
        Defaults.subsequentExecutionMode.value = .resize
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: right)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))
        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))

        XCTAssertEqual(window.frame.minX, right.frame.minX)
        XCTAssertNotEqual(window.frame.width, right.frame.width / 2)
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.count, 2)
    }

    func testAnotherCommandAfterCyclingDisplaysGoesToCursorDisplay() {
        Defaults.subsequentExecutionMode.value = .cycleMonitor
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: left)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.topLeft, windowElement: window, windowId: windowId))
        // A repeat cycles the window on to the next display while the cursor stays put.
        manager.execute(ExecutionParameters(.topLeft, screen: right, windowElement: window, windowId: windowId))
        XCTAssertTrue(right.frame.screenFlipped.contains(window.frame))

        manager.execute(ExecutionParameters(.topRight, windowElement: window, windowId: windowId))

        XCTAssertTrue(left.frame.screenFlipped.contains(window.frame))
        XCTAssertEqual(window.frame.minX, left.frame.midX)
    }

    func testCursorStaysPutWhenWindowMovesToItsDisplay() {
        Defaults.moveCursorAcrossDisplays.enabled = true
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: right)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))

        XCTAssertEqual(window.frame, leftHalf(of: right))
        XCTAssertEqual(manager.cursorWarps, 0)
    }

    func testCursorMovedAlongWithWindowStillCountsAsTheSameDisplay() {
        Defaults.subsequentExecutionMode.value = .cycleMonitor
        Defaults.moveCursorAcrossDisplays.enabled = true
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: left)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.topLeft, windowElement: window, windowId: windowId))
        manager.execute(ExecutionParameters(.topLeft, screen: right, windowElement: window, windowId: windowId))

        // The cursor followed the window, which mustn't make the next press a fresh one.
        XCTAssertEqual(manager.cursorWarps, 1)
        XCTAssertTrue(detection.cursorScreen === right)
        XCTAssertFalse(CursorScreenHistory.shared.changedDisplay(for: windowId, cursorScreenFrame: right.frame))
    }

    func testNextDisplayCountsFromWindowDisplay() {
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: right)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.nextDisplay, windowElement: window, windowId: windowId))

        XCTAssertTrue(right.frame.screenFlipped.contains(window.frame))
    }

    func testCursorDisplayIsIgnoredWhenSettingIsOff() {
        Defaults.useCursorScreenDetection.enabled = false
        let window = TestWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300).screenFlipped)
        let detection = TestScreenDetection(screens: [left, right], cursorScreen: right)
        let manager = TestWindowManager(screenDetection: detection)

        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, windowId: windowId))

        XCTAssertEqual(window.frame, leftHalf(of: left))
        XCTAssertNil(CursorScreenHistory.shared.screenFrames[windowId])
    }

    private func leftHalf(of screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: screen.frame.minY,
               width: screen.frame.width / 2, height: screen.frame.height).screenFlipped
    }

    private func rightHalf(of screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.midX, y: screen.frame.minY,
               width: screen.frame.width / 2, height: screen.frame.height).screenFlipped
    }

    private final class TestScreen: NSScreen {
        private let testFrame: CGRect

        init(frame: CGRect) {
            testFrame = frame
            super.init()
        }

        override var frame: NSRect { testFrame }
        override var visibleFrame: NSRect { testFrame }
        override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    private final class TestScreenDetection: ScreenDetection {
        let screens: [NSScreen]
        var cursorScreen: NSScreen

        init(screens: [NSScreen], cursorScreen: NSScreen) {
            self.screens = screens
            self.cursorScreen = cursorScreen
        }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            let windowFrame = frontmostWindowElement?.frame.screenFlipped ?? .zero
            let screen = screens.first { $0.frame.contains(CGPoint(x: windowFrame.midX, y: windowFrame.midY)) } ?? screens[0]
            return usableScreens(around: screen)
        }

        override func detectScreensAtCursor() -> UsableScreens? {
            usableScreens(around: cursorScreen)
        }

        private func usableScreens(around screen: NSScreen) -> UsableScreens {
            let other = screens.first { $0 !== screen } ?? screen
            return UsableScreens(currentScreen: screen, adjacentScreens: AdjacentScreens(prev: other, next: other),
                                 numScreens: screens.count, screensOrdered: screens)
        }
    }

    private final class TestWindow: AccessibilityElement {
        private var currentFrame: CGRect
        private let heightStep: CGFloat?

        /// A `heightStep` rounds the height down to whole steps, like an app
        /// that sizes its window in rows, so the frame differs from the target.
        init(frame: CGRect, heightStep: CGFloat? = nil) {
            currentFrame = frame
            self.heightStep = heightStep
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { currentFrame }
        override var isSheet: Bool? { false }
        override var isSystemDialog: Bool? { false }
        override var minimumSize: CGSize? { nil }
        override func getWindowId() -> CGWindowID? { nil }
        override func isResizable() -> Bool { true }
        override func bringToFront(force: Bool = false) {}

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: ImmediateWindowPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            var frame = frame
            if let heightStep {
                frame.size.height = (frame.height / heightStep).rounded(.down) * heightStep
            }
            currentFrame = frame
        }
    }

    private final class TestWindowManager: WindowManager {
        private let detection: TestScreenDetection
        private(set) var cursorWarps = 0

        init(screenDetection: TestScreenDetection) {
            detection = screenDetection
            super.init(screenDetection: screenDetection)
        }

        override func warpCursor(to point: CGPoint) {
            cursorWarps += 1
            detection.cursorScreen = detection.screens.first { $0.frame.screenFlipped.contains(point) } ?? detection.cursorScreen
        }
    }
}
