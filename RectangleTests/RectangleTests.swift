/// RectangleTests.swift

import Carbon.HIToolbox
import MASShortcut
import XCTest
@testable import Rectangle

class RectangleTests: XCTestCase {

    override func setUp() {
    }

    override func tearDown() {
    }
}

class WindowActionMenuTests: XCTestCase {

    func testRowsAndColumnsShareOptionalSubmenu() throws {
        for showAdditional in [false, true] {
            let menu = makeMenu(showAdditional: showAdditional, showAllActions: false)
            let tilingItems = menu.items.filter { item in
                item.submenu?.items.contains { $0.representedObject as? WindowAction == .tileRows } == true
            }
            XCTAssertEqual(tilingItems.count, 1)
            let tilingItem = try XCTUnwrap(tilingItems.first)
            XCTAssertEqual(tilingItem.submenu?.items.compactMap { $0.representedObject as? WindowAction },
                           [.tileRows, .tileColumns])
            XCTAssertEqual(tilingItem.isHidden, !showAdditional)
            let topLevelActions = menu.items.compactMap { $0.representedObject as? WindowAction }
            XCTAssertFalse(topLevelActions.contains(.tileRows))
            XCTAssertFalse(topLevelActions.contains(.tileColumns))
            XCTAssertTrue(topLevelActions.contains(.maximize))
        }
    }

    func testShowAllActionsKeepsRowsAndColumnsFlat() {
        let menu = makeMenu(showAdditional: false, showAllActions: true)
        let visibleActions = menu.items.filter { !$0.isHidden }.compactMap { $0.representedObject as? WindowAction }
        XCTAssertTrue(visibleActions.contains(.tileRows))
        XCTAssertTrue(visibleActions.contains(.tileColumns))
        XCTAssertFalse(menu.items.contains { $0.submenu != nil })
    }

    private func makeMenu(showAdditional: Bool, showAllActions: Bool) -> NSMenu {
        let menu = NSMenu()
        let delegate = AppDelegate()
        delegate.mainStatusMenu = menu
        delegate.addWindowActionMenuItems(showAdditional: showAdditional, showAllActions: showAllActions)
        return menu
    }
}

class GridLimitDefaultsTests: XCTestCase {
    // Separate limits round-trip without replacing explicitly saved values or
    // writing an absent default into the user's preferences.
    func testIndependentDefaultsAndConfigRoundTripPreserveExplicitValues() {
        let suiteName = "RectangleGridDefaults-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let columns = PositiveIntDefault(key: "columns", defaultValue: 3, userDefaults: preferences)
        let rows = PositiveIntDefault(key: "rows", defaultValue: 3, userDefaults: preferences)
        XCTAssertEqual(columns.value, 3)
        XCTAssertEqual(rows.value, 3)
        XCTAssertNil(preferences.object(forKey: "columns"))
        columns.value = 1
        rows.load(from: CodableDefault(int: 2))
        XCTAssertEqual(columns.toCodable().int, 1)
        XCTAssertEqual(rows.toCodable().int, 2)
        XCTAssertEqual(PositiveIntDefault(key: "columns", defaultValue: 3, userDefaults: preferences).value, 1)
        XCTAssertEqual(PositiveIntDefault(key: "rows", defaultValue: 3, userDefaults: preferences).value, 2)
        columns.load(from: CodableDefault())
        XCTAssertEqual(columns.value, 1)
    }

    func testInvalidSavedLimitsNormalizeWithoutWritingOnRead() {
        let suiteName = "RectangleGridDefaults-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("invalid", forKey: "limit")
        let limit = PositiveIntDefault(key: "limit", defaultValue: 3, userDefaults: preferences)
        XCTAssertEqual(limit.value, 1)
        XCTAssertEqual(preferences.string(forKey: "limit"), "invalid")
        limit.load(from: CodableDefault(int: 0))
        XCTAssertEqual(limit.value, 1)
        XCTAssertEqual(preferences.integer(forKey: "limit"), 1)
    }
}

class BandTilingTests: XCTestCase {

    private typealias Manager = MultiWindowManager

    private func applyBandTiling(_ windows: [Manager.TilingWindow], bounds: Manager.BackingPixelBounds,
                                direction: Manager.BandDirection, constraints: [Manager.BandConstraint],
                                pointFrame: (CGRect) -> CGRect, backingFrame: (CGRect) -> CGRect) {
        let cross = GridTiling.Constraint.resizable(minimum: 0, maximum: bounds.extent(direction.cross))
        let sizes = constraints.map { primary in
            direction == .rows
                ? GridTiling.WindowConstraints(width: cross, height: primary)
                : GridTiling.WindowConstraints(width: primary, height: cross)
        }
        _ = GridTiling.apply(observedFrames: windows.map { backingFrame($0.element.frame) }, bounds: bounds,
                             direction: direction, subdivision: 1, constraints: sizes) { index, frame in
            windows[index].element.setFrame(pointFrame(frame))
            return backingFrame(windows[index].element.frame)
        }
    }

    private final class TestElement: AccessibilityElement {
        private var acceptedFrame: CGRect
        private(set) var setFrameCalls = 0
        let minimumHeight: CGFloat
        let maximumWidth: CGFloat
        let minimumHeightAtOrigin: (CGFloat) -> CGFloat
        let testWindowId: CGWindowID?
        var testIdentity: CFHashCode
        let reportedMinimumSize: CGSize?
        let canResize: Bool
        let ordinaryWindow: Bool

        init(frame: CGRect = .zero, minimumHeight: CGFloat = 0, maximumWidth: CGFloat = .greatestFiniteMagnitude,
             minimumHeightAtOrigin: @escaping (CGFloat) -> CGFloat = { _ in 0 },
             windowId: CGWindowID? = nil, identity: CFHashCode = 0,
             reportedMinimumSize: CGSize? = .zero, canResize: Bool = true, ordinaryWindow: Bool = true) {
            acceptedFrame = frame
            self.minimumHeight = minimumHeight
            self.maximumWidth = maximumWidth
            self.minimumHeightAtOrigin = minimumHeightAtOrigin
            testWindowId = windowId
            testIdentity = identity
            self.reportedMinimumSize = reportedMinimumSize
            self.canResize = canResize
            self.ordinaryWindow = ordinaryWindow
            super.init(identity == 0 ? AXUIElementCreateSystemWide()
                                     : AXUIElementCreateApplication(pid_t(10_000 + identity)))
        }

        override var frame: CGRect { acceptedFrame }
        override var windowId: CGWindowID? { testWindowId }
        override var pid: pid_t? { 42 }
        override var minimumSize: CGSize? { reportedMinimumSize }
        override func isResizable() -> Bool { canResize }
        override var isWindow: Bool? { ordinaryWindow }
        override var isSheet: Bool? { false }
        override var isMinimized: Bool? { false }
        override var isHidden: Bool? { false }
        override var isSystemDialog: Bool? { false }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: WindowAnimationPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            setFrameCalls += 1
            let originalOrigin = acceptedFrame.origin
            acceptedFrame = frame
            if !adjustPosition { acceptedFrame.origin = originalOrigin }
            acceptedFrame.size.height = max(frame.height, minimumHeight, minimumHeightAtOrigin(frame.minY))
            acceptedFrame.size.width = min(frame.width, maximumWidth)
        }
    }

    private func candidate(_ element: TestElement, frame: CGRect, identity: CFHashCode,
                           pid: pid_t = 42, windowId: CGWindowID? = nil, focused: Bool = false) -> Manager.TilingWindow {
        element.testIdentity = identity
        return Manager.TilingWindow(element: element, frame: frame, windowId: windowId, pid: pid,
                                    isFocused: focused)
    }

    private func testLabel(_ window: Manager.TilingWindow) -> CFHashCode {
        (window.element as! TestElement).testIdentity
    }

    private func visible(_ id: CGWindowID, frame: CGRect, pid: pid_t = 42) -> WindowInfo {
        WindowInfo(id: id, level: 0, frame: frame, pid: pid, processName: nil)
    }

    private func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
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
        override var backingScaleFactor: CGFloat { 1 }
        override func convertRectToBacking(_ rect: NSRect) -> NSRect { rect }
        override func convertRectFromBacking(_ rect: NSRect) -> NSRect { rect }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    private final class TestScreenDetection: ScreenDetection {
        let screens: [NSScreen]
        let cursorScreen: NSScreen
        private(set) var cursorDetections = 0

        init(screens: [NSScreen], cursorScreen: NSScreen) {
            self.screens = screens
            self.cursorScreen = cursorScreen
        }

        override func detectScreens(using window: AccessibilityElement?) -> UsableScreens? {
            window.flatMap { screenContaining($0.frame, screens: screens) }.map {
                UsableScreens(currentScreen: $0, numScreens: screens.count)
            }
        }

        override func detectScreensAtCursor() -> UsableScreens? {
            cursorDetections += 1
            return UsableScreens(currentScreen: cursorScreen, numScreens: screens.count)
        }
    }

    func testTilingUsesFocusedDisplayOrPointerFallback() throws {
        if Defaults.todo.userEnabled, Defaults.todoMode.enabled {
            return // skip testing with todo mode enabled to avoid a crash with screen comparison against mock screen
        }
        
        let left = TestScreen(frame: CGRect(x: -900, y: 0, width: 900, height: 600))
        let right = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))

        for cursorScreen in [left, right] {
            let otherScreen = cursorScreen === left ? right : left
            for hasFocus in [true, false] {
                for action in [WindowAction.tileAll, .tileRows, .tileColumns] {
                    let focused = TestElement(frame: otherScreen.frame.insetBy(dx: 100, dy: 100).screenFlipped,
                                              windowId: 101, identity: 1)
                    let underPointer = TestElement(frame: cursorScreen.frame.insetBy(dx: 100, dy: 100).screenFlipped,
                                                   windowId: 102, identity: 2)
                    let detection = TestScreenDetection(screens: [left, right], cursorScreen: cursorScreen)
                    let context = try XCTUnwrap(Manager.tilingContext(focusedWindow: hasFocus ? focused : nil,
                                                                      screenDetection: detection))
                    let expectedScreen = hasFocus ? otherScreen : cursorScreen
                    XCTAssertTrue(context.screens.currentScreen === expectedScreen)
                    XCTAssertEqual(detection.cursorDetections, hasFocus ? 0 : 1)
                    let windows = Manager.windowsOnScreen(screens: context.screens,
                                                          windows: [focused, underPointer],
                                                          screenFor: { detection.detectScreens(using: $0)?.currentScreen }).windows
                    let visibleInfo = [visible(101, frame: focused.frame), visible(102, frame: underPointer.frame)]
                    switch action {
                    case .tileRows, .tileColumns:
                        Manager.tileWindowsInBands(action == .tileRows ? .rows : .columns,
                                                   focusedWindow: context.focusedWindow, windows: windows,
                                                   visibleWindowInfo: visibleInfo, screen: context.screens.currentScreen,
                                                   visibleFrame: context.screens.currentScreen.frame)
                    case .tileAll:
                        Manager.tileAllWindowsOnScreen(windows: windows, screen: context.screens.currentScreen)
                    default:
                        XCTFail("Unexpected tiling action")
                    }
                    XCTAssertGreaterThan((hasFocus ? focused : underPointer).setFrameCalls, 0)
                    XCTAssertEqual((hasFocus ? underPointer : focused).setFrameCalls, 0)
                }
            }
        }
    }

    func testNonWindowFocusUsesPointerDisplay() throws {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let desktop = TestElement(frame: screen.frame, ordinaryWindow: false)
        let detection = TestScreenDetection(screens: [screen], cursorScreen: screen)
        let context = try XCTUnwrap(Manager.tilingContext(focusedWindow: desktop, screenDetection: detection))
        XCTAssertNil(context.focusedWindow)
        XCTAssertTrue(context.screens.currentScreen === screen)
        XCTAssertEqual(detection.cursorDetections, 1)
        XCTAssertEqual(desktop.setFrameCalls, 0)
    }

    func testBandTilingWithoutFocusStillRequiresCurrentSpaceEvidence() {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let frame = screen.frame.insetBy(dx: 100, dy: 100).screenFlipped
        for direction in [Manager.BandDirection.rows, .columns] {
            let currentSpace = TestElement(frame: frame, windowId: 101, identity: 1)
            let otherSpace = TestElement(frame: frame, windowId: 999, identity: 2)
            Manager.tileWindowsInBands(direction, focusedWindow: nil, windows: [currentSpace, otherSpace],
                                       visibleWindowInfo: [visible(101, frame: frame)], screen: screen,
                                       visibleFrame: screen.frame)
            XCTAssertGreaterThan(currentSpace.setFrameCalls, 0)
            XCTAssertEqual(otherSpace.setFrameCalls, 0)
        }
    }

    func testEmptyPointerDisplayDoesNotMoveWindowsOnAnotherDisplay() throws {
        let emptyScreen = TestScreen(frame: CGRect(x: -900, y: 0, width: 900, height: 600))
        let occupiedScreen = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let window = TestElement(frame: occupiedScreen.frame.insetBy(dx: 100, dy: 100).screenFlipped,
                                 windowId: 101, identity: 1)
        let detection = TestScreenDetection(screens: [emptyScreen, occupiedScreen], cursorScreen: emptyScreen)
        let context = try XCTUnwrap(Manager.tilingContext(focusedWindow: nil, screenDetection: detection))
        let windows = Manager.windowsOnScreen(screens: context.screens, windows: [window],
                                              screenFor: { detection.detectScreens(using: $0)?.currentScreen }).windows
        XCTAssertTrue(windows.isEmpty)
        for direction in [Manager.BandDirection.rows, .columns] {
            Manager.tileWindowsInBands(direction, focusedWindow: nil, windows: windows,
                                       visibleWindowInfo: [visible(101, frame: window.frame)], screen: emptyScreen,
                                       visibleFrame: emptyScreen.frame)
        }
        Manager.tileAllWindowsOnScreen(windows: windows, screen: emptyScreen)
        XCTAssertEqual(window.setFrameCalls, 0)
    }

    func testSelectionKeepsCoveredWindowsAndIdenticalOnScreenTwinsWithoutOtherSpaceWindows() {
        let sameFrame = CGRect(x: 10, y: 20, width: 200, height: 200)
        let first = candidate(TestElement(), frame: sameFrame, identity: 1, focused: true)
        let second = candidate(TestElement(), frame: sameFrame, identity: 2)
        let twoVisible = [visible(101, frame: sameFrame), visible(102, frame: sameFrame)]
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([first, second], visibleWindowInfo: twoVisible)
            .map(testLabel), [1, 2])
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([first, second], visibleWindowInfo: [twoVisible[0]])
            .map(testLabel), [1])

        let coveredFrame = CGRect(x: 300, y: 20, width: 200, height: 200)
        let covered = candidate(TestElement(), frame: coveredFrame, identity: 3)
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([first, covered],
            visibleWindowInfo: [twoVisible[0], visible(103, frame: coveredFrame)])
            .map(testLabel), [1, 3])
    }

    func testIdlessSelectionDoesNotUseAnotherAppAsCurrentSpaceEvidence() {
        let focusedFrame = CGRect(x: 10, y: 20, width: 200, height: 200)
        let otherSpaceFrame = CGRect(x: 300, y: 20, width: 200, height: 200)
        let focused = candidate(TestElement(), frame: focusedFrame, identity: 1,
                                windowId: 101, focused: true)
        let otherSpace = candidate(TestElement(), frame: otherSpaceFrame, identity: 2)
        let onScreen = [visible(101, frame: focusedFrame),
                        visible(201, frame: otherSpaceFrame, pid: 43)]

        XCTAssertEqual(Manager.selectCurrentSpaceWindows([focused, otherSpace],
                                                         visibleWindowInfo: onScreen)
            .map(testLabel), [1])
    }

    func testSelectionUsesRawIdsAndAccountsForIdentifiedSameFrameWindows() {
        let frame = CGRect(x: 10, y: 20, width: 200, height: 200)
        let identified = candidate(TestElement(), frame: frame, identity: 1, windowId: 101)
        let unidentified = candidate(TestElement(), frame: frame, identity: 2)
        let otherSpace = candidate(TestElement(), frame: frame, identity: 3, windowId: 999)
        let onScreen = [visible(101, frame: frame), visible(102, frame: frame)]

        XCTAssertEqual(Manager.selectCurrentSpaceWindows([identified, unidentified, otherSpace],
                        visibleWindowInfo: onScreen).map(testLabel), [1, 2])
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([identified, unidentified, otherSpace],
                        visibleWindowInfo: [onScreen[0]]).map(testLabel), [1])
    }

    func testIdlessSelectionToleratesFrameRoundingWithoutReusingAnIdentifiedCGWindow() {
        let axFrame = CGRect(x: 300.5, y: 20, width: 200.5, height: 200)
        let cgFrame = CGRect(x: 301, y: 20, width: 201, height: 200)
        let current = candidate(TestElement(), frame: axFrame, identity: 1)
        let onScreen = visible(101, frame: cgFrame)

        XCTAssertEqual(Manager.selectCurrentSpaceWindows([current], visibleWindowInfo: [onScreen],
                                                         frameTolerance: 0.5).map(testLabel), [1])

        let identified = candidate(TestElement(), frame: axFrame, identity: 2, windowId: 101)
        let otherSpace = candidate(TestElement(), frame: cgFrame, identity: 3)
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([identified, otherSpace],
                                                         visibleWindowInfo: [onScreen],
                                                         frameTolerance: 0.5).map(testLabel), [2])

        let focused = candidate(TestElement(), frame: axFrame, identity: 4, focused: true)
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([focused, otherSpace],
                                                         visibleWindowInfo: [onScreen],
                                                         frameTolerance: 0.5).map(testLabel), [4])
    }

    func testIdlessSelectionAppliesRoundingToleranceToEachFrameComponent() {
        let frame = CGRect(x: -300, y: -20, width: 200, height: 100)
        let window = candidate(TestElement(), frame: frame, identity: 1)
        let roundedFrames = [
            CGRect(x: -299.5, y: -19.5, width: 200.5, height: 100.5),
            CGRect(x: -300.5, y: -20.5, width: 199.5, height: 99.5)
        ]
        for rounded in roundedFrames {
            XCTAssertEqual(Manager.selectCurrentSpaceWindows([window],
                visibleWindowInfo: [visible(101, frame: rounded)], frameTolerance: 0.5).map(testLabel), [1])
        }

        // No single component may exceed the tolerance, even if changes to
        // position and size cancel out at the far edge.
        let differentFrames = [
            CGRect(x: -299.25, y: -20, width: 199.25, height: 100),
            CGRect(x: -300, y: -19.25, width: 200, height: 99.25),
            CGRect(x: -300.5, y: -20, width: 200.75, height: 100),
            CGRect(x: -300, y: -20.5, width: 200, height: 100.75)
        ]
        for different in differentFrames {
            XCTAssertTrue(Manager.selectCurrentSpaceWindows([window],
                visibleWindowInfo: [visible(101, frame: different)], frameTolerance: 0.5).isEmpty)
        }
    }

    func testSelectionIncludesDistinctMatchesAcrossOverlappingTolerance() {
        let frames = [CGFloat(0), 0.5, 1].map {
            CGRect(x: $0, y: 20, width: 100, height: 100)
        }
        let candidates = frames.enumerated().map { index, frame in
            candidate(TestElement(), frame: frame, identity: CFHashCode(index + 1), focused: index == 0)
        }
        let onScreen = frames.enumerated().map { index, frame in
            visible(CGWindowID(index + 101), frame: frame)
        }
        XCTAssertEqual(Manager.selectCurrentSpaceWindows(candidates, visibleWindowInfo: onScreen,
                                                         frameTolerance: 0.5).map(testLabel), [1, 2, 3])

        let shared = candidate(TestElement(), frame: frames[1], identity: 4)
        let onlyFirst = candidate(TestElement(), frame: frames[0], identity: 5)
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([shared, onlyFirst],
                                                         visibleWindowInfo: [onScreen[0], onScreen[2]],
                                                         frameTolerance: 0.5).map(testLabel), [4, 5])
    }

    func testSelectionKeepsForcedMatchesAndExcludesAmbiguousOnes() {
        let sharedFrame = CGRect(x: 0, y: 20, width: 100, height: 100)
        let middleFrame = sharedFrame.offsetBy(dx: 0.5, dy: 0)
        let focused = candidate(TestElement(), frame: sharedFrame, identity: 1, focused: true)
        let ambiguous = candidate(TestElement(), frame: sharedFrame, identity: 2)
        let forced = candidate(TestElement(), frame: middleFrame, identity: 3)
        let onScreen = [visible(101, frame: sharedFrame),
                        visible(102, frame: sharedFrame.offsetBy(dx: 0.9, dy: 0)),
                        visible(103, frame: sharedFrame.offsetBy(dx: 1, dy: 0))]
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([focused, ambiguous, forced],
                                                         visibleWindowInfo: onScreen,
                                                         frameTolerance: 0.5).map(testLabel), [1, 3])

        // Repeating the same CG ID must not manufacture a second witness.
        XCTAssertEqual(Manager.selectCurrentSpaceWindows([focused, ambiguous],
                                                         visibleWindowInfo: [onScreen[0], onScreen[0]],
                                                         frameTolerance: 0.5).map(testLabel), [1])
    }

    func testBandActionComposesCurrentSpaceSelectionOrderingAndPlacement() throws {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let available = screen.frame.screenFlipped
        let bounds = Manager.BackingPixelBounds(screen.frame)
        let screens = UsableScreens(currentScreen: screen, numScreens: 2)
        let otherScreen = TestScreen(frame: screen.frame.offsetBy(dx: screen.frame.width, dy: 0))
        XCTAssertNotEqual(otherScreen, screen)
        let upperLeft = CGRect(x: available.minX + 10, y: available.minY + 10, width: 100, height: 100)
        let lowerRight = CGRect(x: available.minX + 60, y: available.minY + 60, width: 100, height: 100)

        for direction in [Manager.BandDirection.rows, .columns] {
            let focused = TestElement(frame: upperLeft, windowId: 101, identity: 1)
            let covered = TestElement(frame: lowerRight, windowId: 102, identity: 2)
            let otherSpace = TestElement(frame: lowerRight, windowId: 999, identity: 3)
            let otherDisplay = TestElement(frame: lowerRight, windowId: 103, identity: 4)
            let windows = Manager.windowsOnScreen(screens: screens,
                                                  windows: [covered, otherSpace, otherDisplay],
                                                  focusedWindow: focused,
                                                  screenFor: { $0 === otherDisplay ? otherScreen : screen }).windows
            Manager.tileWindowsInBands(direction, focusedWindow: focused,
                                       windows: windows,
                                       visibleWindowInfo: [visible(102, frame: lowerRight),
                                                           visible(103, frame: otherDisplay.frame)],
                                       screen: screen, visibleFrame: screen.frame)

            XCTAssertGreaterThan(focused.setFrameCalls, 0)
            XCTAssertGreaterThan(covered.setFrameCalls, 0)
            XCTAssertEqual(otherSpace.setFrameCalls, 0)
            XCTAssertEqual(otherSpace.frame, lowerRight)
            XCTAssertEqual(otherDisplay.setFrameCalls, 0)
            XCTAssertEqual(otherDisplay.frame, lowerRight)

            let first = screen.convertRectToBacking(focused.frame.screenFlipped)
            let second = screen.convertRectToBacking(covered.frame.screenFlipped)
            if direction == .rows {
                XCTAssertEqual(first.maxY, CGFloat(bounds.top), accuracy: 0.5)
                XCTAssertEqual(first.minY, second.maxY, accuracy: 0.5)
                XCTAssertEqual(second.minY, CGFloat(bounds.bottom), accuracy: 0.5)
                XCTAssertEqual(first.minX, CGFloat(bounds.left), accuracy: 0.5)
                XCTAssertEqual(second.maxX, CGFloat(bounds.right), accuracy: 0.5)
            } else {
                XCTAssertEqual(first.minX, CGFloat(bounds.left), accuracy: 0.5)
                XCTAssertEqual(first.maxX, second.minX, accuracy: 0.5)
                XCTAssertEqual(second.maxX, CGFloat(bounds.right), accuracy: 0.5)
                XCTAssertEqual(first.minY, CGFloat(bounds.bottom), accuracy: 0.5)
                XCTAssertEqual(second.maxY, CGFloat(bounds.top), accuracy: 0.5)
            }
        }
    }

    func testBandTilingExcludesTodoEvenWhenFocused() {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let screens = UsableScreens(currentScreen: screen, numScreens: 1)
        let workArea = CGRect(x: 0, y: 0, width: 800, height: 600)
        let sidebar = CGRect(x: 800, y: 0, width: 200, height: 600).screenFlipped

        for direction in [Manager.BandDirection.rows, .columns] {
            for todoIsFocused in [false, true] {
                let ordinary = TestElement(frame: workArea.insetBy(dx: 100, dy: 100).screenFlipped,
                                           windowId: 701, identity: 1)
                let todo = TestElement(frame: sidebar, windowId: 702, identity: 2)
                let focused = todoIsFocused ? todo : ordinary
                // Focus recovery must not reintroduce Todo after the exclusion.
                let windows = Manager.windowsOnScreen(screens: screens,
                                                      windows: todoIsFocused ? [ordinary] : [ordinary, todo],
                                                      focusedWindow: focused,
                                                      isActiveTodoWindow: { $0 === todo },
                                                      screenFor: { _ in screen }).windows
                XCTAssertEqual(windows.map(\.windowId), [701])
                Manager.tileWindowsInBands(direction, focusedWindow: focused, windows: windows,
                                           visibleWindowInfo: [visible(701, frame: ordinary.frame),
                                                               visible(702, frame: todo.frame)],
                                           screen: screen, visibleFrame: workArea)

                XCTAssertGreaterThan(ordinary.setFrameCalls, 0)
                XCTAssertEqual(ordinary.frame, workArea.screenFlipped)
                XCTAssertEqual(todo.setFrameCalls, 0)
                XCTAssertEqual(todo.frame, sidebar)
            }
        }
    }

    func testBandTilingHonorsCombinedDisplayBoundsAndSpaceSelection() {
        let left = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let right = TestScreen(frame: CGRect(x: 900, y: 0, width: 900, height: 600))
        let screens = UsableScreens(currentScreen: left, numScreens: 2)

        for combineScreens in [false, true] {
            for direction in [Manager.BandDirection.rows, .columns] {
                let focused = TestElement(frame: left.frame.insetBy(dx: 100, dy: 100).screenFlipped,
                                          windowId: 901, identity: 1)
                let onRight = TestElement(frame: right.frame.insetBy(dx: 100, dy: 100).screenFlipped,
                                          windowId: 902, identity: 2)
                let otherSpace = TestElement(frame: onRight.frame, windowId: 999, identity: 3)
                let originalRightFrame = onRight.frame
                let windows = Manager.windowsOnScreen(screens: screens, windows: [focused, onRight, otherSpace],
                                                      focusedWindow: focused, combineScreens: combineScreens,
                                                      screenFor: { $0 === focused ? left : right }).windows
                let workArea = combineScreens ? left.frame.union(right.frame) : left.frame
                Manager.tileWindowsInBands(direction, focusedWindow: focused, windows: windows,
                                           visibleWindowInfo: [visible(901, frame: focused.frame),
                                                               visible(902, frame: onRight.frame)],
                                           screen: left, visibleFrame: workArea)

                XCTAssertEqual(otherSpace.setFrameCalls, 0)
                XCTAssertEqual(otherSpace.frame, originalRightFrame)
                if combineScreens {
                    let first = direction == .rows
                        ? CGRect(x: 0, y: 300, width: 1800, height: 300)
                        : CGRect(x: 0, y: 0, width: 900, height: 600)
                    let second = direction == .rows
                        ? CGRect(x: 0, y: 0, width: 1800, height: 300)
                        : CGRect(x: 900, y: 0, width: 900, height: 600)
                    XCTAssertEqual(focused.frame, first.screenFlipped)
                    XCTAssertEqual(onRight.frame, second.screenFlipped)
                    XCTAssertGreaterThan(onRight.setFrameCalls, 0)
                } else {
                    XCTAssertEqual(focused.frame, left.frame.screenFlipped)
                    XCTAssertEqual(onRight.frame, originalRightFrame)
                    XCTAssertEqual(onRight.setFrameCalls, 0)
                }
            }
        }
    }

    func testBandActionDerivesFixedAndReportedMinimumConstraints() throws {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        let available = screen.frame.screenFlipped
        let bounds = Manager.BackingPixelBounds(screen.frame)

        for direction in [Manager.BandDirection.rows, .columns] {
            let extent = bounds.extent(direction)
            guard extent > 400 else { throw XCTSkip("Display is too small for the constraint fixture") }
            let fixedPixels = extent / 8
            let minimumPixels = extent * 5 / 8
            let fixedPoints = CGFloat(fixedPixels) / screen.backingScaleFactor
            let minimumPoints = CGFloat(minimumPixels) / screen.backingScaleFactor
            let fixedFrame = CGRect(x: available.minX + 10, y: available.minY + 10,
                                    width: direction == .rows ? available.width : fixedPoints,
                                    height: direction == .rows ? fixedPoints : available.height)
            let laterFrame = CGRect(x: available.minX + 40, y: available.minY + 40,
                                    width: 100, height: 100)
            let reportedMinimum = direction == .rows
                ? CGSize(width: 0, height: minimumPoints)
                : CGSize(width: minimumPoints, height: 0)
            let fixed = TestElement(frame: fixedFrame, windowId: 501, identity: 1, canResize: false)
            let minimum = TestElement(frame: laterFrame, windowId: 502, identity: 2,
                                      reportedMinimumSize: reportedMinimum)
            let flexible = TestElement(frame: laterFrame.offsetBy(dx: 30, dy: 30), windowId: 503, identity: 3)
            let elements = [fixed, minimum, flexible]
            Manager.tileWindowsInBands(direction, focusedWindow: fixed, windows: elements,
                                       visibleWindowInfo: [visible(501, frame: fixed.frame),
                                                           visible(502, frame: minimum.frame),
                                                           visible(503, frame: flexible.frame)],
                                       screen: screen, visibleFrame: screen.frame)

            let lengths = elements.map { element in
                let size = screen.convertRectToBacking(element.frame.screenFlipped).size
                return Int((direction == .rows ? size.height : size.width).rounded())
            }
            XCTAssertEqual(lengths, [fixedPixels, minimumPixels, extent - fixedPixels - minimumPixels])
            XCTAssertTrue(elements.allSatisfy { $0.setFrameCalls > 0 })
        }
    }

    func testRowsAndColumnsUsePreMoveCorners() {
        let topRight = candidate(TestElement(), frame: CGRect(x: 400, y: 0, width: 100, height: 100),
                                 identity: 4, windowId: 104)
        let bottomLeft = candidate(TestElement(), frame: CGRect(x: 0, y: 400, width: 100, height: 100),
                                   identity: 5, windowId: 105)
        XCTAssertEqual(Manager.orderForBandTiling([bottomLeft, topRight], direction: .rows)
            .map(testLabel), [4, 5])
        XCTAssertEqual(Manager.orderForBandTiling([topRight, bottomLeft], direction: .columns)
            .map(testLabel), [5, 4])

        let sameRowLeft = candidate(TestElement(), frame: CGRect(x: 0, y: 20, width: 100, height: 100), identity: 7)
        let sameRowRight = candidate(TestElement(), frame: CGRect(x: 400, y: 20, width: 100, height: 100), identity: 6)
        XCTAssertEqual(Manager.orderForBandTiling([sameRowRight, sameRowLeft], direction: .rows)
            .map(testLabel), [7, 6])
        let sameColumnTop = candidate(TestElement(), frame: CGRect(x: 10, y: 0, width: 100, height: 100), identity: 9)
        let sameColumnBottom = candidate(TestElement(), frame: CGRect(x: 10, y: 400, width: 100, height: 100), identity: 8)
        XCTAssertEqual(Manager.orderForBandTiling([sameColumnBottom, sameColumnTop], direction: .columns)
            .map(testLabel), [9, 8])
    }

    func testMinimumBoundWindowsDoNotConsumeRemainderPixels() {
        let constraints: [Manager.BandConstraint] = [5, 5, 1, 1, 1].map {
            .resizable(minimum: $0, maximum: 17)
        }
        let result = GridTiling.balancedBandLengths(totalPixels: 17, constraints: constraints)
        XCTAssertTrue(result.feasible)
        XCTAssertEqual(result.lengths, [5, 5, 3, 2, 2])
    }

    func testRealizedRowsFillAtOneAndTwoPointScalesWithOnePixelRemainder() {
        let bounds = Manager.BackingPixelBounds(CGRect(x: 20, y: 10, width: 1200, height: 901))
        for scale in [CGFloat(1), CGFloat(2)] {
            let elements = (0..<3).map { _ in TestElement() }
            let windows = elements.enumerated().map { index, element in
                candidate(element, frame: CGRect(x: CGFloat(index * 100), y: 0, width: 100, height: 100),
                          identity: CFHashCode(index + 1))
            }
            let constraints = Array(repeating: Manager.BandConstraint.resizable(minimum: 0, maximum: 901), count: 3)
            applyBandTiling(windows, bounds: bounds, direction: .rows, constraints: constraints,
                                    pointFrame: { self.scaled($0, by: 1 / scale) },
                                    backingFrame: { self.scaled($0, by: scale) })
            let achieved = elements.map { scaled($0.frame, by: scale) }
            XCTAssertEqual(achieved.map(\.height), [301, 300, 300])
            XCTAssertEqual(achieved.map(\.width), [1200, 1200, 1200])
            XCTAssertEqual(achieved.first?.maxY, 911)
            XCTAssertEqual(achieved[0].minY, achieved[1].maxY)
            XCTAssertEqual(achieved[1].minY, achieved[2].maxY)
            XCTAssertEqual(achieved.last?.minY, 10)
        }
    }

    func testRealizedColumnsAndSingleWindowFillTheirBackingPixelBounds() {
        let bounds = Manager.BackingPixelBounds(CGRect(x: 10, y: 20, width: 901, height: 1200))
        let elements = (0..<3).map { _ in TestElement() }
        let windows = elements.enumerated().map { index, element in
            candidate(element, frame: CGRect(x: CGFloat(index * 100), y: 0, width: 100, height: 100),
                      identity: CFHashCode(index + 1))
        }
        let constraints = Array(repeating: Manager.BandConstraint.resizable(minimum: 0, maximum: 901), count: 3)
        applyBandTiling(windows, bounds: bounds, direction: .columns, constraints: constraints,
                                pointFrame: { self.scaled($0, by: 0.5) },
                                backingFrame: { self.scaled($0, by: 2) })
        let achieved = elements.map { scaled($0.frame, by: 2) }
        XCTAssertEqual(achieved.map(\.width), [301, 300, 300])
        XCTAssertEqual(achieved.map(\.height), [1200, 1200, 1200])
        XCTAssertEqual(achieved.first?.minX, 10)
        XCTAssertEqual(achieved[0].maxX, achieved[1].minX)
        XCTAssertEqual(achieved[1].maxX, achieved[2].minX)
        XCTAssertEqual(achieved.last?.maxX, 911)

        let single = TestElement()
        applyBandTiling([candidate(single, frame: .zero, identity: 4)],
                                bounds: bounds, direction: .rows,
                                constraints: [.resizable(minimum: 0, maximum: 1200)],
                                pointFrame: { $0 }, backingFrame: { $0 })
        XCTAssertEqual(single.frame, CGRect(x: 10, y: 20, width: 901, height: 1200))
    }

    func testFixedExtentAndUnreportedMinimumRebalanceAchievedFrames() {
        let bounds = Manager.BackingPixelBounds(CGRect(x: 0, y: 0, width: 600, height: 900))
        let fixed = TestElement()
        let flexible = TestElement()
        let fixedWindows = [candidate(fixed, frame: CGRect(x: 0, y: 0, width: 600, height: 100), identity: 1),
                            candidate(flexible, frame: CGRect(x: 0, y: 100, width: 600, height: 100), identity: 2)]
        applyBandTiling(fixedWindows, bounds: bounds, direction: .rows,
                                constraints: [.fixed(100), .resizable(minimum: 0, maximum: 900)],
                                pointFrame: { $0 }, backingFrame: { $0 })
        XCTAssertEqual([fixed.frame.height, flexible.frame.height], [100, 800])
        XCTAssertEqual(fixed.frame.minY, flexible.frame.maxY)
        XCTAssertEqual(flexible.frame.minY, 0)

        let clamped = TestElement(minimumHeight: 500)
        let others = [TestElement(), TestElement()]
        let elements = [clamped] + others
        let windows = elements.enumerated().map { index, element in
            candidate(element, frame: CGRect(x: 0, y: CGFloat(index * 100), width: 600, height: 100),
                      identity: CFHashCode(index + 1))
        }
        applyBandTiling(windows, bounds: bounds, direction: .rows,
                                constraints: Array(repeating: .resizable(minimum: 0, maximum: 900), count: 3),
                                pointFrame: { $0 }, backingFrame: { $0 })
        XCTAssertEqual(elements.map { $0.frame.height }, [500, 200, 200])
        XCTAssertEqual(elements[0].frame.maxY, 900)
        XCTAssertEqual(elements[0].frame.minY, elements[1].frame.maxY)
        XCTAssertEqual(elements[1].frame.minY, elements[2].frame.maxY)
        XCTAssertEqual(elements[2].frame.minY, 0)
    }

    func testObservedMaximumRedistributesToAnotherResizableWindow() {
        let bounds = Manager.BackingPixelBounds(CGRect(x: 0, y: 0, width: 900, height: 600))
        let capped = TestElement(maximumWidth: 200)
        let flexible = TestElement()
        let windows = [candidate(capped, frame: CGRect(x: 0, y: 0, width: 100, height: 600), identity: 1),
                       candidate(flexible, frame: CGRect(x: 100, y: 0, width: 100, height: 600), identity: 2)]
        applyBandTiling(windows, bounds: bounds, direction: .columns,
                                constraints: [.resizable(minimum: 0, maximum: 900), .resizable(minimum: 0, maximum: 900)],
                                pointFrame: { $0 }, backingFrame: { $0 })
        XCTAssertEqual([capped.frame.width, flexible.frame.width], [200, 700])
        XCTAssertEqual(capped.frame.maxX, flexible.frame.minX)
        XCTAssertEqual(flexible.frame.maxX, 900)
    }

    func testConstraintRefinementDoesNotReapplyAlreadyAchievedFrames() {
        let elements = [TestElement(minimumHeight: 1100), TestElement(minimumHeight: 975),
                        TestElement(minimumHeight: 965), TestElement()]
        let windows = elements.enumerated().map { index, element in
            candidate(element, frame: CGRect(x: 0, y: CGFloat(index * 100), width: 600, height: 100),
                      identity: CFHashCode(index + 1))
        }
        applyBandTiling(windows,
                                bounds: Manager.BackingPixelBounds(CGRect(x: 0, y: 0, width: 600, height: 4000)),
                                direction: .rows,
                                constraints: Array(repeating: .resizable(minimum: 0, maximum: 4000), count: 4),
                                pointFrame: { $0 }, backingFrame: { $0 })

        XCTAssertEqual(elements.map { $0.frame.height }, [1100, 975, 965, 960])
        XCTAssertLessThan(elements.map(\.setFrameCalls).reduce(0, +), 12)
    }

    func testFinalPositionClampReplansTheAchievedBands() {
        let positionSensitive = TestElement(minimumHeightAtOrigin: { $0 <= 400 ? 550 : 500 })
        let flexible = TestElement()
        let windows = [candidate(positionSensitive, frame: CGRect(x: 0, y: 0, width: 600, height: 100),
                                 identity: 1),
                       candidate(flexible, frame: CGRect(x: 0, y: 100, width: 600, height: 100),
                                 identity: 2)]
        applyBandTiling(windows,
                                bounds: Manager.BackingPixelBounds(CGRect(x: 0, y: 0, width: 600, height: 900)),
                                direction: .rows,
                                constraints: Array(repeating: .resizable(minimum: 0, maximum: 900), count: 2),
                                pointFrame: { $0 }, backingFrame: { $0 })

        XCTAssertEqual([positionSensitive.frame.height, flexible.frame.height], [550, 350])
        XCTAssertEqual(positionSensitive.frame.maxY, 900)
        XCTAssertEqual(positionSensitive.frame.minY, flexible.frame.maxY)
        XCTAssertEqual(flexible.frame.minY, 0)
    }

    func testImpossibleRestrictionsStillAttemptAllWindows() {
        let constraints: [Manager.BandConstraint] = [
            .resizable(minimum: 500, maximum: 900),
            .resizable(minimum: 500, maximum: 900),
            .resizable(minimum: 0, maximum: 900)
        ]
        let result = GridTiling.balancedBandLengths(totalPixels: 900, constraints: constraints)
        XCTAssertFalse(result.feasible)
        XCTAssertEqual(result.lengths, [300, 300, 300])

        // The first hidden minimum is feasible; the second makes the set
        // infeasible, so finish from the last feasible allocation.
        let elements = [TestElement(minimumHeight: 500), TestElement(minimumHeight: 500), TestElement()]
        let windows = elements.enumerated().map { index, element in
            candidate(element, frame: CGRect(x: 0, y: CGFloat(index * 100), width: 600, height: 100),
                      identity: CFHashCode(index + 1))
        }
        applyBandTiling(windows,
                                bounds: Manager.BackingPixelBounds(CGRect(x: 0, y: 0, width: 600, height: 900)),
                                direction: .rows,
                                constraints: Array(repeating: .resizable(minimum: 0, maximum: 900), count: 3),
                                pointFrame: { $0 }, backingFrame: { $0 })
        XCTAssertTrue(elements.allSatisfy { $0.setFrameCalls > 0 })
        XCTAssertEqual(elements.map { $0.frame.minY }, [400, 200, 0])
    }

}

final class FootprintAlphaDefaultsTests: XCTestCase {
    private var savedAlpha: Double = 0
    private var savedBlur = false
    private var storedAlpha: Any?
    private var storedBlur: Any?

    override func setUp() {
        super.setUp()
        savedAlpha = Defaults.footprintAlpha.value
        savedBlur = Defaults.footprintBlur.enabled
        storedAlpha = UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key)
        storedBlur = UserDefaults.standard.object(forKey: Defaults.footprintBlur.key)
        UserDefaults.standard.removeObject(forKey: Defaults.footprintAlpha.key)
    }

    override func tearDown() {
        Defaults.footprintAlpha.value = savedAlpha
        Defaults.footprintBlur.enabled = savedBlur
        UserDefaults.standard.set(storedAlpha, forKey: Defaults.footprintAlpha.key)
        UserDefaults.standard.set(storedBlur, forKey: Defaults.footprintBlur.key)
        super.tearDown()
    }

    func testUnsetAlphaFollowsPreviewStyleWithoutSavingAValue() {
        let window = FootprintWindow(accessibility: {
            FootprintAccessibility(reduceMotion: false, reduceTransparency: false)
        })
        defer { window.close() }

        for blurred in [false, true, false] {
            Defaults.footprintBlur.enabled = blurred
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, blurred ? 0 : 0.3)
            XCTAssertEqual(window.presentation.alpha, blurred ? 1 : 0.3)
            XCTAssertEqual(window.presentation.usesBlur, blurred)
            XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key))
        }
    }

    func testExplicitZeroSurvivesStyleChangesReloadAndConfigRoundTrip() throws {
        Defaults.footprintAlpha.value = 0
        for blurred in [false, true] {
            Defaults.footprintBlur.enabled = blurred
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, 0)
            XCTAssertEqual(DoubleDefault(key: Defaults.footprintAlpha.key).value, 0)

            let exported = try exportedAlpha()
            XCTAssertEqual(exported.double, 0)
            XCTAssertNil(exported.float)
            Defaults.footprintAlpha.value = 0.8
            Defaults.footprintAlpha.load(from: exported)
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, 0)
        }
    }

    func testLegacyFloatValuesAndDoublePrecisionArePreserved() throws {
        for json in [#"{"float":0}"#, #"{"float":0.4}"#, #"{"double":0.123456789012345}"#] {
            let imported = try JSONDecoder().decode(CodableDefault.self, from: Data(json.utf8))
            let expected = imported.double ?? Double(imported.float!)
            Defaults.footprintAlpha.load(from: imported)
            for blurred in [false, true] {
                Defaults.footprintBlur.enabled = blurred
                XCTAssertEqual(Defaults.effectiveFootprintAlpha, expected)
                XCTAssertEqual(DoubleDefault(key: Defaults.footprintAlpha.key).value, expected)
                XCTAssertEqual(try exportedAlpha().double, expected)
            }
        }
    }

    func testExportUsesTheEffectiveUnsetAlpha() throws {
        for blurred in [false, true] {
            UserDefaults.standard.removeObject(forKey: Defaults.footprintAlpha.key)
            Defaults.footprintBlur.enabled = blurred
            let exported = try exportedAlpha()
            XCTAssertEqual(exported.double, blurred ? 0 : 0.3)
            XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key))

            Defaults.footprintAlpha.value = 0.8
            Defaults.footprintAlpha.load(from: exported)
            XCTAssertEqual(Defaults.effectiveFootprintAlpha, blurred ? 0 : 0.3)
        }
    }

    private func exportedAlpha() throws -> CodableDefault {
        let json = try XCTUnwrap(Defaults.encoded())
        let config = try XCTUnwrap(Defaults.convert(jsonString: json))
        return try XCTUnwrap(config.defaults[Defaults.footprintAlpha.key])
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

class CooperativeResizeSourceTests: XCTestCase {

    func testKeyboardShortcutsAndDragSnappingAllowCooperativeResize() {
        XCTAssertTrue(ExecutionSource.keyboardShortcut.allowsCooperativeResize)
        XCTAssertTrue(ExecutionSource.dragToSnap.allowsCooperativeResize)
    }

    func testNonSnappingSourcesDoNotAllowCooperativeResize() {
        XCTAssertFalse(ExecutionSource.menuItem.allowsCooperativeResize)
        XCTAssertFalse(ExecutionSource.url.allowsCooperativeResize)
        XCTAssertFalse(ExecutionSource.titleBar.allowsCooperativeResize)
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

class DefaultsExportTests: XCTestCase {

    func testOverlapDefaultsInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("cyclingOverlapOffset"), "cyclingOverlapOffset missing from Defaults.array")
        XCTAssertTrue(keys.contains("cyclingOverlapOffsetSize"), "cyclingOverlapOffsetSize missing from Defaults.array")
        XCTAssertTrue(keys.contains("cyclingOverlapMaxCascade"), "cyclingOverlapMaxCascade missing from Defaults.array")
        XCTAssertTrue(keys.contains("cooperativeCornerResize"), "cooperativeCornerResize missing from Defaults.array")
        XCTAssertTrue(keys.contains("stackBadge"), "stackBadge missing from Defaults.array")
        XCTAssertTrue(keys.contains("stackSameSizeOnly"), "stackSameSizeOnly missing from Defaults.array")
    }
}

class ConfigImportTests: XCTestCase {

    private static let shortcutKeys = WindowAction.active.map(\.name) + TodoManager.defaultsKeys + StackBadgeManager.defaultsKeys
    private var storedValues = [String: Any]()
    private var absentKeys = Set<String>()

    override func setUp() {
        super.setUp()
        for key in Self.shortcutKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                storedValues[key] = value
            } else {
                absentKeys.insert(key)
            }
        }
    }

    override func tearDown() {
        for key in Self.shortcutKeys {
            if let value = storedValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else if absentKeys.contains(key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        storedValues.removeAll()
        absentKeys.removeAll()
        super.tearDown()
    }

    func testImportClearsOmittedActiveShortcut() throws {
        let action = WindowAction.almostMaximize
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 10), forKey: action.name)

        try loadConfig(shortcuts: [:])

        XCTAssertNil(UserDefaults.standard.object(forKey: action.name))
    }

    func testImportClearsOmittedTodoShortcut() throws {
        let defaultsKey = TodoManager.toggleDefaultsKey
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 11), forKey: defaultsKey)

        try loadConfig(shortcuts: [:])

        XCTAssertNil(UserDefaults.standard.object(forKey: defaultsKey))
    }

    func testImportClearsOmittedStackBadgeShortcut() throws {
        let defaultsKey = StackBadgeManager.toggleDefaultsKey
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 14), forKey: defaultsKey)

        try loadConfig(shortcuts: [:])

        XCTAssertNil(UserDefaults.standard.object(forKey: defaultsKey))
    }

    func testImportAppliesSuppliedActiveShortcut() throws {
        let action = WindowAction.almostMaximize
        let importedShortcut = Shortcut(NSEvent.ModifierFlags.command.rawValue, 12)

        try loadConfig(shortcuts: [action.name: importedShortcut])

        let storedShortcut = try XCTUnwrap(ShortcutCycle.shortcut(for: action))
        XCTAssertEqual(storedShortcut.keyCode, importedShortcut.keyCode)
        XCTAssertEqual(storedShortcut.modifierFlags.rawValue, importedShortcut.modifierFlags)
    }

    func testImportUsesActiveShortcutAlias() throws {
        let action = WindowAction.leftHalf
        let alias = try XCTUnwrap(action.aliasName)
        let importedShortcut = Shortcut(NSEvent.ModifierFlags.command.rawValue, 13)

        try loadConfig(shortcuts: [alias: importedShortcut])

        let storedShortcut = try XCTUnwrap(ShortcutCycle.shortcut(for: action))
        XCTAssertEqual(storedShortcut.keyCode, importedShortcut.keyCode)
        XCTAssertEqual(storedShortcut.modifierFlags.rawValue, importedShortcut.modifierFlags)
    }

    func testImportClearsInvalidActiveShortcut() throws {
        let action = WindowAction.almostMaximize
        store(Shortcut(NSEvent.ModifierFlags.command.rawValue, 14), forKey: action.name)

        try loadConfig(shortcuts: [action.name: Shortcut(NSEvent.ModifierFlags.command.rawValue, -1)])

        XCTAssertNil(UserDefaults.standard.object(forKey: action.name))
    }

    private func store(_ shortcut: Shortcut, forKey key: String) {
        let transformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let value = transformer.reverseTransformedValue(shortcut.toMASSHortcut())
        UserDefaults.standard.set(value, forKey: key)
    }

    private func loadConfig(shortcuts: [String: Shortcut]) throws {
        let config = Config(bundleId: "com.knollsoft.Rectangle",
                            version: "ConfigImportTests",
                            shortcuts: shortcuts,
                            defaults: [:])
        let data = try JSONEncoder().encode(config)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigImportTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try data.write(to: fileURL, options: .atomic)

        Defaults.load(fileUrl: fileURL, notificationCenter: NotificationCenter())
    }
}

class StackBadgeGeometryTests: XCTestCase {

    private let laptopFrame = CGRect(x: 0, y: 0, width: 2336, height: 1510)
    // Real rig geometry: external 4K TVs with negative origins.
    private let tvFrame = CGRect(x: -5212, y: 1510, width: 3840, height: 2160)

    func testCornerCountMatchesUnionOfGridFractions() {
        // Column fractions across all grids: 0, 1/4, 1/3, 1/2, 2/3, 3/4 (6 values).
        // Row fractions are the same set. 6 x 6 = 36 unique corners.
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        XCTAssertEqual(corners.count, 36)
    }

    func testCoincidentCornersAreDeduplicated() {
        // The half corner and the quarter corner at x = width/2 coincide;
        // they must appear once, not once per grid.
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        let midTop = corners.filter { abs($0.x - 1168) < 1 && abs($0.y - 1510) < 1 }
        XCTAssertEqual(midTop.count, 1)
    }

    func testScreenOriginIsACorner() {
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        XCTAssertTrue(corners.contains { abs($0.x - 0) < 1 && abs($0.y - 1510) < 1 },
                      "top-left of the screen must be a corner")
    }

    func testFarEdgesAreNotCorners() {
        // A cell's top-left can never sit on the right or bottom screen edge.
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        XCTAssertFalse(corners.contains { abs($0.x - laptopFrame.maxX) < 1 })
        XCTAssertFalse(corners.contains { abs($0.y - laptopFrame.minY) < 1 })
    }

    func testNegativeOriginScreenCorners() {
        let corners = StackBadgeGeometry.cornerPoints(in: tvFrame)
        XCTAssertEqual(corners.count, 36)
        XCTAssertTrue(corners.contains { abs($0.x - (-5212)) < 1 && abs($0.y - 3670) < 1 },
                      "top-left corner of a negative-origin screen")
        XCTAssertTrue(corners.contains { abs($0.x - (-5212 + 3840.0 / 3)) < 1 && abs($0.y - (3670 - 2160.0 / 3)) < 1 },
                      "interior ninth corner on a negative-origin screen")
    }

    func testEmptyFrameYieldsNoCorners() {
        XCTAssertTrue(StackBadgeGeometry.cornerPoints(in: .zero).isEmpty)
        XCTAssertTrue(StackBadgeGeometry.cornerPoints(in: .null).isEmpty)
    }

    func testHoverZoneHitInsideZone() {
        let corners = [CGPoint(x: 100, y: 500)]
        // 20pt right, 20pt below (AppKit y down = minus y) - inside a 30pt zone.
        let hit = StackBadgeGeometry.corner(near: CGPoint(x: 120, y: 480), in: corners, zone: 30)
        XCTAssertEqual(hit, corners[0])
    }

    func testHoverZoneMissOutsideZone() {
        let corners = [CGPoint(x: 100, y: 500)]
        XCTAssertNil(StackBadgeGeometry.corner(near: CGPoint(x: 140, y: 480), in: corners, zone: 30))
        // Above the corner is the neighboring cell - must not trigger.
        XCTAssertNil(StackBadgeGeometry.corner(near: CGPoint(x: 110, y: 520), in: corners, zone: 30))
        // Left of the corner is the neighboring cell - must not trigger.
        XCTAssertNil(StackBadgeGeometry.corner(near: CGPoint(x: 80, y: 490), in: corners, zone: 30))
    }

    func testHoverZonePicksNearestOfTwoCandidates() {
        let near = CGPoint(x: 100, y: 500)
        let far = CGPoint(x: 90, y: 510)
        let hit = StackBadgeGeometry.corner(near: CGPoint(x: 105, y: 495), in: [far, near], zone: 30)
        XCTAssertEqual(hit, near)
    }

    // Regression: the cascade offset runs +x but UP in AX y (it's applied in
    // AppKit coordinates and the y-axis flips), so clustering must accept
    // origins above the anchor. Real-world origins from a two-window stack
    // that the first implementation failed to count.
    func testStackClusterAcceptsUpwardCascade() {
        let origins = [CGPoint(x: 903, y: -2121), CGPoint(x: 892, y: -2110)]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.count, 2)
    }

    // Regression: with maxCascade capped at 1, the second and third windows
    // share an origin. All three belong to the stack.
    func testStackClusterCountsCascadeCapSharedOrigins() {
        let origins = [
            CGPoint(x: 903, y: -2121),
            CGPoint(x: 903, y: -2121),
            CGPoint(x: 892, y: -2110)
        ]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.count, 3)
    }

    func testStackClusterExcludesUnrelatedNeighbor() {
        // A window 30pt away from the anchor is a neighbor, not a stack member,
        // even though a gap-widened candidate box may have caught it.
        let origins = [CGPoint(x: 100, y: 100), CGPoint(x: 111, y: 89), CGPoint(x: 130, y: 130)]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.sorted(), [0, 1])
    }

    func testStackClusterAcceptsDownwardCascade() {
        // Edge clamping can flip the cascade direction locally; both must count.
        let origins = [CGPoint(x: 100, y: 100), CGPoint(x: 111, y: 111)]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.count, 2)
    }

    func testStackClusterEmptyInput() {
        XCTAssertTrue(StackBadgeGeometry.stackIndices(among: [], cascadeRange: 15, tolerance: 4).isEmpty)
    }





    // Regression (review finding): an unrelated window that happens to be the
    // leftmost candidate in the gap-widened box must not mask the real stack.
    func testStackClusterLeftOutlierDoesNotMaskStack() {
        let origins = [
            CGPoint(x: 100, y: 105),   // unrelated leftmost outlier
            CGPoint(x: 120, y: 100),   // buried
            CGPoint(x: 131, y: 89)     // front (cascade +11, -11)
        ]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.sorted(), [1, 2])
    }

    func testTodoSidebarWidthUnitInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("todoSidebarWidthUnit"), "todoSidebarWidthUnit missing from Defaults.array")
    }
}

class StackCycleTests: XCTestCase {

    // AX coordinates (top-left origin), a left half on a 1440x900 screen.
    private let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
    private let cascadeRange: CGFloat = 15
    private let sizeTolerance = StackBadgeGeometry.sizeTolerance

    private func indices(_ frames: [CGRect], anchor: CGRect? = nil) -> [Int] {
        StackBadgeGeometry.stackMembers(anchor: anchor ?? leftHalf, among: frames,
                                       cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: sizeTolerance)
    }

    func testIdenticalFramesStack() {
        XCTAssertEqual(indices([leftHalf, leftHalf, leftHalf]), [0, 1, 2])
    }

    func testCascadedFramesStackInBothYDirections() {
        let up = leftHalf.offsetBy(dx: 11, dy: -11)
        let down = leftHalf.offsetBy(dx: 11, dy: 11)
        XCTAssertEqual(indices([leftHalf, up, down]), [0, 1, 2])
    }

    func testFrameOutsideCascadeRangeIsExcluded() {
        XCTAssertEqual(indices([leftHalf, leftHalf.offsetBy(dx: 30, dy: 0)]), [0])
    }

    // A maximized window shares the left half's corner, but it is not in the
    // same area, so it is not cycled with the half.
    func testMaximizedWindowAtSameCornerIsExcluded() {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(indices([leftHalf, maximized]), [0])
    }

    func testQuarterAtSameCornerIsExcluded() {
        let topLeftQuarter = CGRect(x: 0, y: 25, width: 720, height: 437)
        XCTAssertEqual(indices([leftHalf, topLeftQuarter]), [0])
    }

    // Terminals snap to whole character cells, so they land a little short.
    func testTerminalSizedWindowIsIncluded() {
        let terminal = CGRect(x: 0, y: 25, width: 714, height: 862)
        XCTAssertEqual(indices([leftHalf, terminal]), [0, 1])
    }

    func testRightHalfIsExcluded() {
        XCTAssertEqual(indices([leftHalf, leftHalf.offsetBy(dx: 720, dy: 0)]), [0])
    }

    func testEmptyInput() {
        XCTAssertTrue(indices([]).isEmpty)
    }

    // With stacks not limited to one size, every window at the corner counts,
    // as it does for the hover list.
    func testAnySizeIncludesEveryWindowAtTheCorner() {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let topLeftQuarter = CGRect(x: 0, y: 25, width: 720, height: 437)
        let rightHalf = leftHalf.offsetBy(dx: 720, dy: 0)
        let frames = [leftHalf, maximized, topLeftQuarter.offsetBy(dx: 11, dy: -11), rightHalf]
        XCTAssertEqual(StackBadgeGeometry.stackMembers(anchor: leftHalf, among: frames,
                                                      cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: nil),
                       [0, 1, 2])
    }

    // Regression (review finding): with gaps on halves but not on maximize,
    // a maximized window's origin sits just up and left of a half's. Cycling
    // must pick the same stack the hover list shows, whichever is in front.
    func testAnySizeStackMatchesHoverList() throws {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let half = CGRect(x: 8, y: 33, width: 712, height: 859)
        let offsetHalf = half.offsetBy(dx: 11, dy: 0)

        func cycleStack(_ frames: [CGRect]) throws -> [Int] {
            let origins = frames.map { $0.origin }
            let anchor = try XCTUnwrap(StackBadgeGeometry.clusterAnchor(containing: 0, among: origins,
                                                                        cascadeRange: cascadeRange, tolerance: 4))
            return StackBadgeGeometry.stackMembers(anchor: CGRect(origin: origins[anchor], size: frames[0].size),
                                                  among: frames, cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: nil)
        }
        func hoverStack(_ frames: [CGRect]) -> [Int] {
            StackBadgeGeometry.stackIndices(among: frames.map { $0.origin }, cascadeRange: cascadeRange, tolerance: 4)
        }

        let halfInFront = [half, offsetHalf, maximized]
        XCTAssertEqual(try cycleStack(halfInFront), [0, 1])
        XCTAssertEqual(try cycleStack(halfInFront), hoverStack(halfInFront))

        let maximizedInFront = [maximized, half, offsetHalf]
        XCTAssertEqual(try cycleStack(maximizedInFront), [0, 1])
        XCTAssertEqual(try cycleStack(maximizedInFront), hoverStack(maximizedInFront))
    }

    // Regression (review finding): limited to one size, a denser group of
    // maximized windows at the corner must not claim the focused half and
    // leave it with nothing to cycle to.
    func testSameSizeStackIgnoresDenserGroupOfOtherSizes() throws {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let half = CGRect(x: 8, y: 33, width: 712, height: 859)
        let frames = [half, half.offsetBy(dx: 11, dy: 0), maximized, maximized]
        let anchor = try XCTUnwrap(StackBadgeGeometry.stackAnchor(for: 0, among: frames, cascadeRange: cascadeRange,
                                                                 tolerance: 4, sizeTolerance: sizeTolerance))
        XCTAssertEqual(StackBadgeGeometry.stackMembers(anchor: anchor, among: frames,
                                                      cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: sizeTolerance),
                       [0, 1])
    }

    // A window cascaded right of the stack's anchor still finds the anchor's
    // stack, as the hover list would.
    func testFocusedWindowRightOfAnchorFindsItsStack() throws {
        let behind = CGRect(x: 0, y: 25, width: 720, height: 875)
        let frames = [behind.offsetBy(dx: 11, dy: -11), behind]
        let anchor = try XCTUnwrap(StackBadgeGeometry.stackAnchor(for: 0, among: frames, cascadeRange: cascadeRange,
                                                                 tolerance: 4, sizeTolerance: sizeTolerance))
        XCTAssertEqual(anchor.origin, behind.origin)
        XCTAssertEqual(StackBadgeGeometry.stackMembers(anchor: anchor, among: frames,
                                                      cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: sizeTolerance),
                       [0, 1])
    }

    func testClusterAnchorPrefersDensestClusterThenEarliest() {
        let origins = [CGPoint(x: 8, y: 33), CGPoint(x: 19, y: 33), CGPoint(x: 0, y: 25), CGPoint(x: 30, y: 33)]
        // 0 is in {0, 1} (anchored at 0) and {2, 0} (anchored at 2): a tie,
        // so the earlier anchor wins.
        XCTAssertEqual(StackBadgeGeometry.clusterAnchor(containing: 0, among: origins, cascadeRange: 15, tolerance: 4), 0)
        // 3 is only reachable from 1's cluster {1, 3}, or on its own.
        XCTAssertEqual(StackBadgeGeometry.clusterAnchor(containing: 3, among: origins, cascadeRange: 15, tolerance: 4), 1)
        XCTAssertNil(StackBadgeGeometry.clusterAnchor(containing: 0, among: [], cascadeRange: 15, tolerance: 4))
    }

    // Regression (review finding): limited to one size, an unrelated window
    // near the corner must not become the list's size reference and hide
    // the stack the pointer is on.
    func testSameSizeListIgnoresNeighborNearTheCorner() {
        let neighbor = CGRect(x: 100, y: 105, width: 300, height: 200)
        let stacked = CGRect(x: 120, y: 100, width: 720, height: 875)
        let frames = [neighbor, stacked, stacked.offsetBy(dx: 11, dy: -11)]
        XCTAssertEqual(StackBadgeGeometry.sameSizeStackIndices(among: frames, cascadeRange: cascadeRange, tolerance: 4,
                                                               sizeTolerance: sizeTolerance),
                       [1, 2])
    }

    // Limited to one size, the list shows the stack of the window in front,
    // not a denser group of other sizes behind it.
    func testSameSizeListShowsTheFrontWindowsStack() {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let half = CGRect(x: 8, y: 33, width: 712, height: 859)
        let halfInFront = [half, half.offsetBy(dx: 11, dy: 0), maximized, maximized]
        XCTAssertEqual(StackBadgeGeometry.sameSizeStackIndices(among: halfInFront, cascadeRange: cascadeRange, tolerance: 4,
                                                               sizeTolerance: sizeTolerance),
                       [0, 1])
        let maximizedInFront = [maximized, maximized, half, half.offsetBy(dx: 11, dy: 0)]
        XCTAssertEqual(StackBadgeGeometry.sameSizeStackIndices(among: maximizedInFront, cascadeRange: cascadeRange, tolerance: 4,
                                                               sizeTolerance: sizeTolerance),
                       [0, 1])
        XCTAssertTrue(StackBadgeGeometry.sameSizeStackIndices(among: [], cascadeRange: cascadeRange, tolerance: 4,
                                                              sizeTolerance: sizeTolerance).isEmpty)
    }

    func testCascadeRangeMatchesBadgeFormula() {
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 1, tolerance: 4), 15)
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 3, tolerance: 4), 37)
        // Clamped to 1...5 cascade steps, and at least 1pt per step.
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 9, tolerance: 4), 59)
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 0, tolerance: 4), 15)
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 0, maxCascade: 1, tolerance: 4), 5)
    }

    // MARK: - Ring order

    func testSingleWindowHasNoTarget() {
        XCTAssertNil(StackCycleManager.target(stack: [1], from: 1, previousRing: [], forward: true))
        XCTAssertNil(StackCycleManager.target(stack: [], from: 1, previousRing: [], forward: true))
    }

    func testForwardFirstRaisesBackWindow() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [1, 2, 3], from: 1, previousRing: [], forward: true))
        XCTAssertEqual(result.target, 3)
        XCTAssertEqual(result.ring, [1, 2, 3])
    }

    func testBackwardFirstRaisesWindowBehindFront() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [1, 2, 3], from: 1, previousRing: [], forward: false))
        XCTAssertEqual(result.target, 2)
    }

    /// Simulates presses: each raise moves the target to the front of the
    /// z-order, which is what the next press sees.
    private func walkRing(start: [CGWindowID], presses: Int, forward: Bool) -> [CGWindowID] {
        var zOrder = start
        var ring = [CGWindowID]()
        var raised = [CGWindowID]()
        for _ in 0..<presses {
            guard let result = StackCycleManager.target(stack: zOrder, from: zOrder[0], previousRing: ring, forward: forward) else { break }
            ring = result.ring
            raised.append(result.target)
            zOrder.removeAll { $0 == result.target }
            zOrder.insert(result.target, at: 0)
        }
        return raised
    }

    func testForwardVisitsEveryWindowAndWraps() {
        XCTAssertEqual(walkRing(start: [1, 2, 3], presses: 6, forward: true), [3, 2, 1, 3, 2, 1])
    }

    func testBackwardVisitsEveryWindowAndWraps() {
        // Without the remembered ring this would flip between 1 and 2.
        XCTAssertEqual(walkRing(start: [1, 2, 3], presses: 6, forward: false), [2, 3, 1, 2, 3, 1])
    }

    func testTwoWindowStackToggles() {
        XCTAssertEqual(walkRing(start: [1, 2], presses: 3, forward: true), [2, 1, 2])
        XCTAssertEqual(walkRing(start: [1, 2], presses: 3, forward: false), [2, 1, 2])
    }

    func testChangingDirectionMidCycleStepsBack() throws {
        // Forward from [1, 2, 3] raised 3, so the z-order is [3, 1, 2].
        let next = try XCTUnwrap(StackCycleManager.target(stack: [3, 1, 2], from: 3, previousRing: [1, 2, 3], forward: false))
        XCTAssertEqual(next.target, 1)
    }

    func testRingIsRebuiltWhenStackMembershipChanges() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [4, 2, 1], from: 4, previousRing: [1, 2, 3], forward: true))
        XCTAssertEqual(result.ring, [4, 2, 1])
        XCTAssertEqual(result.target, 1)
    }

    func testRingIsKeptWhenStackMembershipIsUnchanged() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [2, 3, 1], from: 2, previousRing: [1, 2, 3], forward: true))
        XCTAssertEqual(result.ring, [1, 2, 3])
        XCTAssertEqual(result.target, 1)
    }

    func testFrontMissingFromStackHasNoTarget() {
        XCTAssertNil(StackCycleManager.target(stack: [1, 2], from: 9, previousRing: [], forward: true))
    }

    // MARK: - Sessions

    /// A fake window server: frames by id, front to back, plus the stack
    /// rule the manager uses.
    private struct Desk {
        var windows: [(id: CGWindowID, frame: CGRect)]
        var sizeTolerance: CGFloat? = StackBadgeGeometry.sizeTolerance

        func frame(_ id: CGWindowID) -> CGRect { windows.first { $0.id == id }!.frame }

        func stack(at anchor: CGRect) -> [CGWindowID] {
            StackBadgeGeometry.stackMembers(anchor: anchor, among: windows.map { $0.frame },
                                           cascadeRange: 15, tolerance: 4, sizeTolerance: sizeTolerance)
                .map { windows[$0].id }
        }

        mutating func raise(_ id: CGWindowID) {
            let window = windows.first { $0.id == id }!
            windows.removeAll { $0.id == id }
            windows.insert(window, at: 0)
        }

        var front: CGWindowID { windows[0].id }
    }

    private func press(_ desk: Desk, _ session: StackCycleManager.Session?, forward: Bool,
                       raiseInFlight: Bool = false) -> StackCycleManager.Session? {
        guard let anchor = StackBadgeGeometry.stackAnchor(for: 0, among: desk.windows.map { $0.frame },
                                                         cascadeRange: 15, tolerance: 4, sizeTolerance: desk.sizeTolerance)
        else { return nil }
        return StackCycleManager.nextSession(focused: desk.front, freshAnchor: anchor,
                                             previous: session, forward: forward,
                                             raiseInFlight: raiseInFlight, stackFor: desk.stack(at:))
    }

    /// Presses that each land before the next one.
    private func walk(_ desk: Desk, presses: Int, forward: Bool) -> [CGWindowID] {
        var desk = desk
        var session: StackCycleManager.Session?
        var raised = [CGWindowID]()
        for _ in 0..<presses {
            guard let next = press(desk, session, forward: forward) else { break }
            session = next
            raised.append(next.cursor)
            desk.raise(next.cursor)
        }
        return raised
    }

    private func window(_ id: CGWindowID, width: CGFloat) -> (id: CGWindowID, frame: CGRect) {
        (id, CGRect(x: 0, y: 25, width: width, height: 875))
    }

    // Regression (review finding): B is within tolerance of both A and C,
    // but A and C are not of each other. Measuring the stack from each newly
    // raised window dropped C and toggled between A and B forever.
    func testStackAnchorIsFixedForTheSession() {
        let desk = Desk(windows: [window(2, width: 720), window(1, width: 700), window(3, width: 740)])
        XCTAssertEqual(Set(walk(desk, presses: 6, forward: false)), [1, 2, 3])
        XCTAssertEqual(Set(walk(desk, presses: 6, forward: true)), [1, 2, 3])
    }

    func testSessionWalkMatchesRingOrder() {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        XCTAssertEqual(walk(desk, presses: 6, forward: true), [3, 2, 1, 3, 2, 1])
        XCTAssertEqual(walk(desk, presses: 6, forward: false), [2, 3, 1, 2, 3, 1])
    }

    // Regression (review finding): a second press made before the first
    // raise lands still sees the old front window, and must advance past the
    // first target instead of choosing it again.
    func testPressBeforeRaiseLandsStillAdvances() throws {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let first = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(first.cursor, 3)
        let second = try XCTUnwrap(press(desk, first, forward: true, raiseInFlight: true))
        XCTAssertEqual(second.cursor, 2)
    }

    // Two quick presses on a two-window stack come back to the start: while
    // the first raise is in flight, the stale front window is not skipped.
    func testDoublePressOnTwoWindowStackReturnsToStart() throws {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720)])
        let first = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(first.cursor, 2)
        let second = try XCTUnwrap(press(desk, first, forward: true, raiseInFlight: true))
        XCTAssertEqual(second.cursor, 1)
    }

    // A window that never comes forward is stepped past, not retried forever.
    func testRefusedRaiseIsSteppedPast() throws {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        var session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        // Window 2 refused to come forward; 1 is still in front.
        session = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(session.cursor, 3)
    }

    // Regression (review finding): with four windows, the first of two
    // queued raises landing put an intermediate window in front, which read
    // as the user focusing it and restarted the walk on the same target.
    func testPartialRaiseCompletionStillAdvances() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720), window(4, width: 720)])
        let first = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(first.cursor, 4)
        let second = try XCTUnwrap(press(desk, first, forward: true, raiseInFlight: true))
        XCTAssertEqual(second.cursor, 3)
        desk.raise(4)                               // only the first raise has landed
        let third = try XCTUnwrap(press(desk, second, forward: true, raiseInFlight: true))
        XCTAssertEqual(third.cursor, 2)
    }

    // Focus moving between the stack's own windows, by a raise landing or by
    // hand, keeps the walk going from where the presses left it.
    func testFocusWithinStackKeepsWalking() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        desk.raise(2)
        desk.raise(1)                               // user clicks 1
        let next = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(next.cursor, 3)
        XCTAssertEqual(next.ring, [1, 2, 3])
    }

    // Regression (review finding): when the walk reaches the window the user
    // already brought forward by hand, it steps past it rather than
    // re-raising it, which would look like the press did nothing.
    func testWalkSkipsWindowAlreadyInFront() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        desk.raise(2)
        desk.raise(3)                               // user clicks 3, next in the walk
        let next = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(next.cursor, 1)
    }

    // Focusing a window outside the stack ends the session, so the next
    // press starts from that window's own stack.
    func testFocusingAnotherStackStartsNewSession() throws {
        let rightHalf = { (id: CGWindowID) in (id: id, frame: CGRect(x: 720, y: 25, width: 720, height: 875)) }
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), rightHalf(3), rightHalf(4)])
        let left = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(left.cursor, 2)
        desk.raise(4)                               // user clicks the right half
        let right = try XCTUnwrap(press(desk, left, forward: true))
        XCTAssertEqual(right.ring, [4, 3])
        XCTAssertEqual(right.cursor, 3)
    }

    func testClosedTargetCarriesOnFromFocusedWindow() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        desk.windows.removeAll { $0.id == 2 }       // closed before it came forward
        let next = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(next.cursor, 3)
    }

    func testAnySizeCyclesMaximizedWindowWithHalf() {
        let desk = Desk(windows: [window(1, width: 1440), window(2, width: 720)], sizeTolerance: nil)
        XCTAssertEqual(walk(desk, presses: 4, forward: true), [2, 1, 2, 1])
    }

    func testNoSessionWithoutAStack() {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 1440)])
        XCTAssertNil(press(desk, nil, forward: true))
    }

    func testMovedFocusedWindowStartsNewSession() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 1440), window(4, width: 1440)])
        let session = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(session.cursor, 2)
        desk.raise(2)
        // Window 2 is maximized: it now belongs to the maximized stack.
        desk.windows[0] = window(2, width: 1440)
        let next = try XCTUnwrap(press(desk, session, forward: true))
        XCTAssertEqual(Set(next.ring), [2, 3, 4])
    }

    // MARK: - Action wiring

    func testActionsAreActiveAndReachableByUrlName() {
        XCTAssertTrue(WindowAction.active.contains(.cycleStackedWindows))
        XCTAssertTrue(WindowAction.active.contains(.cycleStackedWindowsBackward))
        XCTAssertEqual(WindowAction.cycleStackedWindows.name, "cycleStackedWindows")
        XCTAssertEqual(WindowAction.cycleStackedWindowsBackward.name, "cycleStackedWindowsBackward")
    }

    func testActionsHaveSettingsTitlesButStayOutOfMenu() {
        for action in [WindowAction.cycleStackedWindows, .cycleStackedWindowsBackward] {
            XCTAssertNotNil(action.displayName)
            XCTAssertTrue(action.excludedFromMenu)
            XCTAssertFalse(action.positionCycles)
            XCTAssertFalse(action.overlapOffsetApplies)
            XCTAssertFalse(action.isDragSnappable)
        }
    }
}

/// The cascade math itself. Asserting the resulting rect matters: an earlier
/// version of this feature was certified by a test that only checked an
/// eligibility flag, while the offset it enabled was a no-op for anyone
/// running the default of no gaps.
class OverlapOffsetGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let offset: CGFloat = 11

    private func cascade(_ rect: CGRect, occupied: [CGPoint], maxCascade: Int = 1) -> CGRect {
        OverlapOffsetGeometry.cascadedRect(rect,
                                           occupiedTopLefts: occupied,
                                           screenFrame: screen,
                                           offset: offset,
                                           maxCascade: maxCascade)
    }

    /// A maximized window with no gaps fills the visible frame, so there is
    /// nowhere to shift it - and the caller skips the window scan entirely.
    func testMaximizedWithoutGapsCannotOffset() {
        let maximized = screen
        XCTAssertFalse(OverlapOffsetGeometry.canOffset(maximized, in: screen, by: offset))
        XCTAssertEqual(cascade(maximized, occupied: [OverlapOffsetGeometry.topLeft(of: maximized)]),
                       maximized)
    }

    /// Gaps larger than the offset leave room, so maximized windows cascade.
    func testMaximizedWithGapsOffsets() {
        let maximized = CGRect(x: 22, y: 22, width: 956, height: 756)
        XCTAssertTrue(OverlapOffsetGeometry.canOffset(maximized, in: screen, by: offset))
        XCTAssertEqual(cascade(maximized, occupied: [OverlapOffsetGeometry.topLeft(of: maximized)]),
                       CGRect(x: 33, y: 33, width: 956, height: 756))
    }

    /// Gaps smaller than the offset must not shift the window part way: it
    /// would end up flush against the far edges, deleting the gaps there.
    func testGapsSmallerThanOffsetDoNotOffset() {
        let maximized = CGRect(x: 5, y: 5, width: 990, height: 790)
        XCTAssertFalse(OverlapOffsetGeometry.canOffset(maximized, in: screen, by: offset))
        XCTAssertEqual(cascade(maximized, occupied: [OverlapOffsetGeometry.topLeft(of: maximized)]),
                       maximized)
    }

    /// A half with no gaps has room across but not up, and still offsets on
    /// the axis that fits - the behavior shipped in v0.96.
    func testHalfOffsetsOnTheAxisWithRoom() {
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800)
        XCTAssertEqual(cascade(leftHalf, occupied: [OverlapOffsetGeometry.topLeft(of: leftHalf)]),
                       CGRect(x: 11, y: 0, width: 500, height: 800))
    }

    func testNoOverlapLeavesTheRectAlone() {
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800)
        XCTAssertEqual(cascade(leftHalf, occupied: [CGPoint(x: 500, y: 800)]), leftHalf)
    }

    func testCascadeStopsAtMaxCascade() {
        let quarter = CGRect(x: 0, y: 0, width: 400, height: 400)
        let occupied = [CGPoint(x: 0, y: 400), CGPoint(x: 11, y: 411), CGPoint(x: 22, y: 422)]
        XCTAssertEqual(cascade(quarter, occupied: occupied, maxCascade: 1).origin,
                       CGPoint(x: 11, y: 11))
        XCTAssertEqual(cascade(quarter, occupied: occupied, maxCascade: 3).origin,
                       CGPoint(x: 33, y: 33))
    }

    /// Matching is by top-left corner, so a smaller window landing on a larger
    /// one at the same corner counts as an overlap - an eighth arriving on a
    /// quarter. Both sit against the top of the screen here, so the window
    /// offsets across but not up.
    func testMatchesMixedSizesAtTheSameCorner() {
        let eighth = CGRect(x: 0, y: 600, width: 250, height: 200)
        let quarterTopLeft = OverlapOffsetGeometry.topLeft(of: CGRect(x: 0, y: 400, width: 500, height: 400))
        XCTAssertEqual(quarterTopLeft, OverlapOffsetGeometry.topLeft(of: eighth))
        XCTAssertEqual(cascade(eighth, occupied: [quarterTopLeft]),
                       CGRect(x: 11, y: 600, width: 250, height: 200))
    }

    func testCoversScreen() {
        XCTAssertTrue(OverlapOffsetGeometry.coversScreen(screen, screenFrame: screen))
        XCTAssertTrue(OverlapOffsetGeometry.coversScreen(CGRect(x: 22, y: 22, width: 956, height: 756),
                                                         screenFrame: screen))
        XCTAssertFalse(OverlapOffsetGeometry.coversScreen(CGRect(x: 0, y: 0, width: 500, height: 800),
                                                          screenFrame: screen))
    }
}

/// Which actions are eligible for the overlap offset. `positionCycles` alone
/// excluded maximize, so two maximized windows landed exactly on top of each
/// other. Eligibility is only half of it - whether an eligible window actually
/// moves is covered by OverlapOffsetGeometryTests.
class OverlapOffsetEligibilityTests: XCTestCase {

    func testMaximizeGetsTheOffset() {
        XCTAssertTrue(WindowAction.maximize.overlapOffsetApplies)
    }

    func testGridPositionsGetTheOffset() {
        for action in [WindowAction.leftHalf, .topLeft, .topLeftSixth,
                       .topLeftNinth, .topLeftEighth, .topLeftTwelfth, .topLeftSixteenth] {
            XCTAssertTrue(action.overlapOffsetApplies, "\(action) should get the overlap offset")
        }
    }

    /// Actions that move or resize in place have no "landed on top of
    /// something" notion, so offsetting them would just displace the window.
    func testMovesAndResizesDoNotGetTheOffset() {
        for action in [WindowAction.center, .restore, .moveLeft, .moveRight, .moveUp, .moveDown,
                       .larger, .smaller, .nextDisplay, .previousDisplay,
                       .almostMaximize, .maximizeHeight, .tileAll, .cascadeAll] {
            XCTAssertFalse(action.overlapOffsetApplies, "\(action) should not get the overlap offset")
        }
    }
}

/// The stacked-window list is driven by an event tap, so it decides which
/// keystrokes to take from the app underneath. Taking the wrong ones would
/// break typing system-wide while the list is open.
class StackBadgeKeyHandlingTests: XCTestCase {

    /// The flags macOS actually puts on an arrow keystroke. Every arrow event
    /// carries them, so a test that passes an empty modifier set is asserting
    /// against an event the system never delivers - which is exactly how a
    /// guard that rejected .function shipped with the suite green.
    private static let arrowFlags: NSEvent.ModifierFlags = [.function, .numericPad]

    private func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> StackBadgeManager.NavigationKey? {
        StackBadgeManager.navigationKey(forKeyCode: code, modifiers: modifiers)
    }

    func testNavigationKeysAreClaimed() {
        XCTAssertEqual(key(UInt16(kVK_UpArrow), Self.arrowFlags), .up)
        XCTAssertEqual(key(UInt16(kVK_DownArrow), Self.arrowFlags), .down)
        XCTAssertEqual(key(UInt16(kVK_Return)), .commit)
        XCTAssertEqual(key(UInt16(kVK_ANSI_KeypadEnter), .numericPad), .commit)
        XCTAssertEqual(key(UInt16(kVK_Escape)), .escape)
    }

    /// Caps lock is not something the user is holding for this keystroke, and
    /// a window list that stops navigating because caps lock is on would be
    /// its own bug report.
    func testCapsLockStillNavigates() {
        XCTAssertEqual(key(UInt16(kVK_UpArrow), Self.arrowFlags.union(.capsLock)), .up)
    }

    func testOrdinaryKeysArePassedThrough() {
        for code in [kVK_ANSI_A, kVK_ANSI_Q, kVK_Tab, kVK_Space, kVK_Delete, kVK_PageUp, kVK_Home] {
            XCTAssertNil(key(UInt16(code)), "keyCode \(code) must reach the app underneath")
        }
        for code in [kVK_LeftArrow, kVK_RightArrow] {
            XCTAssertNil(key(UInt16(code), Self.arrowFlags),
                         "keyCode \(code) must reach the app underneath")
        }
    }

    /// A held modifier means the keystroke belongs to the frontmost app. Shift
    /// is included deliberately: shift-return inserts a newline in chat apps
    /// and shift-arrow extends a selection, so claiming those would break
    /// ordinary typing whenever the list happened to be open. The arrow cases
    /// carry the flags macOS sends, so the modifier under test is the only
    /// difference from a keystroke that must be claimed.
    func testModifiedKeysArePassedThrough() {
        for modifier in [NSEvent.ModifierFlags.command, .option, .control, .shift] {
            for code in [kVK_UpArrow, kVK_DownArrow] {
                XCTAssertNil(key(UInt16(code), Self.arrowFlags.union(modifier)),
                             "arrow \(code) with \(modifier) must reach the app underneath")
            }
            for code in [kVK_Return, kVK_Escape] {
                XCTAssertNil(key(UInt16(code), modifier),
                             "keyCode \(code) with \(modifier) must reach the app underneath")
            }
        }
        XCTAssertNil(key(UInt16(kVK_UpArrow), Self.arrowFlags.union([.command, .option])))
        XCTAssertNil(key(UInt16(kVK_Return), [.shift]))
    }

    func testSelectionClampsAtBothEnds() {
        XCTAssertEqual(StackBadgeManager.selection(from: 0, movedBy: -1, count: 4), 0)
        XCTAssertEqual(StackBadgeManager.selection(from: 3, movedBy: 1, count: 4), 3)
        XCTAssertEqual(StackBadgeManager.selection(from: 1, movedBy: 1, count: 4), 2)
        XCTAssertEqual(StackBadgeManager.selection(from: 1, movedBy: -1, count: 4), 0)
    }

    func testSelectionWithNoRowsIsNil() {
        XCTAssertNil(StackBadgeManager.selection(from: 0, movedBy: 1, count: 0))
    }

    /// Rows that would be clipped are never built, so the arrow keys can't
    /// select - and Return can't raise - a window with no visible row.
    func testRowsThatFitIsBoundedByTheScreenBottom() {
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 500, above: 0), 22)
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 60, above: 0), 2)
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 10, above: 0), 0)
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 0, above: 100), 0)
    }
}

/// Which windows at a shared corner count as one stack. A window covering the
/// screen shares its corner with every half and corner placement, so it can
/// only join a stack, never create one - otherwise an everyday layout (one
/// maximized window, one tiled to the left half) reads as a stack of two.
/// Size plays no part in stack membership. A window pegged to the corner is in
/// the stack whether it is maximized or a sixteenth - and a maximized window
/// sitting on a smaller one is the case where the smaller window cannot be
/// seen any other way, which is what the list exists to reveal.
///
/// The list briefly excluded screen-covering windows, borrowed from the
/// overlap offset where the exclusion is necessary (a maximized window shares
/// its origin with every placement and would otherwise shift them all, #1766).
/// The list moves nothing, so it never needed it, and the exclusion made a
/// maximized window over a half-screen window show no list at all.
class StackBadgeSizeAgnosticTests: XCTestCase {

    private let corner = CGPoint(x: 0, y: 0)
    private let cascaded = CGPoint(x: 11, y: -11)

    private func stack(_ origins: [CGPoint]) -> [Int] {
        StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
    }

    /// The reported case: one maximized window over one half-screen window,
    /// both pegged to the same corner, showed nothing at all.
    func testMaximizedOverTiledIsAStack() {
        XCTAssertEqual(stack([corner, corner]).sorted(), [0, 1])
    }

    /// The maximized windows carry the overlap offset, so they sit a cascade
    /// step forward of the tiled window they hide.
    func testOffsetMaximizedWindowsStillIncludeTheTiledOneBeneath() {
        XCTAssertEqual(stack([cascaded, cascaded, corner]).sorted(), [0, 1, 2])
    }

    func testSeveralMaximizedWindowsAreAStack() {
        XCTAssertEqual(stack([corner, cascaded]).count, 2)
    }

    func testTiledStackIsUnaffected() {
        XCTAssertEqual(stack([corner, cascaded]).count, 2)
    }

    /// This returns the densest cluster, which for a single window is that
    /// window; the caller is what requires two before showing anything.
    func testLoneWindowIsItsOwnClusterAndTheCallerRejectsIt() {
        XCTAssertEqual(stack([corner]), [0])
    }

    func testWindowAtAnotherCornerIsNotInTheCluster() {
        XCTAssertEqual(stack([corner, CGPoint(x: 900, y: 0)]).count, 1)
    }
}

class ChangeSizeCalculationTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    private let issueWindowRect = CGRect(x: 1895, y: 0, width: 665, height: 1415)
    private var minimumWindowWidth: Double = 0
    private var minimumWindowHeight: Double = 0
    private var sizeOffset: Float = 0
    private var gapSize: Float = 0
    private var curtainChangeSize: Bool?
    private var smallerShrinksMaximizedHeight = false
    private var storedMinimumWindowWidth: Any?
    private var storedMinimumWindowHeight: Any?

    override func setUp() {
        super.setUp()

        minimumWindowWidth = Defaults.minimumWindowWidth.value
        minimumWindowHeight = Defaults.minimumWindowHeight.value
        sizeOffset = Defaults.sizeOffset.value
        gapSize = Defaults.gapSize.value
        curtainChangeSize = Defaults.curtainChangeSize.enabled
        smallerShrinksMaximizedHeight = Defaults.smallerShrinksMaximizedHeight.enabled
        storedMinimumWindowWidth = UserDefaults.standard.object(forKey: Defaults.minimumWindowWidth.key)
        storedMinimumWindowHeight = UserDefaults.standard.object(forKey: Defaults.minimumWindowHeight.key)

        Defaults.minimumWindowWidth.value = 0
        Defaults.minimumWindowHeight.value = 0
        Defaults.sizeOffset.value = 30
        Defaults.gapSize.value = 0
        Defaults.curtainChangeSize.enabled = true
        Defaults.smallerShrinksMaximizedHeight.enabled = false
    }

    override func tearDown() {
        Defaults.minimumWindowWidth.value = minimumWindowWidth
        Defaults.minimumWindowHeight.value = minimumWindowHeight
        restoreStoredValue(storedMinimumWindowWidth, for: Defaults.minimumWindowWidth.key)
        restoreStoredValue(storedMinimumWindowHeight, for: Defaults.minimumWindowHeight.key)
        Defaults.sizeOffset.value = sizeOffset
        Defaults.gapSize.value = gapSize
        Defaults.curtainChangeSize.enabled = curtainChangeSize
        Defaults.smallerShrinksMaximizedHeight.enabled = smallerShrinksMaximizedHeight

        super.tearDown()
    }

    func testExplicitZeroDisablesScreenFractionMinimum() {
        XCTAssertEqual(smallerResult(for: issueWindowRect),
                       CGRect(x: 1925, y: 0, width: 635, height: 1415))
    }

    func testDoubleDefaultDistinguishesAbsentFromExplicitZero() {
        let key = "ChangeSizeCalculationTests.minimumWindowWidth"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let absentPreference = DoubleDefault(key: key, defaultValue: 0.25)
        XCTAssertEqual(absentPreference.value, 0.25)
        XCTAssertEqual(absentPreference.toCodable().double, 0.25)
        XCTAssertNil(absentPreference.toCodable().float)

        absentPreference.value = 0
        let explicitZeroPreference = DoubleDefault(key: key, defaultValue: 0.25)
        XCTAssertEqual(explicitZeroPreference.value, 0)
        XCTAssertEqual(explicitZeroPreference.toCodable().double, 0)
        XCTAssertNil(explicitZeroPreference.toCodable().float)
    }

    func testDoubleDefaultLoadsLegacyFloatAndNewDoubleConfigValues() throws {
        let key = "ChangeSizeCalculationTests.minimumWindowWidthConfig"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let preference = DoubleDefault(key: key, defaultValue: 0.25)
        let legacyZero = try JSONDecoder().decode(
            CodableDefault.self,
            from: Data(#"{"float":0}"#.utf8)
        )
        let legacyFraction = try JSONDecoder().decode(
            CodableDefault.self,
            from: Data(#"{"float":0.01}"#.utf8)
        )
        let currentZero = try JSONDecoder().decode(
            CodableDefault.self,
            from: Data(#"{"double":0}"#.utf8)
        )
        let currentFraction = try JSONDecoder().decode(
            CodableDefault.self,
            from: Data(#"{"double":0.123456789012345}"#.utf8)
        )

        preference.load(from: legacyZero)
        XCTAssertEqual(preference.value, 0.25)

        preference.load(from: legacyFraction)
        XCTAssertEqual(preference.value, Double(Float(0.01)))

        preference.load(from: currentFraction)
        XCTAssertEqual(preference.value, 0.123456789012345)

        preference.load(from: currentZero)
        XCTAssertEqual(preference.value, 0)
    }

    func testSmallerCanReachExactConfiguredMinimum() {
        Defaults.minimumWindowWidth.value = 0.25
        let windowRect = CGRect(x: 1890, y: 0, width: 670, height: 1415)

        XCTAssertEqual(smallerResult(for: windowRect),
                       CGRect(x: 1920, y: 0, width: 640, height: 1415))
    }

    func testSmallerHonorsConfiguredScreenFractionMinimum() {
        Defaults.minimumWindowWidth.value = 0.25

        XCTAssertEqual(smallerResult(for: issueWindowRect), issueWindowRect)
    }

    func testSmallerKeepsHeightOfFullHeightWindowByDefault() {
        // Default behavior (see #1737): the combined `.smaller` command only shrinks the width of
        // a window pinned to the top and bottom screen edges. The height shrinks only under the
        // height-only `.smallerHeight` command (b97a353, fixes #1645) or when the
        // smallerShrinksMaximizedHeight terminal command config is enabled.
        let fullHeightHalf = CGRect(x: 0, y: 0, width: 1280, height: 1415)

        XCTAssertEqual(smallerResult(for: fullHeightHalf),
                       CGRect(x: 0, y: 0, width: 1250, height: 1415))
    }

    func testSmallerShrinksHeightOfFullHeightWindow() {
        // Regression for #1737, opt-in via the terminal command config: a vertically-maximized
        // (Half / full-height) window shrinks in BOTH dimensions under the combined `.smaller`
        // command. Mirrors the `.smallerHeight` exception added in b97a353 (fixes #1645),
        // extended to `.smaller`.
        Defaults.smallerShrinksMaximizedHeight.enabled = true
        let fullHeightHalf = CGRect(x: 0, y: 0, width: 1280, height: 1415)

        XCTAssertEqual(smallerResult(for: fullHeightHalf),
                       CGRect(x: 0, y: 15, width: 1250, height: 1385))
    }

    func testSmallConfiguredScreenFractionAllowsIssueRegressionStep() {
        Defaults.minimumWindowWidth.value = 0.01

        XCTAssertEqual(smallerResult(for: issueWindowRect),
                       CGRect(x: 1925, y: 0, width: 635, height: 1415))
    }

    func testExplicitZeroStillRejectsNonpositiveSize() {
        let narrowWindow = CGRect(x: 100, y: 100, width: 20, height: 100)

        XCTAssertEqual(smallerResult(for: narrowWindow), narrowWindow)
    }

    private func smallerResult(for windowRect: CGRect) -> CGRect {
        ChangeSizeCalculation().calculateRect(
            RectCalculationParameters(window: Window(id: 1, rect: windowRect),
                                      visibleFrameOfScreen: visibleFrame,
                                      action: .smaller,
                                      lastAction: nil)
        ).rect
    }

    private func restoreStoredValue(_ value: Any?, for key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

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

class CooperativeCornerResizeTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)
    private let minimumSize = CGSize(width: 100, height: 100)
    private let tolerance: CGFloat = 8

    func testBottomLeftVerticalExpansionShrinksTopLeftNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 800, height: 600))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 600, width: 800, height: 300))
        XCTAssertEqual(focusedNew.maxY, adjustments[0].newFrame.minY, accuracy: 0.001)
    }

    func testBottomLeftVerticalExpansionKeepsFullTwoThirdsWhenFeasible() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 800, height: 600))

        guard let plan = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: focusedNew)
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 600, width: 800, height: 300))
    }

    func testBottomLeftVerticalExpansionIsReducedByCooperatingMinimumHeight() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2,
                                                        frame: CGRect(x: 0, y: 300, width: 800, height: 600),
                                                        minimumSize: CGSize(width: 100, height: 400))

        guard let plan = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 800, height: 500))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 500, width: 800, height: 400))
        XCTAssertTrue(plan.debugLog.contains { $0.contains("reduced requested movement") })
    }

    func testBottomLeftVerticalExpansionUsesVisibleFrameInsteadOfRawScreenFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1200, height: 840)
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2,
                                                        frame: CGRect(x: 0, y: 300, width: 800, height: 600),
                                                        minimumSize: CGSize(width: 100, height: 300))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         screenFrame: visibleFrame,
                                         candidates: [topLeft],
                                         axis: .vertical) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 800, height: 540))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 540, width: 800, height: 300))
        XCTAssertLessThanOrEqual(plan.adjustments[0].newFrame.maxY, visibleFrame.maxY)
    }

    func testVerticalExpansionRoundsSharedEdgeAtOneThirdTwoThirdsBoundary() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1200, height: 1000)
        let oneThird = screenFrame.height / 3.0
        let twoThirds = screenFrame.height * 2.0 / 3.0
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: oneThird)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: twoThirds)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: oneThird, width: 800, height: twoThirds))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         screenFrame: screenFrame,
                                         candidates: [topLeft],
                                         axis: .vertical) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 800, height: 667))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 667, width: 800, height: 333))
        XCTAssertEqual(plan.focusedFrame.maxY, plan.adjustments[0].newFrame.minY, accuracy: 0.001)
    }

    func testAffectedWindowsReceiveOneFinalFrameEach() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 400, height: 900)
        let bottomLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        let bottomRight = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 800, y: 0, width: 400, height: 300))
        let topRight = CooperativeCornerResize.Candidate(id: 4, frame: CGRect(x: 800, y: 300, width: 400, height: 600))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [bottomLeft, bottomRight, topRight],
                                         axis: .horizontal) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        let adjustedIds = plan.adjustments.map(\.id)
        XCTAssertEqual(adjustedIds.count, Set(adjustedIds).count)
        XCTAssertEqual(adjustedIds.sorted(), [2, 3, 4])
    }

    func testUnrelatedWindowsAreNotMoved() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 800, height: 600))
        let unrelated = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 850, y: 50, width: 250, height: 250))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft, unrelated],
                                         axis: .vertical) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        XCTAssertEqual(plan.adjustments.map(\.id), [topLeft.id])
    }

    func testNearGridNeighborIsDetectedAndNormalized() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let terminalLikeTop = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 5, y: 304, width: 790, height: 596))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [terminalLikeTop],
                                         axis: .vertical,
                                         tolerance: 20) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 600, width: 800, height: 300))
    }

    func testInitialCornerPushPlansAgainstRequestedSharedBoundary() {
        let focusedOld = CGRect(x: 225, y: 120, width: 420, height: 360)
        let focusedNew = CGRect(x: 0, y: 0, width: 600, height: 450)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 450, width: 600, height: 450))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew,
                                         actionDescription: "initial corner/side cooperative placement") else {
            XCTFail("Expected initial cooperative placement plan")
            return
        }

        assertRect(plan.focusedFrame, equals: focusedNew)
        assertRect(plan.adjustments[0].newFrame, equals: topLeft.frame)
        XCTAssertFalse(CooperativeCornerResize.frameNeedsApplication(currentFrame: topLeft.frame,
                                                                     solvedFrame: plan.adjustments[0].newFrame,
                                                                     screenFrame: screenFrame,
                                                                     layoutTolerance: 4))
        XCTAssertTrue(plan.debugLog.contains { $0.contains("initial corner/side cooperative placement") })
    }

    func testInitialCornerPushWithOversizedFocusedMinimumMovesBoundaryBeforeOverlap() {
        let focusedOld = CGRect(x: 225, y: 120, width: 420, height: 360)
        let focusedNew = CGRect(x: 0, y: 0, width: 600, height: 450)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 450, width: 600, height: 450))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         focusedMinimumSize: CGSize(width: 100, height: 520),
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected oversized focused cooperative placement plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 600, height: 520))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 520, width: 600, height: 380))
        XCTAssertEqual(plan.focusedFrame.maxY, plan.adjustments[0].newFrame.minY, accuracy: 0.001)
        XCTAssertLessThanOrEqual(plan.adjustments[0].newFrame.maxY, screenFrame.maxY)
    }

    func testInitialSidePushWithOversizedNeighborGivesFocusedWindowPartialTarget() {
        let focusedOld = CGRect(x: 180, y: 80, width: 480, height: 640)
        let focusedNew = CGRect(x: 0, y: 0, width: 600, height: 900)
        let rightSide = CooperativeCornerResize.Candidate(id: 2,
                                                          frame: CGRect(x: 600, y: 0, width: 600, height: 900),
                                                          minimumSize: CGSize(width: 700, height: 100))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [rightSide],
                                         axis: .horizontal,
                                         movedEdgeOverride: .right,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected initial side cooperative placement plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 500, height: 900))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 500, y: 0, width: 700, height: 900))
        XCTAssertEqual(plan.focusedFrame.maxX, plan.adjustments[0].newFrame.minX, accuracy: 0.001)
    }

    func testInitialCornerPushWithOversizedFocusedWindowAdjustsBothAxesWithoutSpill() {
        let focusedOld = CGRect(x: 250, y: 160, width: 320, height: 260)
        let focusedNew = CGRect(x: 0, y: 0, width: 400, height: 450)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 450, width: 400, height: 450))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         focusedMinimumSize: CGSize(width: 700, height: 520),
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected both-axis oversized cooperative placement plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 700, height: 520))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 520, width: 400, height: 380))
        XCTAssertLessThanOrEqual(plan.focusedFrame.maxX, screenFrame.maxX)
        XCTAssertLessThanOrEqual(plan.adjustments[0].newFrame.maxY, screenFrame.maxY)
        XCTAssertEqual(plan.focusedFrame.maxY, plan.adjustments[0].newFrame.minY, accuracy: 0.001)
        XCTAssertFalse(plan.focusedFrame.intersects(plan.adjustments[0].newFrame))
    }

    func testExistingCorrectInitialLayoutIsNoOpForAllSolvedFrames() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 600)
        let focusedNew = focusedOld
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 600, width: 800, height: 300))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected cooperative no-op plan")
            return
        }

        XCTAssertFalse(CooperativeCornerResize.frameNeedsApplication(currentFrame: focusedOld,
                                                                     solvedFrame: plan.focusedFrame,
                                                                     screenFrame: screenFrame,
                                                                     layoutTolerance: 4))
        XCTAssertFalse(CooperativeCornerResize.frameNeedsApplication(currentFrame: topLeft.frame,
                                                                     solvedFrame: plan.adjustments[0].newFrame,
                                                                     screenFrame: screenFrame,
                                                                     layoutTolerance: 4))
    }

    func testInitialCornerPlacementPreservesExplicitlyShrunkOccupiedCell() {
        let focusedOld = CGRect(x: 225, y: 120, width: 420, height: 360)
        let focusedDefault = CGRect(x: 0, y: 300, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 600, width: 800, height: 300))
        let bottomLeft = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let focusedNew = CooperativeCornerResize.focusedFramePreservingOccupiedCell(requestedFocusedFrame: focusedDefault,
                                                                                    screenFrame: screenFrame,
                                                                                    candidates: [topLeft, bottomLeft],
                                                                                    axis: .vertical,
                                                                                    movedEdge: .bottom,
                                                                                    tolerance: tolerance)

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft, bottomLeft],
                                         axis: .vertical,
                                         captureTolerance: 72,
                                         movedEdgeOverride: .bottom,
                                         candidateDiscoveryFrame: focusedNew,
                                         actionDescription: "initial corner/side cooperative placement") else {
            XCTFail("Expected initial cooperative placement plan")
            return
        }

        assertRect(focusedNew, equals: topLeft.frame)
        assertRect(plan.focusedFrame, equals: topLeft.frame)
        assertRect(plan.adjustments[0].newFrame, equals: topLeft.frame)
        assertRect(plan.adjustments[1].newFrame, equals: bottomLeft.frame)
    }

    func testInitialCornerPlacementUsesLargerRealizedBoundaryBeforePlanning() {
        let focusedOld = CGRect(x: 225, y: 120, width: 420, height: 360)
        let focusedDefault = CGRect(x: 400, y: 600, width: 800, height: 300)
        let constrainedTopRight = CooperativeCornerResize.Candidate(id: 2,
                                                                    frame: CGRect(x: 400, y: 540, width: 800, height: 360))
        let focusedNew = CooperativeCornerResize.focusedFrameResolvingRealizedCornerBoundary(requestedFocusedFrame: focusedDefault,
                                                                                             screenFrame: screenFrame,
                                                                                             candidates: [constrainedTopRight],
                                                                                             axis: .vertical,
                                                                                             movedEdge: .bottom,
                                                                                             tolerance: tolerance)

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [constrainedTopRight],
                                         axis: .vertical,
                                         movedEdgeOverride: .bottom,
                                         candidateDiscoveryFrame: focusedNew,
                                         actionDescription: "initial corner/side cooperative placement") else {
            XCTFail("Expected initial cooperative placement plan")
            return
        }

        assertRect(focusedNew, equals: constrainedTopRight.frame)
        assertRect(plan.focusedFrame, equals: constrainedTopRight.frame)
        assertRect(plan.adjustments[0].newFrame, equals: constrainedTopRight.frame)
        XCTAssertFalse(CooperativeCornerResize.frameNeedsApplication(currentFrame: constrainedTopRight.frame,
                                                                     solvedFrame: plan.adjustments[0].newFrame,
                                                                     screenFrame: screenFrame,
                                                                     layoutTolerance: 4))
    }

    func testInitialCornerPlacementUsesObservedCyclicBoundaryBeforePlanning() {
        let focusedDefault = CGRect(x: 400, y: 600, width: 800, height: 300)
        let cycledTopRight = CooperativeCornerResize.Candidate(id: 2,
                                                               frame: CGRect(x: 400, y: 300, width: 800, height: 600))

        let focusedNew = CooperativeCornerResize.focusedFrameResolvingRealizedCornerBoundary(requestedFocusedFrame: focusedDefault,
                                                                                             screenFrame: screenFrame,
                                                                                             candidates: [cycledTopRight],
                                                                                             axis: .vertical,
                                                                                             movedEdge: .bottom,
                                                                                             tolerance: tolerance)

        assertRect(focusedNew, equals: cycledTopRight.frame)
    }

    func testCornerCleanupRebalancesRemainingWindowsAfterMinConstrainedWindowLeaves() {
        let removedTopRight = CGRect(x: 400, y: 540, width: 800, height: 360)
        let targetTopRight = CGRect(x: 400, y: 600, width: 800, height: 300)
        let remainingTopRight = CooperativeCornerResize.Candidate(id: 2,
                                                                  frame: CGRect(x: 400, y: 540, width: 800, height: 360))
        let bottomRight = CooperativeCornerResize.Candidate(id: 3,
                                                            frame: CGRect(x: 400, y: 0, width: 800, height: 540))

        guard let plan = cooperativePlan(focusedOld: removedTopRight,
                                         focusedNew: targetTopRight,
                                         candidates: [remainingTopRight, bottomRight],
                                         axis: .vertical,
                                         focusedMinimumSize: CGSize(width: 1, height: 1),
                                         movedEdgeOverride: .bottom,
                                         candidateDiscoveryFrame: removedTopRight,
                                         actionDescription: "cooperative resize cleanup after focused window left corner") else {
            XCTFail("Expected cleanup cooperative plan")
            return
        }

        assertRect(plan.focusedFrame, equals: targetTopRight)
        assertRect(plan.adjustments[0].newFrame, equals: targetTopRight)
        assertRect(plan.adjustments[1].newFrame, equals: CGRect(x: 400, y: 0, width: 800, height: 600))
    }

    func testCornerCleanupKeepsConstrainedLayoutWhenRemainingWindowCannotFitTarget() {
        let removedTopRight = CGRect(x: 400, y: 540, width: 800, height: 360)
        let targetTopRight = CGRect(x: 400, y: 600, width: 800, height: 300)
        let remainingTopRight = CooperativeCornerResize.Candidate(id: 2,
                                                                  frame: CGRect(x: 400, y: 540, width: 800, height: 360),
                                                                  minimumSize: CGSize(width: 100, height: 360))
        let bottomRight = CooperativeCornerResize.Candidate(id: 3,
                                                            frame: CGRect(x: 400, y: 0, width: 800, height: 540))

        guard let plan = cooperativePlan(focusedOld: removedTopRight,
                                         focusedNew: targetTopRight,
                                         candidates: [remainingTopRight, bottomRight],
                                         axis: .vertical,
                                         focusedMinimumSize: CGSize(width: 1, height: 1),
                                         movedEdgeOverride: .bottom,
                                         candidateDiscoveryFrame: removedTopRight,
                                         actionDescription: "cooperative resize cleanup after focused window left corner") else {
            XCTFail("Expected constrained cleanup cooperative plan")
            return
        }

        assertRect(plan.focusedFrame, equals: removedTopRight)
        assertRect(plan.adjustments[0].newFrame, equals: remainingTopRight.frame)
        assertRect(plan.adjustments[1].newFrame, equals: bottomRight.frame)
    }

    func testCornerCleanupRebalancesFocusedAdjacentDestinationAfterMinConstrainedWindowLeaves() {
        let removedTopLeft = CGRect(x: 0, y: 540, width: 800, height: 360)
        let targetTopLeft = CGRect(x: 0, y: 600, width: 800, height: 300)
        let remainingTopLeft = CooperativeCornerResize.Candidate(id: 2,
                                                                 frame: removedTopLeft)
        let focusedBottomLeft = CooperativeCornerResize.Candidate(id: 99,
                                                                  frame: CGRect(x: 0, y: 0, width: 800, height: 540))

        guard let plan = cooperativePlan(focusedOld: removedTopLeft,
                                         focusedNew: targetTopLeft,
                                         candidates: [remainingTopLeft, focusedBottomLeft],
                                         axis: .vertical,
                                         focusedMinimumSize: CGSize(width: 1, height: 1),
                                         movedEdgeOverride: .bottom,
                                         candidateDiscoveryFrame: removedTopLeft,
                                         actionDescription: "cooperative resize cleanup after focused window left corner") else {
            XCTFail("Expected focused destination cleanup cooperative plan")
            return
        }

        let focusedDestinationAdjustment = plan.adjustments.first { $0.id == focusedBottomLeft.id }

        assertRect(plan.focusedFrame, equals: targetTopLeft)
        assertRect(focusedDestinationAdjustment?.newFrame ?? .null,
                   equals: CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func testNearbyWindowEightPercentOffGridIsCapturedAndNormalized() {
        let focusedOld = CGRect(x: 250, y: 160, width: 320, height: 260)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let offGridTop = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 90, y: 660, width: 620, height: 240))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [offGridTop],
                                         axis: .vertical,
                                         captureTolerance: 72,
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected off-grid nearby window to be captured")
            return
        }

        XCTAssertEqual(plan.adjustments.map(\.id), [offGridTop.id])
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 600, width: 800, height: 300))
        XCTAssertTrue(plan.debugLog.contains { $0.contains("capture-tolerance") })
    }

    func testBoundaryCrossingWindowIsCapturedAndAssignedAdjacent() {
        let focusedOld = CGRect(x: 250, y: 160, width: 320, height: 260)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let crossingTop = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 560, width: 800, height: 340))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [crossingTop],
                                         axis: .vertical,
                                         captureTolerance: 72,
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected boundary-crossing window to be captured")
            return
        }

        XCTAssertEqual(plan.adjustments[0].kind, .adjacent)
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 600, width: 800, height: 300))
        XCTAssertTrue(plan.debugLog.contains { $0.contains("boundary crossing") })
    }

    func testGapConsumingWindowIsCorrectedWhenFeasible() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 600)
        let focusedNew = focusedOld
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 605, width: 800, height: 295))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         gapSize: 12,
                                         captureTolerance: 72,
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected gap-consuming window to be corrected")
            return
        }

        assertRect(plan.focusedFrame, equals: focusedNew)
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 612, width: 800, height: 288))
        XCTAssertEqual(plan.adjustments[0].newFrame.minY - plan.focusedFrame.maxY, 12, accuracy: 0.001)
    }

    func testAggressiveCaptureIgnoresUnrelatedFloatingWindow() {
        let focusedOld = CGRect(x: 250, y: 160, width: 320, height: 260)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let floating = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 900, y: 620, width: 180, height: 160))

        let plan = cooperativePlan(focusedOld: focusedOld,
                                   focusedNew: focusedNew,
                                   candidates: [floating],
                                   axis: .vertical,
                                   captureTolerance: 72,
                                   movedEdgeOverride: .top,
                                   candidateDiscoveryFrame: focusedNew)

        XCTAssertNil(plan)
    }

    func testConfiguredGapIsPreservedForVerticalStack() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 312, width: 800, height: 588))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         gapSize: 12) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: focusedNew)
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 612, width: 800, height: 288))
        XCTAssertEqual(plan.adjustments[0].newFrame.minY - plan.focusedFrame.maxY, 12, accuracy: 0.001)
    }

    func testConfiguredGapAndOversizedNeighborReduceExpansion() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2,
                                                        frame: CGRect(x: 0, y: 312, width: 800, height: 588),
                                                        minimumSize: CGSize(width: 100, height: 350))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         gapSize: 12) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 0, y: 0, width: 800, height: 538))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 0, y: 550, width: 800, height: 350))
        XCTAssertEqual(plan.adjustments[0].newFrame.minY - plan.focusedFrame.maxY, 12, accuracy: 0.001)
    }

    func testCapturedGapPerimeterSurvivesOversizedNeighbor() {
        let focusedOld = CGRect(x: 12, y: 12, width: 782, height: 282)
        let focusedNew = CGRect(x: 12, y: 12, width: 782, height: 582)
        let topLeft = CooperativeCornerResize.Candidate(id: 2,
                                                        frame: CGRect(x: 102, y: 654, width: 602, height: 234),
                                                        minimumSize: CGSize(width: 100, height: 350))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [topLeft],
                                         axis: .vertical,
                                         gapSize: 12,
                                         captureTolerance: 72,
                                         movedEdgeOverride: .top,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected gap-aware cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 12, y: 12, width: 782, height: 514))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 12, y: 538, width: 782, height: 350))
        XCTAssertEqual(plan.adjustments[0].newFrame.minY - plan.focusedFrame.maxY, 12, accuracy: 0.001)
        XCTAssertEqual(plan.adjustments[0].newFrame.maxY, screenFrame.maxY - 12, accuracy: 0.001)
    }

    func testCapturedHorizontalGapPerimeterSurvivesOversizedNeighbor() {
        let focusedOld = CGRect(x: 12, y: 12, width: 282, height: 876)
        let focusedNew = CGRect(x: 12, y: 12, width: 582, height: 876)
        let rightSide = CooperativeCornerResize.Candidate(id: 2,
                                                          frame: CGRect(x: 654, y: 72, width: 534, height: 756),
                                                          minimumSize: CGSize(width: 700, height: 100))

        guard let plan = cooperativePlan(focusedOld: focusedOld,
                                         focusedNew: focusedNew,
                                         candidates: [rightSide],
                                         axis: .horizontal,
                                         gapSize: 12,
                                         captureTolerance: 96,
                                         movedEdgeOverride: .right,
                                         candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected horizontal gap-aware cooperative resize plan")
            return
        }

        assertRect(plan.focusedFrame, equals: CGRect(x: 12, y: 12, width: 464, height: 876))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 488, y: 12, width: 700, height: 876))
        XCTAssertEqual(plan.adjustments[0].newFrame.minX - plan.focusedFrame.maxX, 12, accuracy: 0.001)
        XCTAssertEqual(plan.adjustments[0].newFrame.maxX, screenFrame.maxX - 12, accuracy: 0.001)
    }

    func testSettlingPassAdjustsVerticalOversizedNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 800, height: 600))

        guard let planned = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical),
              let correction = correctionPlan(focusedOld: focusedOld,
                                              focusedNew: focusedNew,
                                              plannedPlan: planned,
                                              candidates: [topLeft],
                                              actualFocusedFrame: planned.focusedFrame,
                                              actualCandidateFramesById: [2: CGRect(x: 0, y: 500, width: 800, height: 400)],
                                              axis: .vertical) else {
            XCTFail("Expected cooperative correction plan")
            return
        }

        assertRect(correction.focusedFrame, equals: CGRect(x: 0, y: 0, width: 800, height: 500))
        assertRect(correction.adjustments[0].newFrame, equals: CGRect(x: 0, y: 500, width: 800, height: 400))
    }

    func testPreFocusedSettlingPreservesGapForOversizedTopNeighbor() {
        let focusedOld = CGRect(x: 1600, y: 160, width: 620, height: 540)
        let focusedNew = CGRect(x: 1077, y: 160, width: 2103, height: 1060)
        let topRight = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 1077, y: 1155, width: 2103, height: 600))

        guard let planned = cooperativePlan(focusedOld: focusedOld,
                                            focusedNew: focusedNew,
                                            screenFrame: CGRect(x: 0, y: 140, width: 3200, height: 1635),
                                            candidates: [topRight],
                                            axis: .vertical,
                                            tolerance: 24,
                                            gapSize: 20,
                                            captureTolerance: 96,
                                            movedEdgeOverride: .top,
                                            candidateDiscoveryFrame: focusedNew),
              let correction = CooperativeCornerResize.correctionPlan(oldFocusedFrame: focusedOld,
                                                                      requestedFocusedFrame: focusedNew,
                                                                      plannedPlan: planned,
                                                                      screenFrame: CGRect(x: 0, y: 140, width: 3200, height: 1635),
                                                                      candidates: [topRight],
                                                                      actualFocusedFrame: planned.focusedFrame,
                                                                      actualCandidateFramesById: [topRight.id: topRight.frame],
                                                                      axis: .vertical,
                                                                      tolerance: 24,
                                                                      layoutTolerance: 4,
                                                                      minimumSize: minimumSize,
                                                                      gapSize: 20,
                                                                      captureTolerance: 96,
                                                                      movedEdgeOverride: .top,
                                                                      candidateDiscoveryFrame: focusedNew) else {
            XCTFail("Expected pre-focused correction plan")
            return
        }

        assertRect(correction.focusedFrame, equals: CGRect(x: 1077, y: 160, width: 2103, height: 975))
        assertRect(correction.adjustments[0].newFrame, equals: CGRect(x: 1077, y: 1155, width: 2103, height: 600))
        XCTAssertEqual(correction.adjustments[0].newFrame.minY - correction.focusedFrame.maxY, 20, accuracy: 0.001)
    }

    func testSettlingPassAdjustsHorizontalOversizedNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 600, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 900)
        let rightSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 600, y: 0, width: 600, height: 900))

        guard let planned = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [rightSide], axis: .horizontal),
              let correction = correctionPlan(focusedOld: focusedOld,
                                              focusedNew: focusedNew,
                                              plannedPlan: planned,
                                              candidates: [rightSide],
                                              actualFocusedFrame: planned.focusedFrame,
                                              actualCandidateFramesById: [2: CGRect(x: 700, y: 0, width: 500, height: 900)],
                                              axis: .horizontal) else {
            XCTFail("Expected cooperative correction plan")
            return
        }

        assertRect(correction.focusedFrame, equals: CGRect(x: 0, y: 0, width: 700, height: 900))
        assertRect(correction.adjustments[0].newFrame, equals: CGRect(x: 700, y: 0, width: 500, height: 900))
    }

    func testSettlingPassHandlesBothAxisOversizedNeighborWithoutSpill() {
        let focusedOld = CGRect(x: 0, y: 0, width: 400, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 400, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 400, height: 600))

        guard let planned = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical),
              let correction = correctionPlan(focusedOld: focusedOld,
                                              focusedNew: focusedNew,
                                              plannedPlan: planned,
                                              candidates: [topLeft],
                                              actualFocusedFrame: planned.focusedFrame,
                                              actualCandidateFramesById: [2: CGRect(x: 0, y: 500, width: 700, height: 400)],
                                              axis: .vertical) else {
            XCTFail("Expected cooperative correction plan")
            return
        }

        assertRect(correction.focusedFrame, equals: CGRect(x: 0, y: 0, width: 400, height: 500))
        assertRect(correction.adjustments[0].newFrame, equals: CGRect(x: 0, y: 500, width: 700, height: 400))
        XCTAssertLessThanOrEqual(correction.adjustments[0].newFrame.maxX, screenFrame.maxX)
        XCTAssertLessThanOrEqual(correction.adjustments[0].newFrame.maxY, screenFrame.maxY)
    }

    func testSettlingPassHandlesOversizedInitiatingWindow() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 800, height: 600))

        guard let planned = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical),
              let correction = correctionPlan(focusedOld: focusedOld,
                                              focusedNew: focusedNew,
                                              plannedPlan: planned,
                                              candidates: [topLeft],
                                              actualFocusedFrame: CGRect(x: 0, y: 0, width: 800, height: 700),
                                              actualCandidateFramesById: [2: planned.adjustments[0].newFrame],
                                              axis: .vertical) else {
            XCTFail("Expected cooperative correction plan")
            return
        }

        assertRect(correction.focusedFrame, equals: CGRect(x: 0, y: 0, width: 800, height: 700))
        assertRect(correction.adjustments[0].newFrame, equals: CGRect(x: 0, y: 700, width: 800, height: 200))
    }

    func testSettlingPassIsSkippedWhenActualFramesMatchPlan() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 300, width: 800, height: 600))

        guard let planned = cooperativePlan(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical) else {
            XCTFail("Expected cooperative resize plan")
            return
        }

        let correction = correctionPlan(focusedOld: focusedOld,
                                        focusedNew: focusedNew,
                                        plannedPlan: planned,
                                        candidates: [topLeft],
                                        actualFocusedFrame: planned.focusedFrame,
                                        actualCandidateFramesById: [2: planned.adjustments[0].newFrame],
                                        axis: .vertical)

        XCTAssertNil(correction)
    }

    func testBottomLeftVerticalShrinkExpandsTopLeftNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 600)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 300)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 600, width: 800, height: 300))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 300, width: 800, height: 600))
        XCTAssertEqual(focusedNew.maxY, adjustments[0].newFrame.minY, accuracy: 0.001)
    }

    func testMatchingBottomLeftWindowShrinksWithFocusedWindowBeforeNeighborExpands() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 600)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 300)
        let matchingBottomLeft = CooperativeCornerResize.Candidate(id: 2, frame: focusedOld)
        let topLeft = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 0, y: 600, width: 800, height: 300))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [matchingBottomLeft, topLeft], axis: .vertical)

        XCTAssertEqual(adjustments.count, 2)
        XCTAssertEqual(adjustments[0].id, matchingBottomLeft.id)
        XCTAssertEqual(adjustments[0].kind, .matchingFocusedFrame)
        assertRect(adjustments[0].newFrame, equals: focusedNew)
        XCTAssertEqual(adjustments[1].id, topLeft.id)
        XCTAssertEqual(adjustments[1].kind, .adjacent)
        assertRect(adjustments[1].newFrame, equals: CGRect(x: 0, y: 300, width: 800, height: 600))
    }

    func testTopLeftHorizontalExpansionShrinksTopRightNeighbor() {
        let focusedOld = CGRect(x: 0, y: 300, width: 600, height: 600)
        let focusedNew = CGRect(x: 0, y: 300, width: 800, height: 600)
        let topRight = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 600, y: 300, width: 600, height: 600))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topRight], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 800, y: 300, width: 400, height: 600))
        XCTAssertEqual(focusedNew.maxX, adjustments[0].newFrame.minX, accuracy: 0.001)
    }

    func testTopLeftHorizontalShrinkExpandsTopRightNeighbor() {
        let focusedOld = CGRect(x: 0, y: 300, width: 800, height: 600)
        let focusedNew = CGRect(x: 0, y: 300, width: 600, height: 600)
        let topRight = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 800, y: 300, width: 400, height: 600))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topRight], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 600, y: 300, width: 600, height: 600))
        XCTAssertEqual(focusedNew.maxX, adjustments[0].newFrame.minX, accuracy: 0.001)
    }

    func testLeftSideHorizontalExpansionShrinksRightSideNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 600, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 900)
        let rightSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 600, y: 0, width: 600, height: 900))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [rightSide], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 800, y: 0, width: 400, height: 900))
        XCTAssertEqual(focusedNew.maxX, adjustments[0].newFrame.minX, accuracy: 0.001)
    }

    func testLeftSideHorizontalExpansionShrinksStackedRightCornerNeighbors() {
        let focusedOld = CGRect(x: 0, y: 0, width: 600, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 900)
        let bottomRight = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 600, y: 0, width: 600, height: 450))
        let topRight = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 600, y: 450, width: 600, height: 450))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [bottomRight, topRight], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 2)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 800, y: 0, width: 400, height: 450))
        assertRect(adjustments[1].newFrame, equals: CGRect(x: 800, y: 450, width: 400, height: 450))
    }

    func testLeftSideHorizontalShrinkExpandsRightSideNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 600, height: 900)
        let rightSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 800, y: 0, width: 400, height: 900))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [rightSide], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 600, y: 0, width: 600, height: 900))
        XCTAssertEqual(focusedNew.maxX, adjustments[0].newFrame.minX, accuracy: 0.001)
    }

    func testMatchingLeftSideWindowShrinksWithFocusedWindowBeforeRightSideNeighborExpands() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 600, height: 900)
        let matchingLeftSide = CooperativeCornerResize.Candidate(id: 2, frame: focusedOld)
        let rightSide = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 800, y: 0, width: 400, height: 900))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [matchingLeftSide, rightSide], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 2)
        XCTAssertEqual(adjustments[0].id, matchingLeftSide.id)
        XCTAssertEqual(adjustments[0].kind, .matchingFocusedFrame)
        assertRect(adjustments[0].newFrame, equals: focusedNew)
        XCTAssertEqual(adjustments[1].id, rightSide.id)
        XCTAssertEqual(adjustments[1].kind, .adjacent)
        assertRect(adjustments[1].newFrame, equals: CGRect(x: 600, y: 0, width: 600, height: 900))
    }

    func testLeftSideShrinkAlsoShrinksPartialBottomLeftOccupant() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 900)
        let focusedNew = CGRect(x: 0, y: 0, width: 400, height: 900)
        let bottomLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        let bottomRight = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 800, y: 0, width: 400, height: 300))
        let topRight = CooperativeCornerResize.Candidate(id: 4, frame: CGRect(x: 800, y: 300, width: 400, height: 600))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld,
                                                focusedNew: focusedNew,
                                                candidates: [bottomLeft, bottomRight, topRight],
                                                axis: .horizontal)

        XCTAssertEqual(adjustments.count, 3)
        XCTAssertEqual(adjustments[0].id, bottomLeft.id)
        XCTAssertEqual(adjustments[0].kind, .matchingFocusedFrame)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 0, width: 400, height: 300))
        assertRect(adjustments[1].newFrame, equals: CGRect(x: 400, y: 0, width: 800, height: 300))
        assertRect(adjustments[2].newFrame, equals: CGRect(x: 400, y: 300, width: 800, height: 600))
    }

    func testRightSideHorizontalExpansionShrinksLeftSideNeighbor() {
        let focusedOld = CGRect(x: 600, y: 0, width: 600, height: 900)
        let focusedNew = CGRect(x: 400, y: 0, width: 800, height: 900)
        let leftSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 600, height: 900))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [leftSide], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 0, width: 400, height: 900))
        XCTAssertEqual(adjustments[0].newFrame.maxX, focusedNew.minX, accuracy: 0.001)
    }

    func testTopSideVerticalExpansionShrinksBottomSideNeighbor() {
        let focusedOld = CGRect(x: 0, y: 450, width: 1200, height: 450)
        let focusedNew = CGRect(x: 0, y: 300, width: 1200, height: 600)
        let bottomSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 1200, height: 450))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [bottomSide], axis: .vertical)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 0, width: 1200, height: 300))
        XCTAssertEqual(adjustments[0].newFrame.maxY, focusedNew.minY, accuracy: 0.001)
    }

    func testTopSideVerticalExpansionShrinksStackedBottomCornerNeighbors() {
        let focusedOld = CGRect(x: 0, y: 450, width: 1200, height: 450)
        let focusedNew = CGRect(x: 0, y: 300, width: 1200, height: 600)
        let bottomLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 600, height: 450))
        let bottomRight = CooperativeCornerResize.Candidate(id: 3, frame: CGRect(x: 600, y: 0, width: 600, height: 450))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [bottomLeft, bottomRight], axis: .vertical)

        XCTAssertEqual(adjustments.count, 2)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 0, width: 600, height: 300))
        assertRect(adjustments[1].newFrame, equals: CGRect(x: 600, y: 0, width: 600, height: 300))
    }

    func testTopSideVerticalShrinkExpandsBottomSideNeighbor() {
        let focusedOld = CGRect(x: 0, y: 300, width: 1200, height: 600)
        let focusedNew = CGRect(x: 0, y: 450, width: 1200, height: 450)
        let bottomSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 1200, height: 300))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [bottomSide], axis: .vertical)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 0, width: 1200, height: 450))
        XCTAssertEqual(adjustments[0].newFrame.maxY, focusedNew.minY, accuracy: 0.001)
    }

    func testBottomSideVerticalExpansionShrinksTopSideNeighbor() {
        let focusedOld = CGRect(x: 0, y: 0, width: 1200, height: 450)
        let focusedNew = CGRect(x: 0, y: 0, width: 1200, height: 600)
        let topSide = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 0, y: 450, width: 1200, height: 450))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topSide], axis: .vertical)

        XCTAssertEqual(adjustments.count, 1)
        assertRect(adjustments[0].newFrame, equals: CGRect(x: 0, y: 600, width: 1200, height: 300))
        XCTAssertEqual(focusedNew.maxY, adjustments[0].newFrame.minY, accuracy: 0.001)
    }

    func testNoAdjacentCandidateFound() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [], axis: .vertical)

        XCTAssertTrue(adjustments.isEmpty)
    }

    func testAmbiguousFloatingWindowIsIgnored() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let floating = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 20, y: 302, width: 500, height: 240))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [floating], axis: .vertical)

        XCTAssertTrue(adjustments.isEmpty)
    }

    func testToleranceMatchesNormalTiledNeighborsWithGaps() {
        let focusedOld = CGRect(x: 0, y: 0, width: 800, height: 300)
        let focusedNew = CGRect(x: 0, y: 0, width: 800, height: 600)
        let topLeft = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 3, y: 305, width: 794, height: 592))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topLeft], axis: .vertical)

        XCTAssertEqual(adjustments.count, 1)
        XCTAssertEqual(adjustments[0].newFrame.minY, focusedNew.maxY, accuracy: 0.001)
    }

    func testNonCycledAxisRemainsUnchanged() {
        let focusedOld = CGRect(x: 0, y: 300, width: 600, height: 600)
        let focusedNew = CGRect(x: 0, y: 300, width: 800, height: 600)
        let topRight = CooperativeCornerResize.Candidate(id: 2, frame: CGRect(x: 600, y: 300, width: 600, height: 600))

        let adjustments = cooperativeAdjustments(focusedOld: focusedOld, focusedNew: focusedNew, candidates: [topRight], axis: .horizontal)

        XCTAssertEqual(adjustments.count, 1)
        XCTAssertEqual(adjustments[0].newFrame.minY, topRight.frame.minY, accuracy: 0.001)
        XCTAssertEqual(adjustments[0].newFrame.height, topRight.frame.height, accuracy: 0.001)
    }

    private func cooperativeAdjustments(focusedOld: CGRect,
                                        focusedNew: CGRect,
                                        candidates: [CooperativeCornerResize.Candidate],
                                        axis: CornerCycleExpansionAxis,
                                        gapSize: CGFloat = 0) -> [CooperativeCornerResize.Adjustment] {
        CooperativeCornerResize.adjustments(oldFocusedFrame: focusedOld,
                                            newFocusedFrame: focusedNew,
                                            screenFrame: screenFrame,
                                            candidates: candidates,
                                            axis: axis,
                                            tolerance: tolerance,
                                            minimumSize: minimumSize,
                                            gapSize: gapSize)
    }

    private func cooperativePlan(focusedOld: CGRect,
                                 focusedNew: CGRect,
                                 screenFrame: CGRect? = nil,
                                 candidates: [CooperativeCornerResize.Candidate],
                                 axis: CornerCycleExpansionAxis,
                                 tolerance: CGFloat? = nil,
                                 gapSize: CGFloat = 0,
                                 focusedMinimumSize: CGSize? = nil,
                                 captureTolerance: CGFloat? = nil,
                                 movedEdgeOverride: CooperativeCornerResize.MovedEdge? = nil,
                                 candidateDiscoveryFrame: CGRect? = nil,
                                 actionDescription: String = "test cooperative resize") -> CooperativeCornerResize.Plan? {
        CooperativeCornerResize.plan(oldFocusedFrame: focusedOld,
                                     newFocusedFrame: focusedNew,
                                     screenFrame: screenFrame ?? self.screenFrame,
                                     candidates: candidates,
                                     axis: axis,
                                     tolerance: tolerance ?? self.tolerance,
                                     minimumSize: minimumSize,
                                     focusedMinimumSize: focusedMinimumSize,
                                     gapSize: gapSize,
                                     captureTolerance: captureTolerance,
                                     movedEdgeOverride: movedEdgeOverride,
                                     candidateDiscoveryFrame: candidateDiscoveryFrame,
                                     actionDescription: actionDescription)
    }

    private func correctionPlan(focusedOld: CGRect,
                                focusedNew: CGRect,
                                plannedPlan: CooperativeCornerResize.Plan,
                                candidates: [CooperativeCornerResize.Candidate],
                                actualFocusedFrame: CGRect,
                                actualCandidateFramesById: [CGWindowID: CGRect],
                                axis: CornerCycleExpansionAxis,
                                gapSize: CGFloat = 0,
                                captureTolerance: CGFloat? = nil,
                                movedEdgeOverride: CooperativeCornerResize.MovedEdge? = nil,
                                candidateDiscoveryFrame: CGRect? = nil) -> CooperativeCornerResize.Plan? {
        CooperativeCornerResize.correctionPlan(oldFocusedFrame: focusedOld,
                                               requestedFocusedFrame: focusedNew,
                                               plannedPlan: plannedPlan,
                                               screenFrame: screenFrame,
                                               candidates: candidates,
                                               actualFocusedFrame: actualFocusedFrame,
                                               actualCandidateFramesById: actualCandidateFramesById,
                                               axis: axis,
                                               tolerance: tolerance,
                                               layoutTolerance: 4,
                                               minimumSize: minimumSize,
                                               gapSize: gapSize,
                                               captureTolerance: captureTolerance,
                                               movedEdgeOverride: movedEdgeOverride,
                                               candidateDiscoveryFrame: candidateDiscoveryFrame)
    }

    private func assertRect(_ rect: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}

class CycleSizeRatioPresetTests: XCTestCase {

    func testPercentValuesMatchCycleSizeFractions() {
        XCTAssertEqual(CycleSize.oneHalf.percentValue, 50, accuracy: 0.001)
        XCTAssertEqual(CycleSize.twoThirds.percentValue, 66.666, accuracy: 0.001)
        XCTAssertEqual(CycleSize.oneThird.percentValue, 33.333, accuracy: 0.001)
    }

    func testMatchingPercentValueUsesTolerance() {
        XCTAssertEqual(CycleSize.matching(percentValue: 33.3334), .oneThird)
        XCTAssertEqual(CycleSize.matching(percentValue: 66.6666), .twoThirds)
    }

    func testCustomPercentValueDoesNotMatchPreset() {
        XCTAssertNil(CycleSize.matching(percentValue: 60))
    }
}

class ActiveSideSplitRatiosCooperativeTests: XCTestCase {
    private let screenFrame = CGRect(x: 10, y: 20, width: 1200, height: 900)
    private let gapSize: CGFloat = 20
    private var savedHorizontalSplitRatio: Float = 50
    private var savedVerticalSplitRatio: Float = 50
    private var savedCornerCycleExpansionAxis: CornerCycleExpansionAxis = .horizontal
    private var savedSubsequentExecutionMode: SubsequentExecutionMode = .resize

    override func setUp() {
        super.setUp()
        savedHorizontalSplitRatio = Defaults.horizontalSplitRatio.value
        savedVerticalSplitRatio = Defaults.verticalSplitRatio.value
        savedCornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        savedSubsequentExecutionMode = Defaults.subsequentExecutionMode.value
        Defaults.horizontalSplitRatio.value = CycleSize.oneQuarter.percentValue
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.subsequentExecutionMode.value = .resize
        ActiveSideSplitRatios.shared.resetAll()
    }

    override func tearDown() {
        Defaults.horizontalSplitRatio.value = savedHorizontalSplitRatio
        Defaults.verticalSplitRatio.value = savedVerticalSplitRatio
        Defaults.cornerCycleExpansionAxis.value = savedCornerCycleExpansionAxis
        Defaults.subsequentExecutionMode.value = savedSubsequentExecutionMode
        ActiveSideSplitRatios.shared.resetAll()
        super.tearDown()
    }

    func testMinWidthConstrainedTopLeftRecordsAchievedHorizontalSplit() throws {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let plan = try XCTUnwrap(topLeftPlan(focusedMinimumSize: CGSize(width: 360, height: 100)))

        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: plan.focusedFrame,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        XCTAssertEqual(plan.focusedFrame.width, 360, accuracy: 0.001)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screenFrame), 0.325, accuracy: 0.001)
    }

    func testBottomLeftAfterMinWidthConstraintUsesAchievedHorizontalSplit() throws {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let plan = try XCTUnwrap(topLeftPlan(focusedMinimumSize: CGSize(width: 360, height: 100)))
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: plan.focusedFrame,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        let bottomLeft = WindowCalculationFactory.lowerLeftCalculation.calculateRect(params(for: .bottomLeft)).rect
        let gappedBottomLeft = GapCalculation.applyGaps(bottomLeft,
                                                        sharedEdges: WindowAction.bottomLeft.gapSharedEdge,
                                                        gapSize: Float(gapSize))

        XCTAssertEqual(bottomLeft.width, 390, accuracy: 0.001)
        XCTAssertEqual(gappedBottomLeft.width, plan.focusedFrame.width, accuracy: 0.001)
        XCTAssertEqual(gappedBottomLeft.maxX, plan.focusedFrame.maxX, accuracy: 0.001)
    }

    func testMinHeightConstrainedTopLeftRecordsAchievedVerticalSplit() throws {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let plan = try XCTUnwrap(topLeftPlan(focusedMinimumSize: CGSize(width: 100, height: 360)))

        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: plan.focusedFrame,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        XCTAssertEqual(plan.focusedFrame.height, 360, accuracy: 0.001)
        XCTAssertEqual(ActiveSideSplitRatios.shared.verticalRatio(for: screenFrame), 390.0 / 900.0, accuracy: 0.001)
        XCTAssertEqual(WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf)).rect.height,
                       390,
                       accuracy: 0.001)
    }

    func testRightAndBottomConstraintsRecordSymmetricLeadingSplits() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let constrainedTopRight = gappedCornerFrame(horizontalSide: .trailing,
                                                    verticalSide: .leading,
                                                    horizontalFraction: 390.0 / 1200.0,
                                                    verticalFraction: CycleSize.oneThird.fraction,
                                                    action: .topRight)
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topRight,
                                                                    achievedFrame: constrainedTopRight,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screenFrame), 0.675, accuracy: 0.001)
        XCTAssertEqual(WindowCalculationFactory.rightHalfCalculation.calculateRect(params(for: .rightHalf)).rect.width,
                       390,
                       accuracy: 0.001)

        let constrainedBottomRight = gappedCornerFrame(horizontalSide: .trailing,
                                                       verticalSide: .trailing,
                                                       horizontalFraction: 390.0 / 1200.0,
                                                       verticalFraction: 390.0 / 900.0,
                                                       action: .bottomRight)
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.bottomRight,
                                                                    achievedFrame: constrainedBottomRight,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        XCTAssertEqual(ActiveSideSplitRatios.shared.verticalRatio(for: screenFrame), 1.0 - 390.0 / 900.0, accuracy: 0.001)
        XCTAssertEqual(WindowCalculationFactory.bottomHalfCalculation.calculateRect(params(for: .bottomHalf)).rect.height,
                       390,
                       accuracy: 0.001)
    }

    func testAchievedCooperativeRatiosDoNotChangeSavedDefaults() throws {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let savedHorizontal = Defaults.horizontalSplitRatio.value
        let savedVertical = Defaults.verticalSplitRatio.value
        let plan = try XCTUnwrap(topLeftPlan(focusedMinimumSize: CGSize(width: 360, height: 360)))

        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: plan.focusedFrame,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        XCTAssertEqual(Defaults.horizontalSplitRatio.value, savedHorizontal, accuracy: 0.001)
        XCTAssertEqual(Defaults.verticalSplitRatio.value, savedVertical, accuracy: 0.001)
        XCTAssertNotEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screenFrame), savedHorizontal / 100.0)
        XCTAssertNotEqual(ActiveSideSplitRatios.shared.verticalRatio(for: screenFrame), savedVertical / 100.0)
    }

    func testGapIsIncludedWhenDerivingAchievedSplit() throws {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let plan = try XCTUnwrap(topLeftPlan(focusedMinimumSize: CGSize(width: 360, height: 100)))
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: plan.focusedFrame,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        let ratioIgnoringInternalHalfGap = Float((plan.focusedFrame.maxX - screenFrame.minX) / screenFrame.width)
        XCTAssertEqual(ratioIgnoringInternalHalfGap, 380.0 / 1200.0, accuracy: 0.001)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screenFrame), 390.0 / 1200.0, accuracy: 0.001)
    }

    func testCyclicCornerAfterConstraintUsesAchievedPerpendicularRatio() throws {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        let plan = try XCTUnwrap(topLeftPlan(focusedMinimumSize: CGSize(width: 360, height: 100)))
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: plan.focusedFrame,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: gapSize)

        let firstBottomLeft = WindowCalculationFactory.lowerLeftCalculation.calculateRect(params(for: .bottomLeft)).rect
        let cycledBottomLeft = WindowCalculationFactory.lowerLeftCalculation.calculateRect(
            RectCalculationParameters(window: Window(id: 1, rect: firstBottomLeft),
                                      visibleFrameOfScreen: screenFrame,
                                      action: .bottomLeft,
                                      lastAction: RectangleAction(action: .bottomLeft,
                                                                  subAction: nil,
                                                                  rect: firstBottomLeft,
                                                                  count: 1))
        ).rect

        XCTAssertNotEqual(cycledBottomLeft.height, firstBottomLeft.height)
        XCTAssertEqual(cycledBottomLeft.width, 390, accuracy: 0.001)
    }

    private func topLeftPlan(focusedMinimumSize: CGSize) -> CooperativeCornerResize.Plan? {
        let requestedTopLeft = gappedCornerFrame(horizontalSide: .leading,
                                                 verticalSide: .leading,
                                                 horizontalFraction: CycleSize.oneQuarter.fraction,
                                                 verticalFraction: CycleSize.oneThird.fraction,
                                                 action: .topLeft)
        let bottomLeft = gappedCornerFrame(horizontalSide: .leading,
                                           verticalSide: .trailing,
                                           horizontalFraction: CycleSize.oneQuarter.fraction,
                                           verticalFraction: 1.0 - CycleSize.oneThird.fraction,
                                           action: .bottomLeft)

        return CooperativeCornerResize.plan(oldFocusedFrame: CGRect(x: 300, y: 250, width: 400, height: 300),
                                            newFocusedFrame: requestedTopLeft,
                                            screenFrame: screenFrame,
                                            candidates: [CooperativeCornerResize.Candidate(id: 2, frame: bottomLeft)],
                                            axis: .vertical,
                                            tolerance: 8,
                                            minimumSize: CGSize(width: 100, height: 100),
                                            focusedMinimumSize: focusedMinimumSize,
                                            gapSize: gapSize,
                                            captureTolerance: 72,
                                            movedEdgeOverride: .bottom,
                                            candidateDiscoveryFrame: requestedTopLeft,
                                            actionDescription: "test constrained top-left placement")
    }

    private func gappedCornerFrame(horizontalSide: HalfSplitSide,
                                   verticalSide: HalfSplitSide,
                                   horizontalFraction: Float,
                                   verticalFraction: Float,
                                   action: WindowAction) -> CGRect {
        let rawFrame = HalfSplitFrameCalculation.cornerRect(in: screenFrame,
                                                            horizontalSide: horizontalSide,
                                                            verticalSide: verticalSide,
                                                            horizontalFraction: horizontalFraction,
                                                            verticalFraction: verticalFraction)
        return GapCalculation.applyGaps(rawFrame,
                                        sharedEdges: action.gapSharedEdge,
                                        gapSize: Float(gapSize))
    }

    private func params(for action: WindowAction) -> RectCalculationParameters {
        RectCalculationParameters(window: Window(id: 1, rect: screenFrame),
                                  visibleFrameOfScreen: screenFrame,
                                  action: action,
                                  lastAction: nil)
    }
}

class HalfSplitCornerCalculationTests: XCTestCase {
    
    private var savedHorizontalSplitRatio: Float = 50
    private var savedVerticalSplitRatio: Float = 50
    private var savedSubsequentExecutionMode: SubsequentExecutionMode = .resize
    private var savedCornerCycleExpansionAxis: CornerCycleExpansionAxis = .horizontal
    private var savedCycleSizesIsChanged = false
    private var savedSelectedCycleSizes = Set<CycleSize>()
    private var savedGapSize: Float = 0
    private var savedSkipGapTopEdge = false
    private let visibleFrame = CGRect(x: 10, y: 20, width: 1200, height: 900)
    
    override func setUp() {
        super.setUp()
        savedHorizontalSplitRatio = Defaults.horizontalSplitRatio.value
        savedVerticalSplitRatio = Defaults.verticalSplitRatio.value
        savedSubsequentExecutionMode = Defaults.subsequentExecutionMode.value
        savedCornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        savedCycleSizesIsChanged = Defaults.cycleSizesIsChanged.enabled
        savedSelectedCycleSizes = Defaults.selectedCycleSizes.value
        savedGapSize = Defaults.gapSize.value
        savedSkipGapTopEdge = Defaults.skipGapTopEdge.enabled
        Defaults.subsequentExecutionMode.value = .resize
        Defaults.cycleSizesIsChanged.enabled = false
        Defaults.gapSize.value = 0
        Defaults.skipGapTopEdge.enabled = false
        ActiveSideSplitRatios.shared.resetAll()
    }
    
    override func tearDown() {
        Defaults.horizontalSplitRatio.value = savedHorizontalSplitRatio
        Defaults.verticalSplitRatio.value = savedVerticalSplitRatio
        Defaults.subsequentExecutionMode.value = savedSubsequentExecutionMode
        Defaults.cornerCycleExpansionAxis.value = savedCornerCycleExpansionAxis
        Defaults.cycleSizesIsChanged.enabled = savedCycleSizesIsChanged
        Defaults.selectedCycleSizes.value = savedSelectedCycleSizes
        Defaults.gapSize.value = savedGapSize
        Defaults.skipGapTopEdge.enabled = savedSkipGapTopEdge
        ActiveSideSplitRatios.shared.resetAll()
        super.tearDown()
    }
    
    func testCornersUseHalfSplitRatioOneHalf() {
        setSplitRatio(50)
        
        assertCornerRects(
            topLeft: CGRect(x: 10, y: 470, width: 600, height: 450),
            topRight: CGRect(x: 610, y: 470, width: 600, height: 450),
            bottomLeft: CGRect(x: 10, y: 20, width: 600, height: 450),
            bottomRight: CGRect(x: 610, y: 20, width: 600, height: 450)
        )
    }
    
    func testCornersUseHalfSplitRatioTwoThirds() {
        setSplitRatio(CycleSize.twoThirds.percentValue)
        
        assertCornerRects(
            topLeft: CGRect(x: 10, y: 320, width: 800, height: 600),
            topRight: CGRect(x: 810, y: 320, width: 400, height: 600),
            bottomLeft: CGRect(x: 10, y: 20, width: 800, height: 300),
            bottomRight: CGRect(x: 810, y: 20, width: 400, height: 300)
        )
    }
    
    func testCornersUseHalfSplitRatioThreeQuarters() {
        setSplitRatio(CycleSize.threeQuarters.percentValue)
        
        assertCornerRects(
            topLeft: CGRect(x: 10, y: 245, width: 900, height: 675),
            topRight: CGRect(x: 910, y: 245, width: 300, height: 675),
            bottomLeft: CGRect(x: 10, y: 20, width: 900, height: 225),
            bottomRight: CGRect(x: 910, y: 20, width: 300, height: 225)
        )
    }
    
    func testCornersUseCustomHalfSplitRatio() {
        setSplitRatio(60)
        
        assertCornerRects(
            topLeft: CGRect(x: 10, y: 380, width: 720, height: 540),
            topRight: CGRect(x: 730, y: 380, width: 480, height: 540),
            bottomLeft: CGRect(x: 10, y: 20, width: 720, height: 360),
            bottomRight: CGRect(x: 730, y: 20, width: 480, height: 360)
        )
    }
    
    func testHalfActionsStillUseHalfSplitRatio() {
        setSplitRatio(60)
        
        assertRect(WindowCalculationFactory.leftHalfCalculation.calculateRect(params(for: .leftHalf)).rect,
                   equals: CGRect(x: 10, y: 20, width: 720, height: 900))
        assertRect(WindowCalculationFactory.rightHalfCalculation.calculateRect(params(for: .rightHalf)).rect,
                   equals: CGRect(x: 730, y: 20, width: 480, height: 900))
        assertRect(WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf)).rect,
                   equals: CGRect(x: 10, y: 380, width: 1200, height: 540))
        assertRect(WindowCalculationFactory.bottomHalfCalculation.calculateRect(params(for: .bottomHalf)).rect,
                   equals: CGRect(x: 10, y: 20, width: 1200, height: 360))
    }

    func testRepeatedCornersWithHorizontalExpansionCycleWidthOnly() {
        setSplitRatio(60)
        Defaults.cornerCycleExpansionAxis.value = .horizontal

        assertRepeatedCornerRects(
            topLeft: CGRect(x: 10, y: 380, width: 800, height: 540),
            topRight: CGRect(x: 410, y: 380, width: 800, height: 540),
            bottomLeft: CGRect(x: 10, y: 20, width: 800, height: 360),
            bottomRight: CGRect(x: 410, y: 20, width: 800, height: 360)
        )
    }

    func testSecondRepeatedCornerShortcutBeginsCyclingImmediately() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        setSplitRatio(CycleSize.twoThirds.percentValue)
        Defaults.cornerCycleExpansionAxis.value = .horizontal

        let firstFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect
        let secondFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(repeatedParams(for: .topLeft, currentRect: firstFrame, count: 1)).rect
        let thirdFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(repeatedParams(for: .topLeft, currentRect: secondFrame, count: 2)).rect

        assertRect(firstFrame, equals: CGRect(x: 10, y: 320, width: 800, height: 600))
        assertRect(secondFrame, equals: CGRect(x: 10, y: 320, width: 400, height: 600))
        assertRect(thirdFrame, equals: CGRect(x: 10, y: 320, width: 600, height: 600))
    }

    func testRepeatedCornerCyclingDoesNotReturnNoOpFrameWhenBaseMatchesCycleSize() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        setSplitRatio(CycleSize.twoThirds.percentValue)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let firstFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(params(for: .topRight)).rect
        let secondFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(repeatedParams(for: .topRight, currentRect: firstFrame, count: 1)).rect

        XCTAssertFalse(firstFrame.equalTo(secondFrame))
        XCTAssertEqual(firstFrame.maxY, secondFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(firstFrame.origin.x, secondFrame.origin.x, accuracy: 0.001)
        XCTAssertEqual(firstFrame.width, secondFrame.width, accuracy: 0.001)
    }

    func testRepeatedCornerCyclingRecognizesGapAdjustedCooperativeBoundary() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.gapSize.value = 20

        let rawTwoThirdsFrame = WindowCalculationFactory.lowerRightCalculation.calculateRect(params(for: .bottomRight)).rect
        var cooperativeCurrentFrame = GapCalculation.applyGaps(rawTwoThirdsFrame,
                                                               dimension: .both,
                                                               sharedEdges: WindowAction.bottomRight.gapSharedEdge,
                                                               gapSize: Defaults.gapSize.value,
                                                               skipTopGap: Defaults.skipGapTopEdge.enabled)
        cooperativeCurrentFrame.size.height = rawTwoThirdsFrame.height

        let repeatedFrame = WindowCalculationFactory.lowerRightCalculation.calculateRect(repeatedParams(for: .bottomRight,
                                                                                                        currentRect: cooperativeCurrentFrame,
                                                                                                        count: 1)).rect

        assertRect(rawTwoThirdsFrame, equals: CGRect(x: 810, y: 20, width: 400, height: 600))
        assertRect(cooperativeCurrentFrame, equals: CGRect(x: 820, y: 40, width: 370, height: 600))
        assertRect(repeatedFrame, equals: CGRect(x: 810, y: 20, width: 400, height: 300))
    }

    func testCleanupTargetSkipsCornerReducedByAdjacentMinimumConstraint() {
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let reducedBottomLeft = CGRect(x: 10, y: 20, width: 800, height: 500)
        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .bottomLeft,
                                                              observedFrame: reducedBottomLeft,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .top,
                                                              tolerance: 8,
                                                              includeCycleTargets: true)

        XCTAssertNil(cleanupTarget)
    }

    func testCleanupSourceFinderSupportsSideActionsAndIgnoresCorners() {
        setSplitRatio(50)

        let expandedLeft = CGRect(x: 10, y: 20, width: 700, height: 900)
        let remainingLeft = CooperativeCornerResize.Candidate(id: 2,
                                                              frame: expandedLeft)
        let cornerWidthMatch = CooperativeCornerResize.Candidate(id: 3,
                                                                 frame: CGRect(x: 10, y: 470, width: 800, height: 450))
        let sourceFrame = WindowManager().observedCooperativeSourceFrame(action: .leftHalf,
                                                                         oldFocusedFrame: expandedLeft,
                                                                         candidates: [cornerWidthMatch, remainingLeft],
                                                                         screenFrame: visibleFrame,
                                                                         axis: .horizontal,
                                                                         movedEdge: .right,
                                                                         tolerance: 8,
                                                                         captureTolerance: 96,
                                                                         gapSize: 0)

        assertRect(sourceFrame ?? .null, equals: expandedLeft)
    }

    func testCleanupTargetShrinksExpandedSideSource() {
        setSplitRatio(50)

        let expandedLeft = CGRect(x: 10, y: 20, width: 700, height: 900)
        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .leftHalf,
                                                              observedFrame: expandedLeft,
                                                              screenFrame: visibleFrame,
                                                              axis: .horizontal,
                                                              movedEdge: .right,
                                                              tolerance: 8,
                                                              includeCycleTargets: false)

        assertRect(cleanupTarget ?? .null, equals: CGRect(x: 10, y: 20, width: 600, height: 900))
    }

    func testCooperativeHistoryActionMapsAdjacentSideAndCornerActions() {
        let manager = WindowManager()

        XCTAssertEqual(manager.cooperativeHistoryAction(for: .matchingFocusedFrame,
                                                        sourceAction: .leftHalf,
                                                        movedEdge: .right),
                       .leftHalf)
        XCTAssertEqual(manager.cooperativeHistoryAction(for: .adjacent,
                                                        sourceAction: .leftHalf,
                                                        movedEdge: .right),
                       .rightHalf)
        XCTAssertEqual(manager.cooperativeHistoryAction(for: .adjacent,
                                                        sourceAction: .topLeft,
                                                        movedEdge: .bottom),
                       .bottomLeft)
    }

    func testRecordActionCanPreserveCooperativeCorrectionCount() {
        let manager = WindowManager()
        let windowId = CGWindowID(987_654)
        let originalRect = CGRect(x: 10, y: 20, width: 600, height: 900)
        let correctedRect = CGRect(x: 10, y: 20, width: 800, height: 900)
        AppDelegate.windowHistory.lastRectangleActions[windowId] = RectangleAction(action: .leftHalf,
                                                                                   subAction: nil,
                                                                                   rect: originalRect,
                                                                                   count: 3)
        defer {
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        }

        manager.recordAction(windowId: windowId,
                             resultingRect: correctedRect,
                             action: .leftHalf,
                             subAction: nil,
                             incrementCount: false)

        let recorded = AppDelegate.windowHistory.lastRectangleActions[windowId]
        XCTAssertEqual(recorded?.count, 3)
        assertRect(recorded?.rect ?? .null, equals: correctedRect)
    }

    func testCleanupTargetAllowsExpandedMinimumConstrainedCorner() {
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let expandedTopLeft = CGRect(x: 10, y: 400, width: 800, height: 520)
        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .topLeft,
                                                              observedFrame: expandedTopLeft,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .bottom,
                                                              tolerance: 8,
                                                              includeCycleTargets: false)

        assertRect(cleanupTarget ?? .null, equals: CGRect(x: 10, y: 620, width: 800, height: 300))
    }

    func testCleanupTargetShrinksMinimumRestrictedSourceAtConfiguredSize() {
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = 40
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let minimumRestrictedTopRight = CGRect(x: 610, y: 560, width: 600, height: 360)

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .topRight,
                                                              observedFrame: minimumRestrictedTopRight,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .bottom,
                                                              tolerance: 8,
                                                              includeCycleTargets: false)

        assertRect(cleanupTarget ?? .null, equals: CGRect(x: 610, y: 620, width: 600, height: 300))
    }

    func testCleanupDestinationAllowsNonAdjacentMinimumRestrictedSourceCleanup() {
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = 40
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let manager = WindowManager()
        let minimumRestrictedTopRight = CGRect(x: 610, y: 560, width: 600, height: 360)
        let focusedTopLeftDestination = CGRect(x: 10, y: 620, width: 600, height: 300)
        guard let cleanupTarget = manager.cleanupTargetFrame(action: .topRight,
                                                            observedFrame: minimumRestrictedTopRight,
                                                            screenFrame: visibleFrame,
                                                            axis: .vertical,
                                                            movedEdge: .bottom,
                                                            tolerance: 8,
                                                            includeCycleTargets: false)
        else {
            XCTFail("Expected minimum-restricted cleanup target")
            return
        }

        XCTAssertFalse(manager.frameIsAdjacentToCleanupSource(focusedTopLeftDestination,
                                                              sourceFrame: minimumRestrictedTopRight,
                                                              movedEdge: .bottom,
                                                              axis: .vertical,
                                                              tolerance: 8,
                                                              gapSize: 0))
        XCTAssertTrue(manager.cleanupDestinationAllowsSourceResize(action: .topRight,
                                                                   observedFrame: minimumRestrictedTopRight,
                                                                   targetFrame: cleanupTarget,
                                                                   focusedDestinationFrame: focusedTopLeftDestination,
                                                                   screenFrame: visibleFrame,
                                                                   axis: .vertical,
                                                                   movedEdge: .bottom,
                                                                   tolerance: 8,
                                                                   gapSize: 0))
    }

    func testCleanupSourceFallsBackToDepartedMinimumRestrictedCornerAndExpandsAdjacent() {
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = 40
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let manager = WindowManager()
        let departedTopRight = CGRect(x: 610, y: 560, width: 600, height: 360)
        let bottomRight = CooperativeCornerResize.Candidate(id: 2,
                                                            frame: CGRect(x: 610, y: 20, width: 600, height: 540))
        guard let sourceFrame = manager.cleanupSourceFrame(action: .topRight,
                                                           oldFocusedFrame: departedTopRight,
                                                           candidates: [bottomRight],
                                                           screenFrame: visibleFrame,
                                                           axis: .vertical,
                                                           movedEdge: .bottom,
                                                           tolerance: 8,
                                                           captureTolerance: 96,
                                                           gapSize: 0),
              let targetFrame = manager.cleanupTargetFrame(action: .topRight,
                                                           observedFrame: sourceFrame,
                                                           screenFrame: visibleFrame,
                                                           axis: .vertical,
                                                           movedEdge: .bottom,
                                                           tolerance: 8,
                                                           includeCycleTargets: false),
              let plan = CooperativeCornerResize.plan(oldFocusedFrame: sourceFrame,
                                                      newFocusedFrame: targetFrame,
                                                      screenFrame: visibleFrame,
                                                      candidates: [bottomRight],
                                                      axis: .vertical,
                                                      tolerance: 8,
                                                      minimumSize: CGSize(width: 100, height: 100),
                                                      focusedMinimumSize: CGSize(width: 1, height: 1),
                                                      movedEdgeOverride: .bottom,
                                                      candidateDiscoveryFrame: sourceFrame,
                                                      actionDescription: "cooperative resize cleanup after focused window left source")
        else {
            XCTFail("Expected departed minimum-restricted corner cleanup plan")
            return
        }

        assertRect(sourceFrame, equals: departedTopRight)
        assertRect(targetFrame, equals: CGRect(x: 610, y: 620, width: 600, height: 300))
        assertRect(plan.adjustments[0].newFrame, equals: CGRect(x: 610, y: 20, width: 600, height: 600))
    }

    func testCleanupSourceDoesNotFallBackToDepartedCycleCorner() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let cycledTopRight = CGRect(x: 610, y: 320, width: 600, height: 600)
        let bottomRight = CooperativeCornerResize.Candidate(id: 2,
                                                            frame: CGRect(x: 610, y: 20, width: 600, height: 300))

        let sourceFrame = WindowManager().cleanupSourceFrame(action: .topRight,
                                                            oldFocusedFrame: cycledTopRight,
                                                            candidates: [bottomRight],
                                                            screenFrame: visibleFrame,
                                                            axis: .vertical,
                                                            movedEdge: .bottom,
                                                            tolerance: 8,
                                                            captureTolerance: 96,
                                                            gapSize: 0)

        XCTAssertNil(sourceFrame)
    }

    func testCleanupDestinationRejectsNonAdjacentCycleSourceCleanup() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let manager = WindowManager()
        let cycledBottomRight = CGRect(x: 610, y: 20, width: 600, height: 600)
        let focusedTopLeftDestination = CGRect(x: 10, y: 620, width: 600, height: 300)
        let hypotheticalCleanupTarget = CGRect(x: 610, y: 20, width: 600, height: 450)

        XCTAssertFalse(manager.frameIsAdjacentToCleanupSource(focusedTopLeftDestination,
                                                              sourceFrame: cycledBottomRight,
                                                              movedEdge: .top,
                                                              axis: .vertical,
                                                              tolerance: 8,
                                                              gapSize: 0))
        XCTAssertFalse(manager.cleanupDestinationAllowsSourceResize(action: .bottomRight,
                                                                    observedFrame: cycledBottomRight,
                                                                    targetFrame: hypotheticalCleanupTarget,
                                                                    focusedDestinationFrame: focusedTopLeftDestination,
                                                                    screenFrame: visibleFrame,
                                                                    axis: .vertical,
                                                                    movedEdge: .top,
                                                                    tolerance: 8,
                                                                    gapSize: 0))
    }

    func testCleanupTargetDoesNotShrinkComplementOfMinimumRestrictedAdjacent() {
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let complementaryBottomRight = CGRect(x: 610, y: 20, width: 600, height: 540)
        let minimumBandTopRight = CooperativeCornerResize.Candidate(id: 2,
                                                                    frame: CGRect(x: 610, y: 560, width: 600, height: 360))

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .bottomRight,
                                                              observedFrame: complementaryBottomRight,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .top,
                                                              tolerance: 8,
                                                              includeCycleTargets: false,
                                                              candidates: [minimumBandTopRight])

        XCTAssertNil(cleanupTarget)
    }

    func testCleanupTargetDoesNotShrinkInitialCycleSourceWithMinimumCycleAdjacent() {
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let cycledBottomLeft = CGRect(x: 10, y: 20, width: 600, height: 600)
        let selectedCycleTopLeft = CooperativeCornerResize.Candidate(id: 2,
                                                                     frame: CGRect(x: 10, y: 620, width: 600, height: 300))

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .bottomLeft,
                                                              observedFrame: cycledBottomLeft,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .top,
                                                              tolerance: 8,
                                                              includeCycleTargets: false,
                                                              candidates: [selectedCycleTopLeft])

        XCTAssertNil(cleanupTarget)
    }

    func testCleanupTargetDoesNotShrinkRepeatedCycleSourceWithMinimumCycleAdjacent() {
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let cycledBottomLeft = CGRect(x: 10, y: 20, width: 600, height: 600)
        let selectedCycleTopLeft = CooperativeCornerResize.Candidate(id: 2,
                                                                     frame: CGRect(x: 10, y: 620, width: 600, height: 300))

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .bottomLeft,
                                                              observedFrame: cycledBottomLeft,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .top,
                                                              tolerance: 8,
                                                              includeCycleTargets: true,
                                                              candidates: [selectedCycleTopLeft])

        XCTAssertNil(cleanupTarget)
    }

    func testCleanupTargetDoesNotShrinkValidCycleCornerFromOriginalLocation() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let cycledTopRight = CGRect(x: 610, y: 320, width: 600, height: 600)
        let minimumCycleBottomRight = CooperativeCornerResize.Candidate(id: 2,
                                                                        frame: CGRect(x: 610, y: 20, width: 600, height: 300))

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .topRight,
                                                              observedFrame: cycledTopRight,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .bottom,
                                                              tolerance: 8,
                                                              includeCycleTargets: false,
                                                              candidates: [minimumCycleBottomRight])

        XCTAssertNil(cleanupTarget)
    }

    func testCleanupTargetDoesNotShrinkComplementOfSelectedAdjacentCycleSize() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = [.oneHalf, .oneThird]

        let complementaryBottomLeft = CGRect(x: 10, y: 20, width: 600, height: 600)
        let selectedCycleTopLeft = CooperativeCornerResize.Candidate(id: 2,
                                                                     frame: CGRect(x: 10, y: 620, width: 600, height: 300))

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .bottomLeft,
                                                              observedFrame: complementaryBottomLeft,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .top,
                                                              tolerance: 8,
                                                              includeCycleTargets: false,
                                                              candidates: [selectedCycleTopLeft])

        XCTAssertNil(cleanupTarget)
    }

    func testCleanupTargetDoesNotShrinkBalancedCorner() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let bottomRight = CGRect(x: 610, y: 20, width: 600, height: 450)
        let balancedTopRight = CooperativeCornerResize.Candidate(id: 2,
                                                                 frame: CGRect(x: 610, y: 470, width: 600, height: 450))

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .bottomRight,
                                                              observedFrame: bottomRight,
                                                              screenFrame: visibleFrame,
                                                              axis: .vertical,
                                                              movedEdge: .top,
                                                              tolerance: 8,
                                                              includeCycleTargets: false,
                                                              candidates: [balancedTopRight])

        XCTAssertNil(cleanupTarget)
    }

    func testRepeatedCornerLookAheadSkipsExpansionWhenAdjacentIsInMinimumCycleBand() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let oldFocusedFrame = CGRect(x: 10, y: 20, width: 600, height: 540)
        let requestedTwoThirdsFrame = CGRect(x: 10, y: 20, width: 600, height: 600)
        let minimumRestrictedTop = CooperativeCornerResize.Candidate(id: 2,
                                                                     frame: CGRect(x: 10, y: 560, width: 600, height: 360))

        let lookAheadTarget = WindowManager().cycleLookAheadTargetForMinimumRestrictedAdjacent(action: .bottomLeft,
                                                                                               oldFocusedFrame: oldFocusedFrame,
                                                                                               requestedFocusedFrame: requestedTwoThirdsFrame,
                                                                                               screenFrame: visibleFrame,
                                                                                               candidates: [minimumRestrictedTop],
                                                                                               axis: .vertical,
                                                                                               movedEdge: .top,
                                                                                               tolerance: 8,
                                                                                               gapSize: 0)

        XCTAssertEqual(lookAheadTarget?.skippedCycleSize, .twoThirds)
        XCTAssertEqual(lookAheadTarget?.targetCycleSize, .oneThird)
        XCTAssertEqual(lookAheadTarget?.restrictedAdjacentId, 2)
        assertRect(lookAheadTarget?.rawFrame ?? .null, equals: CGRect(x: 10, y: 20, width: 600, height: 300))
        assertRect(lookAheadTarget?.gappedFrame ?? .null, equals: CGRect(x: 10, y: 20, width: 600, height: 300))
    }

    func testRepeatedCornerLookAheadDoesNotSkipWhenAdjacentIsAtCycleBoundary() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let oldFocusedFrame = CGRect(x: 10, y: 20, width: 600, height: 450)
        let requestedTwoThirdsFrame = CGRect(x: 10, y: 20, width: 600, height: 600)
        let halfHeightTop = CooperativeCornerResize.Candidate(id: 2,
                                                              frame: CGRect(x: 10, y: 470, width: 600, height: 450))

        let lookAheadTarget = WindowManager().cycleLookAheadTargetForMinimumRestrictedAdjacent(action: .bottomLeft,
                                                                                               oldFocusedFrame: oldFocusedFrame,
                                                                                               requestedFocusedFrame: requestedTwoThirdsFrame,
                                                                                               screenFrame: visibleFrame,
                                                                                               candidates: [halfHeightTop],
                                                                                               axis: .vertical,
                                                                                               movedEdge: .top,
                                                                                               tolerance: 8,
                                                                                               gapSize: 0)

        XCTAssertNil(lookAheadTarget)
    }

    func testRepeatedCornerLookAheadWrapsPastMaximumBlockedByMinimumRestrictedAdjacent() {
        let screenFrame = CGRect(x: 0, y: 140, width: 3200, height: 1660)
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = Set(CycleSize.allCases)
        Defaults.gapSize.value = 20
        ActiveSideSplitRatios.shared.resetAll()

        let achievedBottomLeft = CGRect(x: 20, y: 160, width: 2200, height: 1100)
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.bottomLeft,
                                                                    achievedFrame: achievedBottomLeft,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: 20)
        let cycleParams = RectCalculationParameters(window: Window(id: 1, rect: achievedBottomLeft),
                                                    visibleFrameOfScreen: screenFrame,
                                                    action: .bottomLeft,
                                                    lastAction: nil)
        let rawThreeQuarters = WindowCalculationFactory.lowerLeftCalculation.calculateFractionalRect(cycleParams,
                                                                                                      fraction: CycleSize.threeQuarters.fraction).rect
        let requestedThreeQuarters = GapCalculation.applyGaps(rawThreeQuarters,
                                                              sharedEdges: WindowAction.bottomLeft.gapSharedEdge,
                                                              gapSize: 20)
        let minimumRestrictedTop = CooperativeCornerResize.Candidate(id: 2,
                                                                     frame: CGRect(x: 20, y: 1280, width: 2200, height: 500))

        let lookAheadTarget = WindowManager().cycleLookAheadTargetForMinimumRestrictedAdjacent(action: .bottomLeft,
                                                                                               oldFocusedFrame: achievedBottomLeft,
                                                                                               requestedFocusedFrame: requestedThreeQuarters,
                                                                                               screenFrame: screenFrame,
                                                                                               candidates: [minimumRestrictedTop],
                                                                                               axis: .vertical,
                                                                                               movedEdge: .top,
                                                                                               tolerance: 24,
                                                                                               gapSize: 20)

        XCTAssertEqual(lookAheadTarget?.skippedCycleSize, .threeQuarters)
        XCTAssertEqual(lookAheadTarget?.targetCycleSize, .oneQuarter)
        XCTAssertEqual(lookAheadTarget?.gappedFrame.height ?? -1, 385, accuracy: 0.001)
    }

    func testRestrictedHeightCornerLeavingAttemptsNextSmallerCycleSize() {
        let screenFrame = CGRect(x: 0, y: 140, width: 3200, height: 1660)
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        Defaults.verticalSplitRatio.value = CycleSize.oneThird.percentValue
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = Set(CycleSize.allCases)
        Defaults.gapSize.value = 20
        ActiveSideSplitRatios.shared.resetAll()

        let minimumRestrictedTop = CGRect(x: 20, y: 1280, width: 2200, height: 500)
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(.topLeft,
                                                                    achievedFrame: minimumRestrictedTop,
                                                                    screenFrame: screenFrame,
                                                                    gapSize: 20)

        let cleanupTarget = WindowManager().cleanupTargetFrame(action: .topLeft,
                                                              observedFrame: minimumRestrictedTop,
                                                              screenFrame: screenFrame,
                                                              axis: .vertical,
                                                              movedEdge: .bottom,
                                                              tolerance: 24,
                                                              includeCycleTargets: false,
                                                              gapSize: 20)

        assertRect(cleanupTarget ?? .null, equals: CGRect(x: 20, y: 1395, width: 2200, height: 385))
    }

    func testCleanupSourceAdjacencyOnlyMatchesDirectDestination() {
        let manager = WindowManager()
        let sourceTopLeft = CGRect(x: 10, y: 400, width: 800, height: 520)
        let adjacentBottomLeft = CGRect(x: 10, y: 20, width: 800, height: 380)
        let otherBottom = CGRect(x: 810, y: 20, width: 400, height: 380)
        let sourceBottomRight = CGRect(x: 610, y: 20, width: 600, height: 540)
        let diagonalTopLeft = CGRect(x: 10, y: 560, width: 600, height: 360)

        XCTAssertTrue(manager.frameIsAdjacentToCleanupSource(adjacentBottomLeft,
                                                             sourceFrame: sourceTopLeft,
                                                             movedEdge: .bottom,
                                                             axis: .vertical,
                                                             tolerance: 8,
                                                             gapSize: 0))
        XCTAssertFalse(manager.frameIsAdjacentToCleanupSource(otherBottom,
                                                              sourceFrame: sourceTopLeft,
                                                              movedEdge: .bottom,
                                                              axis: .vertical,
                                                              tolerance: 8,
                                                              gapSize: 0))
        XCTAssertFalse(manager.frameIsAdjacentToCleanupSource(adjacentBottomLeft,
                                                              sourceFrame: sourceTopLeft,
                                                              movedEdge: .right,
                                                              axis: .vertical,
                                                              tolerance: 8,
                                                              gapSize: 0))
        XCTAssertFalse(manager.frameIsAdjacentToCleanupSource(diagonalTopLeft,
                                                              sourceFrame: sourceBottomRight,
                                                              movedEdge: .top,
                                                              axis: .vertical,
                                                              tolerance: 8,
                                                              gapSize: 0))
    }

    func testRepeatedCornersWithVerticalExpansionCycleHeightOnly() {
        setSplitRatio(60)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        assertRepeatedCornerRects(
            topLeft: CGRect(x: 10, y: 320, width: 720, height: 600),
            topRight: CGRect(x: 730, y: 320, width: 480, height: 600),
            bottomLeft: CGRect(x: 10, y: 20, width: 720, height: 600),
            bottomRight: CGRect(x: 730, y: 20, width: 480, height: 600)
        )
    }

    func testRepeatedHalfActionsStillCycleOnTheirNaturalAxis() {
        setSplitRatio(60)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        assertRect(WindowCalculationFactory.leftHalfCalculation.calculateRepeatedRect(repeatedParams(for: .leftHalf)).rect,
                   equals: CGRect(x: 10, y: 20, width: 800, height: 900))
        assertRect(WindowCalculationFactory.rightHalfCalculation.calculateRepeatedRect(repeatedParams(for: .rightHalf)).rect,
                   equals: CGRect(x: 410, y: 20, width: 800, height: 900))

        Defaults.cornerCycleExpansionAxis.value = .horizontal

        assertRect(WindowCalculationFactory.topHalfCalculation.calculateRect(repeatedParams(for: .topHalf)).rect,
                   equals: CGRect(x: 10, y: 320, width: 1200, height: 600))
        assertRect(WindowCalculationFactory.bottomHalfCalculation.calculateRect(repeatedParams(for: .bottomHalf)).rect,
                   equals: CGRect(x: 10, y: 20, width: 1200, height: 600))
    }

    func testRepeatedHalfActionStartsAtFirstSelectedCycleSizeWhenOneHalfIsDeselected() {
        setSplitRatio(50)
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = [.oneThird, .twoThirds]

        let firstRepeatedRect = WindowCalculationFactory.bottomHalfCalculation.calculateRepeatedRect(repeatedParams(for: .bottomHalf)).rect
        let secondRepeatedRect = WindowCalculationFactory.bottomHalfCalculation.calculateRepeatedRect(repeatedParams(for: .bottomHalf, currentRect: firstRepeatedRect, count: 2)).rect

        assertRect(firstRepeatedRect, equals: CGRect(x: 10, y: 20, width: 1200, height: 600))
        assertRect(secondRepeatedRect, equals: CGRect(x: 10, y: 20, width: 1200, height: 300))
    }

    func testRepeatedBottomCornerStartsAtFirstSelectedCycleSizeWhenOneHalfIsDeselected() {
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = [.oneThird, .twoThirds]

        let firstRect = WindowCalculationFactory.lowerLeftCalculation.calculateRect(params(for: .bottomLeft)).rect
        let firstRepeatedRect = WindowCalculationFactory.lowerLeftCalculation.calculateRect(repeatedParams(for: .bottomLeft, currentRect: firstRect)).rect
        let secondRepeatedRect = WindowCalculationFactory.lowerLeftCalculation.calculateRect(repeatedParams(for: .bottomLeft, currentRect: firstRepeatedRect, count: 2)).rect

        assertRect(firstRect, equals: CGRect(x: 10, y: 20, width: 600, height: 450))
        assertRect(firstRepeatedRect, equals: CGRect(x: 10, y: 20, width: 600, height: 600))
        assertRect(secondRepeatedRect, equals: CGRect(x: 10, y: 20, width: 600, height: 300))
    }

    func testRepeatedSideShortcutAdvancesWhenCurrentFrameMatchesSplitRatioCycleSize() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        setSplitRatio(CycleSize.twoThirds.percentValue)

        let leftFrame = WindowCalculationFactory.leftHalfCalculation.calculateRect(params(for: .leftHalf)).rect
        let repeatedLeftFrame = WindowCalculationFactory.leftHalfCalculation.calculateRepeatedRect(repeatedParams(for: .leftHalf, currentRect: leftFrame)).rect

        assertRect(leftFrame, equals: CGRect(x: 10, y: 20, width: 800, height: 900))
        assertRect(repeatedLeftFrame, equals: CGRect(x: 10, y: 20, width: 400, height: 900))
    }

    func testRepeatedTopShortcutAdvancesWhenCurrentFrameMatchesSplitRatioCycleSize() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        setSplitRatio(CycleSize.twoThirds.percentValue)

        let topFrame = WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf)).rect
        let repeatedTopFrame = WindowCalculationFactory.topHalfCalculation.calculateRepeatedRect(repeatedParams(for: .topHalf, currentRect: topFrame)).rect

        assertRect(topFrame, equals: CGRect(x: 10, y: 320, width: 1200, height: 600))
        assertRect(repeatedTopFrame, equals: CGRect(x: 10, y: 620, width: 1200, height: 300))
    }

    func testRepeatedRightShortcutUpdatesActiveSplitForSubsequentCorners() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        Defaults.verticalSplitRatio.value = 50
        ActiveSideSplitRatios.shared.resetAll()

        let firstRightFrame = WindowCalculationFactory.rightHalfCalculation.calculateRect(params(for: .rightHalf)).rect
        let repeatedRightFrame = WindowCalculationFactory.rightHalfCalculation.calculateRepeatedRect(repeatedParams(for: .rightHalf,
                                                                                                                    currentRect: firstRightFrame)).rect

        ActiveSideSplitRatios.shared.recordSideAction(.rightHalf,
                                                      targetFrame: repeatedRightFrame,
                                                      screenFrame: visibleFrame)

        let topRightFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(params(for: .topRight)).rect
        let topLeftFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect

        assertRect(firstRightFrame, equals: CGRect(x: 810, y: 20, width: 400, height: 900))
        assertRect(repeatedRightFrame, equals: CGRect(x: 410, y: 20, width: 800, height: 900))
        assertRect(topRightFrame, equals: CGRect(x: 410, y: 470, width: 800, height: 450))
        assertRect(topLeftFrame, equals: CGRect(x: 10, y: 470, width: 400, height: 450))
        XCTAssertEqual(Defaults.horizontalSplitRatio.value, CycleSize.twoThirds.percentValue, accuracy: 0.001)
    }

    func testRepeatedBottomShortcutUpdatesActiveSplitForSubsequentCorners() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = CycleSize.twoThirds.percentValue
        ActiveSideSplitRatios.shared.resetAll()

        let firstBottomFrame = WindowCalculationFactory.bottomHalfCalculation.calculateRect(params(for: .bottomHalf)).rect
        let repeatedBottomFrame = WindowCalculationFactory.bottomHalfCalculation.calculateRepeatedRect(repeatedParams(for: .bottomHalf,
                                                                                                                      currentRect: firstBottomFrame)).rect

        ActiveSideSplitRatios.shared.recordSideAction(.bottomHalf,
                                                      targetFrame: repeatedBottomFrame,
                                                      screenFrame: visibleFrame)

        let bottomRightFrame = WindowCalculationFactory.lowerRightCalculation.calculateRect(params(for: .bottomRight)).rect
        let topRightFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(params(for: .topRight)).rect

        assertRect(firstBottomFrame, equals: CGRect(x: 10, y: 20, width: 1200, height: 300))
        assertRect(repeatedBottomFrame, equals: CGRect(x: 10, y: 20, width: 1200, height: 600))
        assertRect(bottomRightFrame, equals: CGRect(x: 610, y: 20, width: 600, height: 600))
        assertRect(topRightFrame, equals: CGRect(x: 610, y: 620, width: 600, height: 300))
        XCTAssertEqual(Defaults.verticalSplitRatio.value, CycleSize.twoThirds.percentValue, accuracy: 0.001)
    }

    func testActiveSideSplitIsScopedToDisplayFrame() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        ActiveSideSplitRatios.shared.resetAll()

        let cycledRightFrame = CGRect(x: 410, y: 20, width: 800, height: 900)
        let otherDisplayFrame = CGRect(x: 2000, y: 20, width: 1200, height: 900)

        ActiveSideSplitRatios.shared.recordSideAction(.rightHalf,
                                                      targetFrame: cycledRightFrame,
                                                      screenFrame: visibleFrame)

        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: visibleFrame),
                       CycleSize.oneThird.fraction,
                       accuracy: 0.001)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: otherDisplayFrame),
                       CycleSize.twoThirds.fraction,
                       accuracy: 0.001)
    }

    func testChangingSavedSplitRatioResetsActiveRuntimeSplit() {
        Defaults.horizontalSplitRatio.value = CycleSize.twoThirds.percentValue
        ActiveSideSplitRatios.shared.resetAll()
        ActiveSideSplitRatios.shared.recordSideAction(.rightHalf,
                                                      targetFrame: CGRect(x: 410, y: 20, width: 800, height: 900),
                                                      screenFrame: visibleFrame)

        Defaults.horizontalSplitRatio.value = 50

        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: visibleFrame), 0.5, accuracy: 0.001)
    }

    func testHorizontalCornerShortcutCanCycleAfterCompatibleSideShortcut() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .horizontal

        let leftFrame = WindowCalculationFactory.leftHalfCalculation.calculateRect(params(for: .leftHalf)).rect
        let topLeftFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(RectCalculationParameters(window: Window(id: 1, rect: leftFrame),
                                                                                                                visibleFrameOfScreen: visibleFrame,
                                                                                                                action: .topLeft,
                                                                                                                lastAction: RectangleAction(action: .leftHalf,
                                                                                                                                            subAction: nil,
                                                                                                                                            rect: leftFrame,
                                                                                                                                            count: 1))).rect

        assertRect(topLeftFrame, equals: CGRect(x: 10, y: 470, width: 800, height: 450))
    }

    func testVerticalCornerShortcutCanCycleAfterCompatibleSideShortcut() {
        guard Defaults.cooperativeCornerResize.enabled else { return }
        setSplitRatio(50)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let topFrame = WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf)).rect
        let topLeftFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(RectCalculationParameters(window: Window(id: 1, rect: topFrame),
                                                                                                                visibleFrameOfScreen: visibleFrame,
                                                                                                                action: .topLeft,
                                                                                                                lastAction: RectangleAction(action: .topHalf,
                                                                                                                                            subAction: nil,
                                                                                                                                            rect: topFrame,
                                                                                                                                            count: 1))).rect

        assertRect(topLeftFrame, equals: CGRect(x: 10, y: 320, width: 600, height: 600))
    }

    func testDifferentTopCornerShortcutDoesNotTriggerVerticalExpansionCycleAtOneThirdSplit() {
        setSplitRatio(CycleSize.oneThird.percentValue)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let topLeftFrame = WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect
        let topRightFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(RectCalculationParameters(window: Window(id: 1, rect: topLeftFrame),
                                                                                                                  visibleFrameOfScreen: visibleFrame,
                                                                                                                  action: .topRight,
                                                                                                                  lastAction: RectangleAction(action: .topLeft,
                                                                                                                                              subAction: nil,
                                                                                                                                              rect: topLeftFrame,
                                                                                                                                              count: 1))).rect

        assertRect(topLeftFrame, equals: CGRect(x: 10, y: 620, width: 400, height: 300))
        assertRect(topRightFrame, equals: CGRect(x: 410, y: 620, width: 800, height: 300))
    }

    func testRepeatedHalfActionWithNoCycleSizesSelectedUsesFirstRect() {
        setSplitRatio(60)
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = []

        assertRect(WindowCalculationFactory.leftHalfCalculation.calculateRepeatedRect(repeatedParams(for: .leftHalf)).rect,
                   equals: CGRect(x: 10, y: 20, width: 720, height: 900))
    }

    func testRepeatedCornerActionWithNoCycleSizesSelectedUsesFirstRect() {
        setSplitRatio(60)
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = []

        let firstRect = WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect
        let repeatedRect = WindowCalculationFactory.upperLeftCalculation.calculateRect(repeatedParams(for: .topLeft, currentRect: firstRect)).rect

        assertRect(repeatedRect, equals: firstRect)
    }
    
    private func setSplitRatio(_ percent: Float) {
        Defaults.horizontalSplitRatio.value = percent
        Defaults.verticalSplitRatio.value = percent
    }
    
    private func assertCornerRects(topLeft: CGRect, topRight: CGRect, bottomLeft: CGRect, bottomRight: CGRect) {
        assertRect(WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect, equals: topLeft)
        assertRect(WindowCalculationFactory.upperRightCalculation.calculateRect(params(for: .topRight)).rect, equals: topRight)
        assertRect(WindowCalculationFactory.lowerLeftCalculation.calculateRect(params(for: .bottomLeft)).rect, equals: bottomLeft)
        assertRect(WindowCalculationFactory.lowerRightCalculation.calculateRect(params(for: .bottomRight)).rect, equals: bottomRight)
    }

    private func assertRepeatedCornerRects(topLeft: CGRect, topRight: CGRect, bottomLeft: CGRect, bottomRight: CGRect) {
        let topLeftBase = WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect
        let topRightBase = WindowCalculationFactory.upperRightCalculation.calculateRect(params(for: .topRight)).rect
        let bottomLeftBase = WindowCalculationFactory.lowerLeftCalculation.calculateRect(params(for: .bottomLeft)).rect
        let bottomRightBase = WindowCalculationFactory.lowerRightCalculation.calculateRect(params(for: .bottomRight)).rect

        assertRect(WindowCalculationFactory.upperLeftCalculation.calculateRect(repeatedParams(for: .topLeft, currentRect: topLeftBase)).rect, equals: topLeft)
        assertRect(WindowCalculationFactory.upperRightCalculation.calculateRect(repeatedParams(for: .topRight, currentRect: topRightBase)).rect, equals: topRight)
        assertRect(WindowCalculationFactory.lowerLeftCalculation.calculateRect(repeatedParams(for: .bottomLeft, currentRect: bottomLeftBase)).rect, equals: bottomLeft)
        assertRect(WindowCalculationFactory.lowerRightCalculation.calculateRect(repeatedParams(for: .bottomRight, currentRect: bottomRightBase)).rect, equals: bottomRight)
    }
    
    private func params(for action: WindowAction) -> RectCalculationParameters {
        RectCalculationParameters(window: Window(id: 1, rect: visibleFrame),
                                  visibleFrameOfScreen: visibleFrame,
                                  action: action,
                                  lastAction: nil)
    }

    private func repeatedParams(for action: WindowAction, currentRect: CGRect? = nil, count: Int = 1) -> RectCalculationParameters {
        RectCalculationParameters(window: Window(id: 1, rect: currentRect ?? visibleFrame),
                                  visibleFrameOfScreen: visibleFrame,
                                  action: action,
                                  lastAction: RectangleAction(action: action,
                                                              subAction: nil,
                                                              rect: currentRect ?? visibleFrame,
                                                              count: count))
    }
    
    private func assertRect(_ rect: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 0.001, file: file, line: line)
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

final class WindowDragGeometryTests: XCTestCase {
    private let initial = CGRect(x: -1983, y: -964, width: 1920, height: 1016)

    func testDetectsMovementWhileAccessibilityStillReportsTheInitialFrame() throws {
        let moved = initial.offsetBy(dx: 0, dy: 2)
        var accessibilityReads = 0
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: initial,
                                                        serverFrame: moved, accessibilityFrame: {
            accessibilityReads += 1
            return self.initial
        }))
        XCTAssertTrue(geometry.isMoving)
        XCTAssertTrue(geometry.movedWithoutResizing)
        XCTAssertEqual(geometry.currentFrame, moved)
        XCTAssertEqual(accessibilityReads, 0)
    }

    func testDifferentCoordinateSourcesDoNotCreateFalseMovement() throws {
        let accessibility = initial.offsetBy(dx: 1, dy: 1)
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: accessibility, initialServerFrame: initial,
                                                        serverFrame: initial, accessibilityFrame: { accessibility }))
        XCTAssertFalse(geometry.isMoving)
        XCTAssertFalse(geometry.isResizing)
    }

    func testUnavailableServerFrameFallsBackToAccessibilityBaseline() throws {
        let accessibility = initial.offsetBy(dx: 1, dy: 1)
        for unavailable in [nil, CGRect.null, CGRect.zero] as [CGRect?] {
            let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: accessibility, initialServerFrame: initial,
                                                            serverFrame: unavailable, accessibilityFrame: { accessibility }))
            XCTAssertFalse(geometry.isMoving)
            XCTAssertEqual(geometry.currentFrame, accessibility)
        }
    }

    func testServerFrameWithoutServerBaselineUsesAccessibility() throws {
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: nil,
                                                        serverFrame: initial.offsetBy(dx: 20, dy: 20),
                                                        accessibilityFrame: { self.initial }))
        XCTAssertFalse(geometry.isMoving)
    }

    func testResizingFromEitherCornerDoesNotTriggerRestore() throws {
        let frames = [CGRect(x: initial.minX, y: initial.minY, width: 1800, height: 900),
                      CGRect(x: initial.minX + 120, y: initial.minY + 100, width: 1800, height: 916)]
        for frame in frames {
            let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: initial,
                                                            serverFrame: frame, accessibilityFrame: { nil }))
            XCTAssertTrue(geometry.isResizing)
            XCTAssertFalse(geometry.isMoving)
            XCTAssertFalse(geometry.movedWithoutResizing)
        }
    }

    func testMovingAndChangingSizeAcrossDisplaysStillCountsAsMovement() throws {
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: initial,
                                                        serverFrame: CGRect(x: 20, y: 30, width: 1400, height: 800),
                                                        accessibilityFrame: { nil }))
        XCTAssertTrue(geometry.isMoving)
        XCTAssertFalse(geometry.movedWithoutResizing)
    }

    func testMissingGeometryDoesNotCreateADrag() {
        XCTAssertNil(WindowDragGeometry(initialFrame: initial, initialServerFrame: nil,
                                        serverFrame: nil, accessibilityFrame: { nil }))
        XCTAssertNil(WindowDragGeometry(initialFrame: initial, initialServerFrame: nil,
                                        serverFrame: nil, accessibilityFrame: { .null }))
    }
}

final class DragRestorePlacementTests: XCTestCase {
    private let current = CGRect(x: -1983, y: -950, width: 1920, height: 1016)
    private let size = CGSize(width: 1100, height: 650)

    func testDisplayedFrameUsesTheOriginalGrabOffsetInsteadOfANewerMouseSample() {
        let initial = CGRect(x: -1983, y: -964, width: 1920, height: 1016)
        let displayed = initial.offsetBy(dx: 0, dy: 38)
        let reference = DragRestorePlacement.referenceCursor(current: displayed, initial: initial,
                                                              mouseDown: CGPoint(x: -255, y: -934),
                                                              fallback: CGPoint(x: -255, y: -858))
        XCTAssertEqual(reference, CGPoint(x: -255, y: -896))
        XCTAssertEqual(reference.y - displayed.minY, 30)
    }

    func testMissingMouseDownUsesTheAvailableCursorSample() {
        let cursor = CGPoint(x: -561, y: -920)
        XCTAssertEqual(DragRestorePlacement.referenceCursor(current: current, initial: current,
                                                            mouseDown: nil, fallback: cursor), cursor)
    }

    func testLeftGrabKeepsNativePosition() {
        let restored = DragRestorePlacement.frame(from: current, size: size, cursor: CGPoint(x: -1600, y: -920))
        XCTAssertEqual(restored.origin, current.origin)
        XCTAssertEqual(restored.size, size)
    }

    func testRightGrabMovesOnlyEnoughToKeepThePointerInside() {
        let cursor = CGPoint(x: -561, y: -920)
        let restored = DragRestorePlacement.frame(from: current, size: size, cursor: cursor)
        XCTAssertEqual(restored.minX, -1629)
        XCTAssertEqual(restored.maxX - cursor.x, 32)
        XCTAssertTrue(restored.contains(cursor))
        XCTAssertLessThan(restored.maxX, current.maxX)
    }

    func testNearbyGrabPointsDoNotSwitchToTheFarRightEdge() {
        let cutoff = current.minX + size.width - 32
        let left = DragRestorePlacement.frame(from: current, size: size, cursor: CGPoint(x: cutoff - 1, y: -920))
        let right = DragRestorePlacement.frame(from: current, size: size, cursor: CGPoint(x: cutoff + 1, y: -920))
        XCTAssertEqual(left.minX, current.minX)
        XCTAssertEqual(right.minX - left.minX, 1)
    }

    func testGrabAtTheFarRightDoesNotPushPastTheOriginalEdge() {
        let restored = DragRestorePlacement.frame(from: current, size: size,
                                                  cursor: CGPoint(x: current.maxX - 1, y: -920))
        XCTAssertEqual(restored.maxX, current.maxX)
    }

    func testGrowingFromAHalfScreenDoesNotReposition() {
        let half = CGRect(x: 400, y: 100, width: 800, height: 900)
        let restored = DragRestorePlacement.frame(from: half, size: size, cursor: CGPoint(x: 1190, y: 130))
        XCTAssertEqual(restored.origin, half.origin)
    }

    func testPlacementIsTheSameRelativeToEitherDisplay() {
        let cursor = CGPoint(x: -561, y: -920)
        let external = DragRestorePlacement.frame(from: current, size: size, cursor: cursor)
        let local = DragRestorePlacement.frame(from: current.offsetBy(dx: 2000, dy: 1000), size: size,
                                               cursor: CGPoint(x: cursor.x + 2000, y: cursor.y + 1000))
        XCTAssertEqual(local, external.offsetBy(dx: 2000, dy: 1000))
        XCTAssertEqual(DragRestorePlacement.frame(from: current, size: size, cursor: nil).origin, current.origin)
    }
}

final class DragRestoreReleaseTests: XCTestCase {
    private final class WindowElement: WindowAnimationElement {
        var currentFrame = CGRect(x: 120, y: 120, width: 800, height: 600)
        var writes: [CGRect] = []
        override var frame: CGRect { currentFrame }
        override func beginAnimatedAdjustment() -> () -> Void { {} }
        override func setAnimationFrame(_ frame: CGRect, resizeOnly: Bool = false) -> Bool { true }
        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: WindowAnimationPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            currentFrame.size = frame.size
            if adjustPosition { currentFrame.origin = frame.origin }
            writes.append(currentFrame)
        }
    }

    private final class Manager: SnappingManager {
        var restores = 0
        override func unsnapRestore(windowId: CGWindowID, currentRect: CGRect, cursorLoc: CGPoint?) {
            restores += 1
        }
        override func snapAreaContainingCursor(priorSnapArea: SnapArea?, at loc: CGPoint) -> SnapArea? { nil }
    }

    private func release(dragAlreadyDetected: Bool) throws -> Manager {
        let saved = Defaults.windowSnapping.enabled
        Defaults.windowSnapping.enabled = false
        defer { Defaults.windowSnapping.enabled = saved }
        let manager = Manager()
        manager.windowElement = WindowElement(AXUIElementCreateSystemWide())
        manager.windowId = .max
        manager.initialWindowRect = CGRect(x: 100, y: 100, width: 800, height: 600)
        manager.windowMoving = dragAlreadyDetected
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                                                   timestamp: 1, windowNumber: 0, context: nil,
                                                   eventNumber: 1, clickCount: 1, pressure: 0))
        manager.handle(event: event)
        return manager
    }

    func testMouseUpDoesNotRestoreAgainWhenDisplayedSizeHasNotCaughtUp() throws {
        let manager = try release(dragAlreadyDetected: true)
        XCTAssertEqual(manager.restores, 0)
        XCTAssertFalse(manager.windowMoving)
        XCTAssertNil(manager.windowId)
        XCTAssertNil(manager.windowElement)
    }

    func testMouseUpStillRestoresAQuickDragThatHadNotBeenDetected() throws {
        let manager = try release(dragAlreadyDetected: false)
        XCTAssertEqual(manager.restores, 1)
        XCTAssertFalse(manager.windowMoving)
        XCTAssertNil(manager.initialWindowRect)
    }

    func testDirectAnimationWithoutServerIdentityCompletesOnceAndMouseUpDoesNotRepeatIt() throws {
        let animator = DirectWindowAnimator(enabled: { true }, automaticallyAdvances: false, environmentIsSafe: { true })
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer {
            animator.finish()
            Defaults.experimentalWindowAnimations.enabled = saved
        }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by accessibility settings")
        let window = WindowElement(AXUIElementCreateSystemWide())
        XCTAssertNil(window.windowId, "Direct animation does not require a WindowServer identity")
        let destination = CGRect(x: 300, y: 120, width: 500, height: 400)
        var completedFrames: [CGRect] = []
        animator.animate(window, to: destination, duration: 0.18, resizeOnly: false, placement: nil, offset: { .zero }) { completedFrames.append($0) }

        XCTAssertTrue(completedFrames.isEmpty)
        XCTAssertEqual(animator.destination(for: window), destination)
        animator.finish()
        XCTAssertEqual(completedFrames, [destination])
        XCTAssertNil(animator.destination(for: window))

        let manager = try release(dragAlreadyDetected: true)

        XCTAssertEqual(completedFrames, [destination], "A later native release must not repeat the completed animation")
        XCTAssertEqual(manager.restores, 0)
        XCTAssertNil(animator.destination(for: window))
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

        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !sm.isFullScreen }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 3), .completed)
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

class SnappingManagerUnsnapRestoreTests: XCTestCase {

    private let windowId = CGWindowID(918_273)
    private var savedSnappingEnabled: Bool?
    private var savedUnsnapRestore: Bool?
    private var savedUnsnapRestoreFromSizeChange: Bool?
    private var savedRestoreRects = [CGWindowID: CGRect]()
    private var savedActions = [CGWindowID: RectangleAction]()

    override func setUp() {
        super.setUp()
        savedSnappingEnabled = Defaults.windowSnapping.enabled
        savedUnsnapRestore = Defaults.unsnapRestore.enabled
        savedUnsnapRestoreFromSizeChange = Defaults.unsnapRestoreFromSizeChange.enabled
        savedRestoreRects = AppDelegate.windowHistory.restoreRects
        savedActions = AppDelegate.windowHistory.lastRectangleActions
        Defaults.windowSnapping.enabled = false
        Defaults.unsnapRestore.enabled = true
        AppDelegate.windowHistory.restoreRects.removeValue(forKey: windowId)
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
    }

    override func tearDown() {
        Defaults.windowSnapping.enabled = savedSnappingEnabled
        Defaults.unsnapRestore.enabled = savedUnsnapRestore
        Defaults.unsnapRestoreFromSizeChange.enabled = savedUnsnapRestoreFromSizeChange
        AppDelegate.windowHistory.restoreRects = savedRestoreRects
        AppDelegate.windowHistory.lastRectangleActions = savedActions
        super.tearDown()
    }

    func testSuppressedSizeChangeRestoreKeepsTheUserPositionedRect() {
        Defaults.unsnapRestoreFromSizeChange.enabled = false
        let userRect = CGRect(x: 164, y: 73, width: 1414, height: 861)
        let smallerRect = CGRect(x: 179, y: 88, width: 1354, height: 801)
        AppDelegate.windowHistory.restoreRects[windowId] = userRect
        AppDelegate.windowHistory.lastRectangleActions[windowId] = RectangleAction(action: .smaller,
                                                                                   subAction: nil,
                                                                                   rect: smallerRect,
                                                                                   count: 2)
        let snappingManager = SnappingManager()
        snappingManager.initialWindowRect = smallerRect

        snappingManager.unsnapRestore(windowId: windowId,
                                      currentRect: smallerRect.offsetBy(dx: 40, dy: 0),
                                      cursorLoc: nil)

        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[windowId], userRect)
    }

    func testDraggingAWindowRectangleDidNotPlaceRecordsTheRestoreRect() {
        let draggedFrom = CGRect(x: 100, y: 100, width: 800, height: 600)
        let snappingManager = SnappingManager()
        snappingManager.initialWindowRect = draggedFrom

        snappingManager.unsnapRestore(windowId: windowId,
                                      currentRect: draggedFrom.offsetBy(dx: 40, dy: 0),
                                      cursorLoc: nil)

        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[windowId], draggedFrom)
    }
}

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
        let notificationCenter: NotificationCenter
        let workspaceNotificationCenter: NotificationCenter
        let shortcuts: ValueBox<[WindowAction: MASShortcut]>
        let appDisabled: ValueBox<Bool>
        let scheduler: SchedulerSpy
        let todoSessionStates: ValueBox<[Bool]>
    }

    private func shortcut(_ keyCode: Int) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: [.command, .option])
    }

    private func makeHarness(
        initiallyActive: Bool = true,
        appDisabled: Bool = false,
        shortcuts: [WindowAction: MASShortcut]? = nil
    ) -> Harness {
        let bindingStore = BindingStoreSpy()
        let notificationCenter = NotificationCenter()
        let workspaceNotificationCenter = NotificationCenter()
        let shortcuts = ValueBox(shortcuts ?? [.leftHalf: shortcut(1)])
        let appDisabled = ValueBox(appDisabled)
        let scheduler = SchedulerSpy()
        let todoSessionStates = ValueBox<[Bool]>([])
        let manager = ShortcutManager(
            windowManager: WindowManager(),
            bindingStore: bindingStore,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            shortcutsProvider: { shortcuts.value },
            activeStateProvider: { initiallyActive },
            appDisabledProvider: { appDisabled.value },
            scheduler: { scheduler.schedule($0) },
            todoSessionStateChanged: { todoSessionStates.value.append($0) }
        )

        return Harness(
            manager: manager,
            bindingStore: bindingStore,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            shortcuts: shortcuts,
            appDisabled: appDisabled,
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

class WindowAnimationPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 29, width: 1403, height: 869)

    private func placement(for zone: CGRect, screen: CGRect? = nil) -> WindowAnimationPlacement {
        let screen = screen ?? self.screen
        return WindowAnimationPlacement(screenFrame: screen, sharedEdges: zone.sharedEdges(withRect: screen),
                                        constrainToScreen: true, gap: 0)
    }

    func testMinimumSizeKeepsEverySelectedEdgeAndCorner() {
        let cases: [(CGRect, CGSize, CGPoint)] = [
            (CGRect(x: 702, y: 29, width: 701, height: 869), CGSize(width: 913, height: 869), CGPoint(x: 490, y: 29)),
            (CGRect(x: 0, y: 29, width: 701, height: 869), CGSize(width: 913, height: 869), CGPoint(x: 0, y: 29)),
            (CGRect(x: 0, y: 29, width: 1403, height: 434), CGSize(width: 1403, height: 600), CGPoint(x: 0, y: 29)),
            (CGRect(x: 0, y: 464, width: 1403, height: 434), CGSize(width: 1403, height: 600), CGPoint(x: 0, y: 298)),
            (CGRect(x: 0, y: 29, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 0, y: 29)),
            (CGRect(x: 702, y: 29, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 490, y: 29)),
            (CGRect(x: 0, y: 464, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 0, y: 298)),
            (CGRect(x: 702, y: 464, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 490, y: 298))
        ]
        for (zone, size, expected) in cases {
            let result = placement(for: zone).frame(for: zone, actualSize: size, origin: screen, progress: 1)
            XCTAssertEqual(result.origin, expected)
            XCTAssertEqual(result.size, size)
        }
    }

    func testWidthLimitDoesNotReverseMotionOrJumpAtTheEnd() {
        let origin = CGRect(x: 100, y: 100, width: 1100, height: 650)
        let target = CGRect(x: 702, y: 29, width: 701, height: 869)
        let placement = placement(for: target)
        var previous = origin
        for step in 1...100 {
            let t = CGFloat(step) / 100
            let requested = CGRect(x: origin.minX + (target.minX - origin.minX) * t,
                                   y: origin.minY + (target.minY - origin.minY) * t,
                                   width: origin.width + (target.width - origin.width) * t,
                                   height: origin.height + (target.height - origin.height) * t)
            let result = placement.frame(for: requested, actualSize: CGSize(width: max(913, requested.width), height: requested.height),
                                         origin: origin, progress: t)
            XCTAssertGreaterThanOrEqual(result.minX, previous.minX - 0.001)
            XCTAssertLessThan(abs(result.minX - previous.minX), 7)
            previous = result
        }
        XCTAssertEqual(previous.minX, 490, accuracy: 0.001)
    }

    func testMaximumAndAspectRatioSizesKeepTheRightEdgeAndVerticalCenter() {
        let target = CGRect(x: 702, y: 29, width: 701, height: 869)
        for size in [CGSize(width: 600, height: 400), CGSize(width: 600, height: 450)] {
            let result = placement(for: target).frame(for: target, actualSize: size, origin: screen, progress: 1)
            XCTAssertEqual(result.maxX, screen.maxX)
            XCTAssertEqual(result.midY, screen.midY, accuracy: 0.5)
            XCTAssertEqual(result.size, size)
        }
    }

    func testCenteredLayoutCentersBothConstrainedDimensions() {
        let target = CGRect(x: 351, y: 129, width: 702, height: 669)
        let result = placement(for: target).frame(for: target, actualSize: CGSize(width: 913, height: 400), origin: screen, progress: 1)
        XCTAssertEqual(result.midX, target.midX, accuracy: 0.5)
        XCTAssertEqual(result.midY, target.midY, accuracy: 0.5)
    }

    func testDockInsetsAndNegativeDisplayCoordinatesUseTheProvidedWorkArea() {
        let screens = [CGRect(x: 45, y: 29, width: 1395, height: 869), screen,
                       CGRect(x: 0, y: 29, width: 1440, height: 831),
                       CGRect(x: -1600, y: -870, width: 1600, height: 900)]
        for screen in screens {
            let target = CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)
            let result = placement(for: target, screen: screen).frame(for: target, actualSize: CGSize(width: 913, height: 600), origin: screen, progress: 1)
            XCTAssertEqual(result.maxX, screen.maxX)
            XCTAssertEqual(result.midY, screen.midY, accuracy: 0.5)
        }
    }

    func testInitiallyOutOfBoundsWindowIsNotClippedOnItsFirstFrame() {
        let origin = CGRect(x: 600, y: 29, width: 913, height: 700)
        let target = CGRect(x: 702, y: 29, width: 701, height: 869)
        let placement = placement(for: target)
        XCTAssertEqual(placement.frame(for: origin, actualSize: origin.size, origin: origin, progress: 0), origin)
        let final = placement.frame(for: target, actualSize: CGSize(width: 913, height: 869), origin: origin, progress: 1)
        XCTAssertEqual(final.maxX, screen.maxX)
    }

    func testGapCorrectionMatchesNormalWindowBounds() {
        let result = WindowFrameBounds.constrained(CGRect(x: 1000, y: 0, width: 600, height: 500), to: screen, gap: 10)
        XCTAssertEqual(result.origin, CGPoint(x: 793, y: 39))
        XCTAssertTrue(WindowFrameBounds.constrained(.null, to: screen, gap: 10).isNull)
    }

    func testFinalFrameIsAppliedBeforeCleanupAndOnlyOnce() {
        var events: [String] = []
        let destination = CGRect(x: 700, y: 29, width: 700, height: 869)
        let animation = WindowFrameAnimation(from: .zero, to: destination, startTime: 0, duration: 0.34,
                                             write: { _, _ in events.append("tick"); return true },
                                             finalize: { frame in XCTAssertEqual(frame, destination); events.append("final") },
                                             cleanup: { events.append("cleanup") },
                                             completion: { _ in events.append("completion") })
        animation.tick(at: 0.1)
        animation.tick(at: 0.5)
        animation.finish()
        XCTAssertEqual(events, ["tick", "final", "cleanup", "completion"])
    }

    func testCancellationDoesNotWriteTheDestination() {
        var events: [String] = []
        let animation = WindowFrameAnimation(from: .zero, to: screen, startTime: 0, duration: 0.34,
                                             write: { _, _ in true },
                                             finalize: { _ in events.append("final") },
                                             cleanup: { events.append("cleanup") },
                                             completion: { _ in events.append("completion") })
        animation.cancel()
        animation.finish()
        XCTAssertEqual(events, ["cleanup"])
    }
}

class ClampedWindowAlignerTests: XCTestCase {

    // AX coordinates: minY is the visual top. Edge names follow CGRect.sharedEdges.
    private let screenFrame = CGRect(x: 0, y: 0, width: 2000, height: 1200)

    func testRightHalfClampedBothAxesAnchorsRightCentersVertically() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 600, height: 800) // narrower + shorter than zone
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 1400, accuracy: 0.001) // zone.maxX - width = 2000 - 600
        XCTAssertEqual(result.origin.y, 200, accuracy: 0.001)  // centered: (1200 - 800)/2
        XCTAssertEqual(result.width, 600, accuracy: 0.001)
        XCTAssertEqual(result.height, 800, accuracy: 0.001)
    }

    func testRightHalfFullHeightLeavesVerticalUntouched() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 600, height: 1200) // fills height
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 1400, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 0, accuracy: 0.001)
    }

    func testLeftHalfClampedAnchorsLeftCentersVertically() {
        let zone = CGRect(x: 0, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 0, y: 0, width: 600, height: 800)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(result.origin.y, 200, accuracy: 0.001)
    }

    func testBottomRightQuarterAnchorsToCorner() {
        let zone = CGRect(x: 1000, y: 600, width: 1000, height: 600)
        let window = CGRect(x: 1000, y: 600, width: 600, height: 400)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 1400, accuracy: 0.001) // maxX - width
        XCTAssertEqual(result.origin.y, 800, accuracy: 0.001)  // maxY - height = 1200 - 400
    }

    func testInteriorZoneCentersBothAxes() {
        let zone = CGRect(x: 600, y: 400, width: 800, height: 400)
        let window = CGRect(x: 600, y: 400, width: 400, height: 200)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 800, accuracy: 0.001) // (800-400)/2 + 600
        XCTAssertEqual(result.origin.y, 500, accuracy: 0.001) // (400-200)/2 + 400
    }

    func testExactFitReturnsUnchanged() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = zone
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertTrue(result.equalTo(window))
    }

    // A maximize against a Dock on the right comes back a point narrow (see #1852). Centering
    // that shortfall would put the window at x=1 and leave a visible gap on the left edge.

    func testMaximizeOnePointNarrowStaysPut() {
        let zone = CGRect(x: 0, y: 0, width: 1679, height: 1079)
        let window = CGRect(x: 0, y: 0, width: 1678, height: 1079)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: zone, alignment: .edgesAndCorners)
        XCTAssertTrue(result.equalTo(window))
    }

    func testRightHalfOnePointNarrowStaysPut() {
        let zone = CGRect(x: 840, y: 0, width: 839, height: 1079)
        let window = CGRect(x: 840, y: 0, width: 838, height: 1079)
        let screen = CGRect(x: 0, y: 0, width: 1679, height: 1079)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screen, alignment: .edgesAndCorners)
        XCTAssertTrue(result.equalTo(window))
    }

    func testOnePointShortHeightStaysPut() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 1000, height: 1199)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertTrue(result.equalTo(window))
    }

    func testShortfallJustOverToleranceStillAligns() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 998.5, height: 1200)
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 1001.5, accuracy: 0.001) // zone.maxX - width = 2000 - 998.5
    }

    func testOnePointNarrowLeavesOtherAxisAlignmentIntact() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1000, y: 0, width: 999, height: 800) // a point narrow, genuinely short
        let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                  screenFrame: screenFrame, alignment: .edgesAndCorners)
        XCTAssertEqual(result.origin.x, 1000, accuracy: 0.001) // width within tolerance, left alone
        XCTAssertEqual(result.origin.y, 200, accuracy: 0.001)  // height still centered: (1200-800)/2
    }

    func testCornersModeCentersHalfButAnchorsQuarter() {
        let window = CGRect(x: 1000, y: 0, width: 600, height: 400)
        let half = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let quarter = CGRect(x: 1000, y: 0, width: 1000, height: 600)

        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: half, initialRect: half,
                                                    screenFrame: screenFrame, alignment: .corners),
                       CGRect(x: 1200, y: 400, width: 600, height: 400))
        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: quarter, initialRect: quarter,
                                                    screenFrame: screenFrame, alignment: .corners),
                       CGRect(x: 1400, y: 0, width: 600, height: 400))
    }

    func testCenteredModeCentersEvenInCorner() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 600)
        let window = CGRect(x: 1000, y: 0, width: 600, height: 400)
        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                    screenFrame: screenFrame, alignment: .centered),
                       CGRect(x: 1200, y: 100, width: 600, height: 400))
    }

    func testLeadingCornerKeepsAspectRatioWindowsTopAlignedAcrossSideWidths() {
        // Offset display, including negative coordinates; widths are 1/2, 2/3, 1/3.
        let screen = CGRect(x: -2400, y: -600, width: 2400, height: 1400)
        for width: CGFloat in [1200, 1600, 800] {
            for x in [screen.minX, screen.maxX - width] {
                let zone = CGRect(x: x, y: screen.minY, width: width, height: screen.height)
                let window = CGRect(x: 100, y: 200, width: width, height: width * 9 / 16)
                let result = ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                          screenFrame: screen, alignment: .leadingCorner)
                XCTAssertEqual(result, CGRect(x: x, y: -600, width: width, height: width * 9 / 16))
            }
        }
    }

    func testLeadingCornerUsesGappedZoneOriginForWidthConstrainedWindow() {
        let initialRect = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let zone = initialRect.insetBy(dx: 12, dy: 12)
        let window = CGRect(x: 1500, y: 200, width: 600, height: zone.height)

        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: initialRect,
                                                    screenFrame: screenFrame, alignment: .leadingCorner),
                       CGRect(x: 1012, y: 12, width: 600, height: 1176))
        // Existing edge alignment must still detect edges before gaps are applied.
        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: initialRect,
                                                    screenFrame: screenFrame, alignment: .edgesAndCorners),
                       CGRect(x: 1388, y: 200, width: 600, height: 1176))
    }

    func testLeadingCornerPreservesFixedSizeLargerThanZone() {
        let zone = CGRect(x: 1000, y: 600, width: 1000, height: 600)
        let window = CGRect(x: 100, y: 200, width: 1100, height: 800)
        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                    screenFrame: screenFrame, alignment: .leadingCorner),
                       CGRect(x: 1000, y: 600, width: 1100, height: 800))
        // Screen containment is applied separately by BestEffortWindowMover.
    }

    func testLeadingCornerRestoresRequestedOriginWithinSizeTolerance() {
        let zone = CGRect(x: 1000, y: 0, width: 1000, height: 1200)
        let window = CGRect(x: 1004, y: 7, width: 999, height: 1199)
        XCTAssertEqual(ClampedWindowAligner.aligned(window: window, inZone: zone, initialRect: zone,
                                                    screenFrame: screenFrame, alignment: .leadingCorner),
                       CGRect(x: 1000, y: 0, width: 999, height: 1199))
    }
}

class NilWindowIdCalculationTests: XCTestCase {
    
    private let visibleFrame = CGRect(x: 10, y: 20, width: 1200, height: 900)
    private let windowRect = CGRect(x: 100, y: 100, width: 600, height: 400)
    
    /// The window id is bookkeeping only (#640); geometry must not depend on it.
    func testRectCalculationsMatchWithAndWithoutWindowId() {
        for action in WindowAction.active {
            guard let calculation = WindowCalculationFactory.calculationsByAction[action] else { continue }
            
            let withId = calculation.calculateRect(params(windowId: 1, action: action)).rect
            let withoutId = calculation.calculateRect(params(windowId: nil, action: action)).rect
            
            XCTAssertEqual(withId, withoutId, "\(action.name) geometry should not depend on window id")
        }
    }
    
    private func params(windowId: CGWindowID?, action: WindowAction) -> RectCalculationParameters {
        RectCalculationParameters(window: Window(id: windowId, rect: windowRect),
                                  visibleFrameOfScreen: visibleFrame,
                                  action: action,
                                  lastAction: nil)
    }
}

class DerivedWindowIdTests: XCTestCase {
    
    func testDerivedIdHasHighBitSet() {
        XCTAssertEqual(AccessibilityElement.deriveWindowId(fromElementHash: 0) & 0x8000_0000, 0x8000_0000)
        XCTAssertEqual(AccessibilityElement.deriveWindowId(fromElementHash: CFHashCode.max) & 0x8000_0000, 0x8000_0000)
    }
    
    func testDerivedIdIsDeterministic() {
        XCTAssertEqual(AccessibilityElement.deriveWindowId(fromElementHash: 1668292462),
                       AccessibilityElement.deriveWindowId(fromElementHash: 1668292462))
    }
    
    func testDistinctHashesGiveDistinctIds() {
        let ids: [CGWindowID] = [1668318964, 1668318948, 1668321588].map { AccessibilityElement.deriveWindowId(fromElementHash: CFHashCode($0)) }
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

// Portrait eighth snapping tiles the screen into four rows. On a display whose
// visible-frame height is not divisible by 4, the row origins must be expressed
// as cell-height multiples (floor(height / 4)) so adjacent rows abut exactly
// instead of drifting apart by the raw height fraction's sub-pixel remainder.
class PortraitEighthAbutmentTests: XCTestCase {

    // Portrait frame whose height is NOT divisible by 4 (1002 % 4 == 2): the case
    // that used to leave 1-2px gaps between rows.
    private static let nonDivisibleFrame = CGRect(x: 0, y: 0, width: 800, height: 1002)
    // Portrait frame whose height IS divisible by 4: rows already tile seamlessly.
    private static let divisibleFrame = CGRect(x: 0, y: 0, width: 800, height: 1000)

    private func portraitEighths(_ frame: CGRect) -> [CGRect] {
        return [
            TopLeftEighthCalculation().portraitRect(frame).rect,
            TopCenterLeftEighthCalculation().portraitRect(frame).rect,
            TopCenterRightEighthCalculation().portraitRect(frame).rect,
            TopRightEighthCalculation().portraitRect(frame).rect,
            BottomLeftEighthCalculation().portraitRect(frame).rect,
            BottomCenterLeftEighthCalculation().portraitRect(frame).rect,
            BottomCenterRightEighthCalculation().portraitRect(frame).rect,
            BottomRightEighthCalculation().portraitRect(frame).rect,
        ]
    }

    private func rowOrigins(_ frame: CGRect) -> [CGFloat] {
        return Set(portraitEighths(frame).map { $0.origin.y }).sorted(by: >)
    }

    func testAllPortraitEighthsAreOneCellTall() {
        let cellHeight = floor(Self.nonDivisibleFrame.height / 4.0)
        for rect in portraitEighths(Self.nonDivisibleFrame) {
            XCTAssertEqual(rect.height, cellHeight, accuracy: 0.001)
        }
    }

    func testPortraitEighthRowsAlignToCellHeightGridOnNonDivisibleHeight() {
        let frame = Self.nonDivisibleFrame
        let cellHeight = floor(frame.height / 4.0)
        let origins = rowOrigins(frame)

        XCTAssertEqual(origins.count, 4)
        XCTAssertEqual(origins[0], frame.maxY - cellHeight, accuracy: 0.001)
        XCTAssertEqual(origins[1], frame.maxY - cellHeight * 2.0, accuracy: 0.001)
        XCTAssertEqual(origins[2], frame.maxY - cellHeight * 3.0, accuracy: 0.001)
        XCTAssertEqual(origins[3], frame.minY, accuracy: 0.001)
    }

    func testPortraitEighthRowsAbutExactlyOnNonDivisibleHeight() {
        // Before the fix, rows 2 and 3 used raw height fractions (height / 2 and
        // height * 0.75), so rows 1-2 and 2-3 each drifted ~1px apart. The top
        // three rows must abut exactly now: each row's minY equals the row
        // above's maxY. (The height % 4 residual sits at the row3-row4 boundary
        // and is zero only when height is divisible by 4 — see the divisible test.)
        let frame = Self.nonDivisibleFrame
        let cellHeight = floor(frame.height / 4.0)
        let origins = rowOrigins(frame)

        XCTAssertEqual(origins[0], origins[1] + cellHeight, accuracy: 0.001)
        XCTAssertEqual(origins[1], origins[2] + cellHeight, accuracy: 0.001)
    }

    func testPortraitEighthRowsTileFullyWhenHeightDivisibleByFour() {
        // When height % 4 == 0 the rounding residual is zero, so every row boundary
        // abuts. Guards against regressing the already-seamless divisible case.
        let frame = Self.divisibleFrame
        let cellHeight = frame.height / 4.0
        let origins = rowOrigins(frame)

        XCTAssertEqual(origins[0], origins[1] + cellHeight, accuracy: 0.001)
        XCTAssertEqual(origins[1], origins[2] + cellHeight, accuracy: 0.001)
        XCTAssertEqual(origins[2], origins[3] + cellHeight, accuracy: 0.001)
    }
}
      
final class WindowSizeConstraintTests: XCTestCase {
    private let requested = CGRect(x: 0, y: 0, width: 504, height: 900)

    func testMinimumWidthAndHeightAreDetectedIndependently() {
        XCTAssertTrue(WindowSizeConstraint.isExceeded(requested: requested,
                                                      actual: CGRect(x: 0, y: 0, width: 600, height: 900),
                                                      action: .firstThird))
        XCTAssertTrue(WindowSizeConstraint.isExceeded(requested: requested,
                                                      actual: CGRect(x: 0, y: 0, width: 504, height: 950),
                                                      action: .firstThird))
    }

    func testRoundingUpToOnePointDoesNotWarn() {
        for difference: CGFloat in [0, 0.5, 1] {
            let actual = CGRect(x: 30, y: -20, width: requested.width + difference,
                                height: requested.height + difference)
            XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: requested, actual: actual,
                                                           action: .firstThird))
        }
        XCTAssertTrue(WindowSizeConstraint.isExceeded(requested: requested,
                                                      actual: CGRect(x: 0, y: 0, width: 505.5, height: 900),
                                                      action: .firstThird))
    }

    func testMaximumSizeOrAspectRatioConstraintsDoNotWarn() {
        for size in [CGSize(width: 400, height: 900), CGSize(width: 504, height: 600),
                     CGSize(width: 400, height: 600)] {
            XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: requested,
                                                           actual: CGRect(origin: .zero, size: size),
                                                           action: .maximize))
        }
    }

    func testMoveOnlyActionsDoNotWarn() {
        let actual = CGRect(x: 20, y: 20, width: 600, height: 950)
        for action: WindowAction in [.center, .centerProminently, .nextDisplay] {
            XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: requested, actual: actual,
                                                           action: action))
        }
    }

    func testInvalidRequestedAndActualFramesDoNotWarn() {
        let invalidFrames: [CGRect] = [
            .null, .infinite, .zero,
            CGRect(x: 0, y: 0, width: 0, height: 900),
            CGRect(x: 0, y: 0, width: 504, height: 0),
            CGRect(x: 0, y: 0, width: -504, height: 900),
            CGRect(x: 0, y: 0, width: 504, height: -900),
            CGRect(x: CGFloat.nan, y: 0, width: 504, height: 900),
            CGRect(x: 0, y: CGFloat.infinity, width: 504, height: 900),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 900),
            CGRect(x: 0, y: 0, width: 504, height: CGFloat.nan)
        ]
        let larger = CGRect(x: 0, y: 0, width: 600, height: 950)
        for invalid in invalidFrames {
            XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: invalid, actual: larger,
                                                           action: .firstThird))
            XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: requested, actual: invalid,
                                                           action: .firstThird))
        }
    }
}

final class WindowSizeConstraintExecutionTests: XCTestCase {
    private let windowId: CGWindowID = 522_001
    private var savedDefaults: [(Default, CodableDefault)] = []
    private var savedRestoreRects: [CGWindowID: CGRect] = [:]
    private var savedActions: [CGWindowID: RectangleAction] = [:]
    private var savedLogging = false

    override func setUp() {
        super.setUp()
        let settings: [(Default, CodableDefault)] = [
            (Defaults.subsequentExecutionMode, CodableDefault(int: SubsequentExecutionMode.none.rawValue)),
            (Defaults.cooperativeCornerResize, CodableDefault(bool: false)),
            (Defaults.experimentalWindowAnimations, CodableDefault(bool: false)),
            (Defaults.useCursorScreenDetection, CodableDefault(bool: false)),
            (Defaults.moveFixedSizeToEdge, CodableDefault(int: EdgeAlignment.edgesAndCorners.rawValue)),
            (Defaults.horizontalSplitRatio, CodableDefault(float: 50)),
            (Defaults.verticalSplitRatio, CodableDefault(float: 50)),
            (Defaults.halvesPreserveOtherAxisSize, CodableDefault(bool: false)),
            (Defaults.cycleSizesIsChanged, CodableDefault(bool: false)),
            (Defaults.resizeOnDirectionalMove, CodableDefault(bool: false)),
            (Defaults.centeredDirectionalMove, CodableDefault(int: 2)),
            (Defaults.gapSize, CodableDefault(float: 0)),
            (Defaults.stageSize, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapLeft, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapRight, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapTop, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapBottom, CodableDefault(float: 0)),
            (Defaults.cyclingOverlapOffset, CodableDefault(int: 2)),
            (Defaults.combinedDisplayMode, CodableDefault(int: 2)),
            (Defaults.layoutHelper, CodableDefault(int: 2)),
            (Defaults.layoutHelperKeyboard, CodableDefault(bool: false)),
            (Defaults.todo, CodableDefault(int: 2))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
        savedRestoreRects = AppDelegate.windowHistory.restoreRects
        savedActions = AppDelegate.windowHistory.lastRectangleActions
        AppDelegate.windowHistory.restoreRects.removeValue(forKey: windowId)
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        savedLogging = Logger.logging
        Logger.logging = false
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        AppDelegate.windowHistory.restoreRects = savedRestoreRects
        AppDelegate.windowHistory.lastRectangleActions = savedActions
        Logger.logging = savedLogging
        super.tearDown()
    }

    func testLeadingOriginPersistsThroughConstrainedHalfCycles() {
        assertConstrainedHalfCycles(alignment: .leadingCorner, topOffsets: [0, 0, 0, 0])
    }

    func testEdgesAndCornersCentersConstrainedHalfCycles() {
        assertConstrainedHalfCycles(alignment: .edgesAndCorners, topOffsets: [363, 250, 475, 363])
    }

    func testCornersOnlyCentersConstrainedHalfCycles() {
        assertConstrainedHalfCycles(alignment: .corners, topOffsets: [363, 250, 475, 363])
    }

    func testCenteredModeCentersConstrainedHalfCycles() {
        assertConstrainedHalfCycles(alignment: .centered, topOffsets: [363, 250, 475, 363])
    }

    private func assertConstrainedHalfCycles(alignment: EdgeAlignment, topOffsets: [CGFloat],
                                            file: StaticString = #filePath, line: UInt = #line) {
        Defaults.moveFixedSizeToEdge.value = alignment
        Defaults.subsequentExecutionMode.value = .resize
        let screen = TestScreen(frame: CGRect(x: -2400, y: -600, width: 2400, height: 1400))
        let window = ConstrainedWindow(frame: CGRect(x: -2000, y: -200, width: 800, height: 450).screenFlipped) {
            CGRect(origin: $0.origin, size: CGSize(width: $0.width, height: $0.width * 9 / 16))
        }
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen))

        // Each execution consumes the achieved frame and history from the previous one.
        // Changing sides must start the new action's cycle at one half.
        for action: WindowAction in [.leftHalf, .rightHalf] {
            for (index, width) in [CGFloat(1200), 1600, 800, 1200].enumerated() {
                manager.execute(ExecutionParameters(action, screen: screen, windowElement: window,
                                                    windowId: windowId, source: .menuItem))

                let x = action == .leftHalf ? screen.frame.minX : screen.frame.maxX - width
                XCTAssertEqual(window.frame,
                               CGRect(x: x, y: screen.frame.screenFlipped.minY + topOffsets[index],
                                      width: width, height: width * 9 / 16),
                               "\(action), width \(width)", file: file, line: line)
            }
        }
    }

    func testLeadingOriginFixedWindowIsContainedAfterBottomRightPlacement() {
        Defaults.moveFixedSizeToEdge.value = .leadingCorner
        let screen = TestScreen(frame: CGRect(x: -1600, y: 200, width: 1200, height: 900))
        let size = CGSize(width: 800, height: 700)
        let window = ConstrainedWindow(frame: CGRect(x: -1500, y: 300, width: size.width, height: size.height).screenFlipped,
                                       resizable: false) {
            CGRect(origin: $0.origin, size: size)
        }
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen))

        manager.execute(ExecutionParameters(.bottomRight, screen: screen, windowElement: window,
                                            windowId: windowId, source: .menuItem))

        // The 600x450 snap region cannot hold this window. Containment takes precedence
        // over its requested origin without shrinking the app's accepted size.
        let visibleFrame = screen.frame.screenFlipped
        XCTAssertEqual(window.frame,
                       CGRect(x: visibleFrame.maxX - size.width, y: visibleFrame.maxY - size.height,
                              width: size.width, height: size.height))
        XCTAssertTrue(visibleFrame.contains(window.frame))
    }

    func testLeadingOriginDoesNotOverrideAppPositionAfterMovementOnlyAction() {
        Defaults.moveFixedSizeToEdge.value = .leadingCorner
        let screen = TestScreen(frame: CGRect(x: -2400, y: -600, width: 2400, height: 1400))
        let initialFrame = CGRect(x: -1900, y: 0, width: 600, height: 400).screenFlipped
        var initialMove = true
        let window = ConstrainedWindow(frame: initialFrame) { requestedFrame in
            // Simulate the app correcting its position after the initial move.
            // A subsequent alignment write would wrongly undo that correction.
            defer { initialMove = false }
            return initialMove ? requestedFrame.offsetBy(dx: 0, dy: 7) : requestedFrame
        }
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen))

        manager.execute(ExecutionParameters(.moveRight, screen: screen, windowElement: window,
                                            windowId: windowId, source: .menuItem))

        XCTAssertEqual(window.frame,
                       CGRect(x: screen.frame.maxX - initialFrame.width, y: initialFrame.minY + 7,
                              width: initialFrame.width, height: initialFrame.height))
    }

    func testClampedFirstAndLastThirdsWarnAndPreserveAchievedGeometry() {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 900))
        for action: WindowAction in [.firstThird, .lastThird] {
            let window = ClampingWindow(targetSize: CGSize(width: 504, height: 900))
            let originalFrame = window.frame
            let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen))

            manager.execute(ExecutionParameters(action, screen: screen, windowElement: window,
                                                windowId: windowId, source: .menuItem))

            XCTAssertEqual(window.resizeAttempts, 1)
            XCTAssertEqual(window.frame.width, 600)
            XCTAssertEqual(window.frame.height, 900)
            XCTAssertEqual(window.frame.minX, action == .firstThird ? 0 : 912)
            XCTAssertEqual(manager.warningScreens.count, 1)
            XCTAssertTrue(manager.warningScreens.first === screen)
            XCTAssertEqual(manager.hideCount, 1)
            XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.rect, window.frame)
            XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.action, action)
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[windowId], originalFrame)
        }
    }

    func testSuccessfulTwoThirdsClearEarlierWarning() {
        let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 900))
        let window = ClampingWindow(targetSize: CGSize(width: 504, height: 900))
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen))
        manager.execute(ExecutionParameters(.firstThird, screen: screen, windowElement: window,
                                            windowId: windowId, source: .menuItem))
        XCTAssertTrue(manager.warningVisible)

        manager.execute(ExecutionParameters(.firstTwoThirds, screen: screen, windowElement: window,
                                            windowId: windowId, source: .menuItem))

        XCTAssertEqual(window.frame.size, CGSize(width: 1008, height: 900))
        XCTAssertEqual(manager.warningScreens.count, 1)
        XCTAssertEqual(manager.hideCount, 2)
        XCTAssertFalse(manager.warningVisible)
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.rect, window.frame)
    }

    func testSuccessfulFinalCrossDisplayRetryDoesNotWarn() {
        assertCrossDisplayWarning(clampedAttempts: 2, expectsWarning: false)
    }

    func testPersistentlyClampedCrossDisplayRetryWarnsOnceOnDestination() {
        assertCrossDisplayWarning(clampedAttempts: nil, expectsWarning: true)
    }

    func testNewerActionCancelsPendingCrossDisplayRetryAndWarning() {
        let source = TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 900))
        let destination = TestScreen(frame: CGRect(x: 1512, y: 0, width: 1512, height: 900))
        let window = ClampingWindow(targetSize: CGSize(width: 504, height: 900))
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: source))
        manager.execute(ExecutionParameters(.lastThird, screen: destination, windowElement: window,
                                            windowId: windowId, source: .menuItem))
        XCTAssertEqual(window.resizeAttempts, 2)
        XCTAssertTrue(manager.warningScreens.isEmpty)

        manager.execute(ExecutionParameters(.firstTwoThirds, screen: source, windowElement: window,
                                            windowId: windowId, source: .menuItem))
        let newerFrame = window.frame
        XCTAssertEqual(newerFrame.size, CGSize(width: 1008, height: 900))
        let staleCompletion = expectation(description: "Superseded resize must not complete")
        staleCompletion.isInverted = true
        manager.didFinish = { staleCompletion.fulfill() }

        wait(for: [staleCompletion], timeout: 0.1)

        XCTAssertEqual(window.resizeAttempts, 2)
        XCTAssertEqual(window.frame, newerFrame)
        XCTAssertTrue(manager.warningScreens.isEmpty)
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.rect, newerFrame)
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.action, .firstTwoThirds)
    }

    private func assertCrossDisplayWarning(clampedAttempts: Int?, expectsWarning: Bool) {
        let source = TestScreen(frame: CGRect(x: 0, y: 0, width: 1512, height: 900))
        let destination = TestScreen(frame: CGRect(x: 1512, y: 0, width: 1512, height: 900))
        let window = ClampingWindow(targetSize: CGSize(width: 504, height: 900),
                                    clampedAttempts: clampedAttempts)
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: source))
        let finished = expectation(description: "Final cross-display resize processed")
        manager.didFinish = { finished.fulfill() }

        manager.execute(ExecutionParameters(.lastThird, screen: destination, windowElement: window,
                                            windowId: windowId, source: .menuItem))

        XCTAssertEqual(window.resizeAttempts, 2)
        XCTAssertTrue(manager.warningScreens.isEmpty)
        XCTAssertNil(AppDelegate.windowHistory.lastRectangleActions[windowId])

        wait(for: [finished], timeout: 1)
        XCTAssertEqual(window.resizeAttempts, 3)
        XCTAssertEqual(window.frame.width, expectsWarning ? 600 : 504)
        XCTAssertEqual(window.frame.maxX, destination.frame.maxX)
        XCTAssertEqual(manager.warningScreens.count, expectsWarning ? 1 : 0)
        if expectsWarning {
            XCTAssertTrue(manager.warningScreens.first === destination)
        }
        XCTAssertEqual(AppDelegate.windowHistory.lastRectangleActions[windowId]?.rect, window.frame)
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
        let source: NSScreen

        init(source: NSScreen) { self.source = source }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            UsableScreens(currentScreen: source, numScreens: 2)
        }
    }

    private final class ClampingWindow: AccessibilityElement {
        private var currentFrame = CGRect(x: 100, y: 100, width: 900, height: 500).screenFlipped
        private let targetSize: CGSize
        private let clampedAttempts: Int?
        private(set) var resizeAttempts = 0

        init(targetSize: CGSize, clampedAttempts: Int? = nil) {
            self.targetSize = targetSize
            self.clampedAttempts = clampedAttempts
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { currentFrame }
        override var isSheet: Bool? { false }
        override var isSystemDialog: Bool? { false }
        override var minimumSize: CGSize? { nil }
        override func getWindowId() -> CGWindowID? { nil }
        override func isResizable() -> Bool { true }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: WindowAnimationPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            currentFrame = frame
            if frame.size == targetSize {
                resizeAttempts += 1
                if clampedAttempts.map({ resizeAttempts <= $0 }) ?? true {
                    currentFrame.size.width = max(frame.width, 600)
                }
            }
        }
    }

    private final class ConstrainedWindow: AccessibilityElement {
        private var currentFrame: CGRect
        private let resizable: Bool
        private let acceptedFrame: (CGRect) -> CGRect

        init(frame: CGRect, resizable: Bool = true, acceptedFrame: @escaping (CGRect) -> CGRect) {
            currentFrame = frame
            self.resizable = resizable
            self.acceptedFrame = acceptedFrame
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { currentFrame }
        override var isSheet: Bool? { false }
        override var isSystemDialog: Bool? { false }
        override var minimumSize: CGSize? { nil }
        override func getWindowId() -> CGWindowID? { nil }
        override func isResizable() -> Bool { resizable }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: WindowAnimationPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            currentFrame = acceptedFrame(frame)
        }
    }

    private final class TestWindowManager: WindowManager {
        private(set) var warningScreens: [NSScreen] = []
        private(set) var hideCount = 0
        private(set) var warningVisible = false
        var didFinish: (() -> Void)?

        override func showSizeConstraintWarning(on screen: NSScreen) {
            warningScreens.append(screen)
            warningVisible = true
        }

        override func hideSizeConstraintWarning() {
            hideCount += 1
            warningVisible = false
        }

        override func windowMovedAcrossDisplays(windowElement: AccessibilityElement, resultingRect: CGRect) {}

        override func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
            super.postProcess(result: result, resultingRect: resultingRect, incrementCount: incrementCount)
            didFinish?()
        }
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
                                        placement: WindowAnimationPlacement? = nil) {
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

        override func windowMovedAcrossDisplays(windowElement: AccessibilityElement, resultingRect: CGRect) {}

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

class HalvesPreserveOtherAxisSizeTests: XCTestCase {

    private var savedHalvesPreserveOtherAxisSize = false
    private var savedGapSize: Float = 0
    private var savedSkipGapTopEdge = false
    private var savedHorizontalSplitRatio: Float = 50
    private var savedVerticalSplitRatio: Float = 50
    private var savedSubsequentExecutionMode: SubsequentExecutionMode = .resize
    private var savedCycleSizesIsChanged = false
    private var savedCooperativeCornerResize = false

    private let visibleFrame = CGRect(x: 10, y: 20, width: 1200, height: 900)
    // Ungapped rects that the half and quarter actions produce on `visibleFrame` at the default 50% split.
    private let leftHalf = CGRect(x: 10, y: 20, width: 600, height: 900)
    private let rightHalf = CGRect(x: 610, y: 20, width: 600, height: 900)
    private let topHalf = CGRect(x: 10, y: 470, width: 1200, height: 450)
    private let bottomHalf = CGRect(x: 10, y: 20, width: 1200, height: 450)
    private let topLeftQuarter = CGRect(x: 10, y: 470, width: 600, height: 450)
    private let topRightQuarter = CGRect(x: 610, y: 470, width: 600, height: 450)
    private let bottomLeftQuarter = CGRect(x: 10, y: 20, width: 600, height: 450)
    private let bottomRightQuarter = CGRect(x: 610, y: 20, width: 600, height: 450)

    override func setUp() {
        super.setUp()
        savedHalvesPreserveOtherAxisSize = Defaults.halvesPreserveOtherAxisSize.enabled
        savedGapSize = Defaults.gapSize.value
        savedSkipGapTopEdge = Defaults.skipGapTopEdge.enabled
        savedHorizontalSplitRatio = Defaults.horizontalSplitRatio.value
        savedVerticalSplitRatio = Defaults.verticalSplitRatio.value
        savedSubsequentExecutionMode = Defaults.subsequentExecutionMode.value
        savedCycleSizesIsChanged = Defaults.cycleSizesIsChanged.enabled
        savedCooperativeCornerResize = Defaults.cooperativeCornerResize.enabled
        Defaults.halvesPreserveOtherAxisSize.enabled = true
        Defaults.gapSize.value = 0
        Defaults.skipGapTopEdge.enabled = false
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = 50
        Defaults.subsequentExecutionMode.value = .resize
        Defaults.cycleSizesIsChanged.enabled = false
        Defaults.cooperativeCornerResize.enabled = false
        ActiveSideSplitRatios.shared.resetAll()
    }

    override func tearDown() {
        Defaults.halvesPreserveOtherAxisSize.enabled = savedHalvesPreserveOtherAxisSize
        Defaults.gapSize.value = savedGapSize
        Defaults.skipGapTopEdge.enabled = savedSkipGapTopEdge
        Defaults.horizontalSplitRatio.value = savedHorizontalSplitRatio
        Defaults.verticalSplitRatio.value = savedVerticalSplitRatio
        Defaults.subsequentExecutionMode.value = savedSubsequentExecutionMode
        Defaults.cycleSizesIsChanged.enabled = savedCycleSizesIsChanged
        Defaults.cooperativeCornerResize.enabled = savedCooperativeCornerResize
        ActiveSideSplitRatios.shared.resetAll()
        super.tearDown()
    }

    // MARK: A half action keeps the other axis: Left + Top = top left quarter, in either order

    func testTopHalfKeepsLeftHalfColumn() {
        assertTiled(.topHalf, from: leftHalf, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testLeftHalfKeepsTopHalfRow() {
        assertTiled(.leftHalf, from: topHalf, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testBottomHalfKeepsRightHalfColumn() {
        assertTiled(.bottomHalf, from: rightHalf, gives: bottomRightQuarter, as: .bottomRight, subAction: .bottomRightQuarter)
    }

    func testRightHalfKeepsBottomHalfRow() {
        assertTiled(.rightHalf, from: bottomHalf, gives: bottomRightQuarter, as: .bottomRight, subAction: .bottomRightQuarter)
    }

    func testTopHalfKeepsRightHalfColumn() {
        assertTiled(.topHalf, from: rightHalf, gives: topRightQuarter, as: .topRight, subAction: .topRightQuarter)
    }

    func testBottomHalfKeepsLeftHalfColumn() {
        assertTiled(.bottomHalf, from: leftHalf, gives: bottomLeftQuarter, as: .bottomLeft, subAction: .bottomLeftQuarter)
    }

    // MARK: The action for the opposite edge expands the window along that axis

    func testBottomHalfExpandsTopLeftQuarterToLeftHalf() {
        assertTiled(.bottomHalf, from: topLeftQuarter, gives: leftHalf, as: .leftHalf)
    }

    func testTopHalfExpandsBottomLeftQuarterToLeftHalf() {
        assertTiled(.topHalf, from: bottomLeftQuarter, gives: leftHalf, as: .leftHalf)
    }

    func testRightHalfExpandsTopLeftQuarterToTopHalf() {
        assertTiled(.rightHalf, from: topLeftQuarter, gives: topHalf, as: .topHalf)
    }

    func testLeftHalfExpandsBottomRightQuarterToBottomHalf() {
        assertTiled(.leftHalf, from: bottomRightQuarter, gives: bottomHalf, as: .bottomHalf)
    }

    func testLeftHalfExpandsRightHalfToFullScreen() {
        assertTiled(.leftHalf, from: rightHalf, gives: visibleFrame, as: .maximize)
    }

    func testTopHalfExpandsBottomHalfToFullScreen() {
        assertTiled(.topHalf, from: bottomHalf, gives: visibleFrame, as: .maximize)
    }

    // MARK: The action for the edge a quarter is docked to cycles sizes along its own axis

    func testLeftHalfCyclesWidthOfTopLeftQuarter() {
        let twoThirdsWide = CGRect(x: 10, y: 470, width: 800, height: 450)
        let oneThirdWide = CGRect(x: 10, y: 470, width: 400, height: 450)

        assertTiled(.leftHalf, from: topLeftQuarter, gives: twoThirdsWide, as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.leftHalf, from: twoThirdsWide, gives: oneThirdWide, as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.leftHalf, from: oneThirdWide, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testRightHalfCyclesWidthOfBottomRightQuarterFromItsEdge() {
        assertTiled(.rightHalf, from: bottomRightQuarter,
                    gives: CGRect(x: 410, y: 20, width: 800, height: 450), as: .bottomRight, subAction: .bottomRightQuarter)
    }

    func testTopHalfCyclesHeightOfTopLeftQuarter() {
        let twoThirdsHigh = CGRect(x: 10, y: 320, width: 600, height: 600)
        let oneThirdHigh = CGRect(x: 10, y: 620, width: 600, height: 300)

        assertTiled(.topHalf, from: topLeftQuarter, gives: twoThirdsHigh, as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.topHalf, from: twoThirdsHigh, gives: oneThirdHigh, as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.topHalf, from: oneThirdHigh, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testBottomHalfCyclesHeightOfBottomRightQuarterFromItsEdge() {
        assertTiled(.bottomHalf, from: bottomRightQuarter,
                    gives: CGRect(x: 610, y: 20, width: 600, height: 600), as: .bottomRight, subAction: .bottomRightQuarter)
    }

    func testCyclingInsideQuarterUsesSelectedCycleSizes() {
        let savedSelectedCycleSizes = Defaults.selectedCycleSizes.value
        defer { Defaults.selectedCycleSizes.value = savedSelectedCycleSizes }
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = [.twoThirds, .oneQuarter]

        let twoThirdsWide = CGRect(x: 10, y: 470, width: 800, height: 450)
        let oneQuarterWide = CGRect(x: 10, y: 470, width: 300, height: 450)

        // One half is not selected: the cycle starts at the first selected size and never returns to one half.
        assertTiled(.leftHalf, from: topLeftQuarter, gives: twoThirdsWide, as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.leftHalf, from: twoThirdsWide, gives: oneQuarterWide, as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.leftHalf, from: oneQuarterWide, gives: twoThirdsWide, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testCyclingInsideQuarterStartsOverFromCustomSplitRatio() {
        Defaults.horizontalSplitRatio.value = 60
        let sixtyPercentWide = CGRect(x: 10, y: 470, width: 720, height: 450)

        assertTiled(.leftHalf, from: sixtyPercentWide, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testCyclingInsideQuarterRecognizesGappedWindow() {
        Defaults.gapSize.value = 20
        let gappedTopLeftQuarter = GapCalculation.applyGaps(topLeftQuarter, dimension: .both, sharedEdges: [.right, .bottom], gapSize: 20, skipTopGap: false)

        assertTiled(.leftHalf, from: gappedTopLeftQuarter,
                    gives: CGRect(x: 10, y: 470, width: 800, height: 450), as: .topLeft, subAction: .topLeftQuarter)
    }

    func testQuarterStaysPutWhenRepeatedCommandsDoNotResize() {
        for mode in [SubsequentExecutionMode.none, .acrossMonitor, .cycleMonitor] {
            Defaults.subsequentExecutionMode.value = mode
            assertTiled(.leftHalf, from: topLeftQuarter, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
            assertTiled(.topHalf, from: topLeftQuarter, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
        }
    }

    func testQuarterStaysPutWhenNoCycleSizesAreSelected() {
        let savedSelectedCycleSizes = Defaults.selectedCycleSizes.value
        defer { Defaults.selectedCycleSizes.value = savedSelectedCycleSizes }
        Defaults.cycleSizesIsChanged.enabled = true
        Defaults.selectedCycleSizes.value = []

        assertTiled(.leftHalf, from: topLeftQuarter, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testRepeatedTopHalfInsideQuarterCyclesHeightWithoutHistory() {
        let params = params(for: .topHalf, windowRect: topLeftQuarter,
                            lastAction: RectangleAction(action: .topLeft, subAction: .topLeftQuarter, rect: topLeftQuarter, count: 5))

        let result = WindowCalculationFactory.topHalfCalculation.calculateRect(params)

        XCTAssertEqual(result.rect, CGRect(x: 10, y: 320, width: 600, height: 600))
        XCTAssertEqual(result.resultingAction, .topLeft)
        XCTAssertEqual(result.subAction, .topLeftQuarter)
    }

    // MARK: Plain halves and windows that are not tiled behave as without the feature

    func testPlainHalvesRepeatAsUsual() {
        XCTAssertNil(tiled(.leftHalf, from: leftHalf))
        XCTAssertNil(tiled(.rightHalf, from: rightHalf))
        XCTAssertNil(tiled(.topHalf, from: topHalf))
        XCTAssertNil(tiled(.bottomHalf, from: bottomHalf))
    }

    func testRepeatedPlainTopHalfStillCyclesHeight() {
        let params = params(for: .topHalf, windowRect: topHalf,
                            lastAction: RectangleAction(action: .topHalf, subAction: nil, rect: topHalf, count: 1))

        let result = WindowCalculationFactory.topHalfCalculation.calculateRect(params)

        XCTAssertEqual(result.rect, CGRect(x: 10, y: 320, width: 1200, height: 600))
    }

    func testUntiledWindowsAreNotAffected() {
        let floating = CGRect(x: 300, y: 100, width: 700, height: 500)
        let centeredColumn = CGRect(x: 310, y: 20, width: 600, height: 900)

        for action in [WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf] {
            XCTAssertNil(tiled(action, from: floating), "\(action)")
            XCTAssertNil(tiled(action, from: visibleFrame), "\(action)")
        }
        XCTAssertNil(tiled(.topHalf, from: centeredColumn))
    }

    func testTopHalfCalculationFallsBackToDefaultBehaviorForUntiledWindows() {
        let result = WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf, windowRect: CGRect(x: 300, y: 100, width: 700, height: 500)))

        XCTAssertEqual(result.rect, topHalf)
        XCTAssertNil(result.resultingAction)
        XCTAssertNil(result.subAction)
    }

    func testTopHalfCalculationTilesWhenEnabled() {
        let result = WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf, windowRect: leftHalf))

        XCTAssertEqual(result.rect, topLeftQuarter)
        XCTAssertEqual(result.resultingAction, .topLeft)
        XCTAssertEqual(result.subAction, .topLeftQuarter)
    }

    func testBottomHalfCalculationTilesWhenEnabled() {
        let result = WindowCalculationFactory.bottomHalfCalculation.calculateRect(params(for: .bottomHalf, windowRect: topLeftQuarter))

        XCTAssertEqual(result.rect, leftHalf)
        XCTAssertEqual(result.resultingAction, .leftHalf)
    }

    func testDisabledFeatureKeepsFullWidthTopHalf() {
        Defaults.halvesPreserveOtherAxisSize.enabled = false

        let result = WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf, windowRect: leftHalf))

        XCTAssertEqual(result.rect, topHalf)
        XCTAssertNil(result.resultingAction)
        XCTAssertNil(result.subAction)
    }

    // MARK: Columns and rows other than exactly one half

    func testTopHalfKeepsCycledTwoThirdsColumn() {
        assertTiled(.topHalf, from: CGRect(x: 10, y: 20, width: 800, height: 900),
                    gives: CGRect(x: 10, y: 470, width: 800, height: 450), as: .topLeft, subAction: .topLeftQuarter)
    }

    func testBottomHalfExpandsTwoThirdsWideTopLeftQuarterToTwoThirdsColumn() {
        assertTiled(.bottomHalf, from: CGRect(x: 10, y: 470, width: 800, height: 450),
                    gives: CGRect(x: 10, y: 20, width: 800, height: 900), as: .leftHalf)
    }

    func testLeftHalfKeepsCycledTopThirdRow() {
        assertTiled(.leftHalf, from: CGRect(x: 10, y: 620, width: 1200, height: 300),
                    gives: CGRect(x: 10, y: 620, width: 600, height: 300), as: .topLeft, subAction: .topLeftQuarter)
    }

    func testTopHalfKeepsRightThirdColumn() {
        assertTiled(.topHalf, from: CGRect(x: 810, y: 20, width: 400, height: 900),
                    gives: CGRect(x: 810, y: 470, width: 400, height: 450), as: .topRight, subAction: .topRightQuarter)
    }

    func testCustomSplitRatioIsUsedForRecognitionAndResults() {
        Defaults.horizontalSplitRatio.value = 60

        assertTiled(.topHalf, from: CGRect(x: 10, y: 20, width: 720, height: 900),
                    gives: CGRect(x: 10, y: 470, width: 720, height: 450), as: .topLeft, subAction: .topLeftQuarter)
        assertTiled(.topHalf, from: CGRect(x: 730, y: 20, width: 480, height: 900),
                    gives: CGRect(x: 730, y: 470, width: 480, height: 450), as: .topRight, subAction: .topRightQuarter)
        assertTiled(.leftHalf, from: topHalf,
                    gives: CGRect(x: 10, y: 470, width: 720, height: 450), as: .topLeft, subAction: .topLeftQuarter)
    }

    // MARK: Gaps and tolerance

    func testRecognizesGappedColumnAndReturnsUngappedRect() {
        Defaults.gapSize.value = 20
        // Left half with gaps applied by WindowManager: inset 20 on each side, half a gap back on the shared right edge.
        let gappedLeftHalf = CGRect(x: 30, y: 40, width: 570, height: 860)

        assertTiled(.topHalf, from: gappedLeftHalf, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testRecognizesGappedRowWithSkippedTopGap() {
        Defaults.gapSize.value = 20
        Defaults.skipGapTopEdge.enabled = true
        let gappedTopHalf = GapCalculation.applyGaps(topHalf, dimension: .both, sharedEdges: .bottom, gapSize: 20, skipTopGap: true)

        assertTiled(.leftHalf, from: gappedTopHalf, gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testToleratesWindowsThatCannotTakeTheExactSize() {
        assertTiled(.topHalf, from: CGRect(x: 10, y: 20, width: 594, height: 900),
                    gives: topLeftQuarter, as: .topLeft, subAction: .topLeftQuarter)
    }

    func testDoesNotMatchWindowsFarFromAnyColumn() {
        XCTAssertNil(tiled(.topHalf, from: CGRect(x: 10, y: 20, width: 560, height: 900)))
    }

    // MARK: Helpers

    private func tiled(_ action: WindowAction, from windowRect: CGRect) -> RectResult? {
        HalvesPreserveOtherAxisSize.rect(for: params(for: action, windowRect: windowRect))
    }

    private func assertTiled(_ action: WindowAction,
                             from windowRect: CGRect,
                             gives expectedRect: CGRect,
                             as expectedAction: WindowAction,
                             subAction expectedSubAction: SubWindowAction? = nil,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        guard let result = tiled(action, from: windowRect) else {
            XCTFail("\(action) from \(windowRect) fell back to the default behavior", file: file, line: line)
            return
        }
        XCTAssertEqual(result.rect, expectedRect, file: file, line: line)
        XCTAssertEqual(result.resultingAction, expectedAction, file: file, line: line)
        XCTAssertEqual(result.subAction, expectedSubAction, file: file, line: line)
    }

    private func params(for action: WindowAction, windowRect: CGRect, lastAction: RectangleAction? = nil) -> RectCalculationParameters {
        RectCalculationParameters(window: Window(id: 1, rect: windowRect),
                                  visibleFrameOfScreen: visibleFrame,
                                  action: action,
                                  lastAction: lastAction)
    }
}

class RepeatedMaximizeRestoreTests: XCTestCase {

    private var savedRepeatedMaximizeRestoresPrevious = false

    private let windowId = CGWindowID(24_680)
    private let screen = RepeatedMaximizeTestScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    private let previousFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
    private let maximizedFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let almostMaximizedFrame = CGRect(x: 72, y: 69, width: 1296, height: 788)

    override func setUp() {
        super.setUp()
        savedRepeatedMaximizeRestoresPrevious = Defaults.repeatedMaximizeRestoresPrevious.enabled
        Defaults.repeatedMaximizeRestoresPrevious.enabled = true
    }

    override func tearDown() {
        Defaults.repeatedMaximizeRestoresPrevious.enabled = savedRepeatedMaximizeRestoresPrevious
        AppDelegate.windowHistory.preMaximizeRects.removeValue(forKey: windowId)
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        super.tearDown()
    }

    func testAppliesToMaximizeAndAlmostMaximizeOnly() {
        XCTAssertTrue(RepeatedMaximizeRestore.applies(to: .maximize))
        XCTAssertTrue(RepeatedMaximizeRestore.applies(to: .almostMaximize))
        XCTAssertFalse(RepeatedMaximizeRestore.applies(to: .maximizeHeight))
        XCTAssertFalse(RepeatedMaximizeRestore.applies(to: .leftHalf))
        XCTAssertFalse(RepeatedMaximizeRestore.applies(to: .restore))
    }

    func testRepeatedMaximizeRestoresThePreviousFrame() {
        XCTAssertEqual(restoreRect(.maximize, window: maximizedFrame, last: .maximize, lastRect: maximizedFrame), previousFrame)
        XCTAssertEqual(restoreRect(.almostMaximize, window: almostMaximizedFrame, last: .almostMaximize, lastRect: almostMaximizedFrame), previousFrame)
    }

    func testDoesNothingWhenDisabled() {
        Defaults.repeatedMaximizeRestoresPrevious.enabled = false
        XCTAssertNil(restoreRect(.maximize, window: maximizedFrame, last: .maximize, lastRect: maximizedFrame))
    }

    func testDoesNothingWhenTheLastActionWasAnotherOne() {
        XCTAssertNil(restoreRect(.maximize, window: almostMaximizedFrame, last: .almostMaximize, lastRect: almostMaximizedFrame))
        XCTAssertNil(restoreRect(.almostMaximize, window: maximizedFrame, last: .maximize, lastRect: maximizedFrame))
        XCTAssertNil(restoreRect(.maximize, window: maximizedFrame, last: .leftHalf, lastRect: maximizedFrame))
    }

    func testDoesNothingWithoutHistory() {
        XCTAssertNil(restoreRect(.maximize, window: maximizedFrame, last: nil, lastRect: nil))
        XCTAssertNil(restoreRect(.maximize, window: maximizedFrame, last: .maximize, lastRect: maximizedFrame, previous: nil))
    }

    func testDoesNothingWhenTheWindowMovedSinceTheLastAction() {
        let moved = maximizedFrame.offsetBy(dx: 0, dy: 10)
        XCTAssertNil(restoreRect(.maximize, window: moved, last: .maximize, lastRect: maximizedFrame))
    }

    func testIgnoresOtherActions() {
        XCTAssertNil(restoreRect(.maximizeHeight, window: maximizedFrame, last: .maximizeHeight, lastRect: maximizedFrame))
    }

    // MARK: - Calculation entry point

    func testRecordsThePreviousFrameAndFallsThroughWhenMaximizing() {
        let params = calculationParams(.maximize, window: previousFrame, last: nil)

        XCTAssertNil(RepeatedMaximizeRestore.calculate(params))
        XCTAssertEqual(AppDelegate.windowHistory.preMaximizeRects[windowId], previousFrame.screenFlipped)
    }

    func testRestoresAsTheRestoreAction() {
        AppDelegate.windowHistory.preMaximizeRects[windowId] = previousFrame.screenFlipped
        let params = calculationParams(.maximize, window: maximizedFrame, last: .maximize, lastRect: maximizedFrame)

        let result = RepeatedMaximizeRestore.calculate(params)

        XCTAssertEqual(result?.rect, previousFrame.screenFlipped)
        XCTAssertEqual(result?.resultingAction, .restore)
    }

    func testAlmostMaximizeRestoresTheSameWay() {
        AppDelegate.windowHistory.preMaximizeRects[windowId] = previousFrame.screenFlipped
        let params = calculationParams(.almostMaximize, window: almostMaximizedFrame, last: .almostMaximize, lastRect: almostMaximizedFrame)

        let result = RepeatedMaximizeRestore.calculate(params)

        XCTAssertEqual(result?.rect, previousFrame.screenFlipped)
        XCTAssertEqual(result?.resultingAction, .restore)
    }

    func testMaximizesAgainAfterARestore() {
        AppDelegate.windowHistory.preMaximizeRects[windowId] = maximizedFrame.screenFlipped
        // The restore reported .restore, so the window's last action is no longer the maximize.
        let params = calculationParams(.maximize, window: previousFrame, last: .restore, lastRect: previousFrame)

        XCTAssertNil(RepeatedMaximizeRestore.calculate(params))
        XCTAssertEqual(AppDelegate.windowHistory.preMaximizeRects[windowId], previousFrame.screenFlipped)
    }

    func testRecordsNothingWhenDisabled() {
        Defaults.repeatedMaximizeRestoresPrevious.enabled = false
        let params = calculationParams(.maximize, window: previousFrame, last: nil)

        XCTAssertNil(RepeatedMaximizeRestore.calculate(params))
        XCTAssertNil(AppDelegate.windowHistory.preMaximizeRects[windowId])
    }

    func testMaximizeCalculationRestoresThroughTheHelper() {
        AppDelegate.windowHistory.preMaximizeRects[windowId] = previousFrame.screenFlipped
        let params = calculationParams(.maximize, window: maximizedFrame, last: .maximize, lastRect: maximizedFrame)

        let result = WindowCalculationFactory.maximizeCalculation.calculate(params)

        XCTAssertEqual(result?.rect, previousFrame.screenFlipped)
        XCTAssertEqual(result?.resultingAction, .restore)
    }

    // MARK: - Helpers

    private func restoreRect(_ action: WindowAction,
                             window: CGRect,
                             last: WindowAction?,
                             lastRect: CGRect?,
                             previous: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600)) -> CGRect? {
        RepeatedMaximizeRestore.restoreRect(for: action,
                                            windowRect: window.screenFlipped,
                                            lastAction: rectangleAction(last, lastRect),
                                            preMaximizeRect: previous)
    }

    private func calculationParams(_ action: WindowAction,
                                   window: CGRect,
                                   last: WindowAction?,
                                   lastRect: CGRect? = nil) -> WindowCalculationParameters {
        WindowCalculationParameters(window: Window(id: windowId, rect: window.screenFlipped),
                                    usableScreens: UsableScreens(currentScreen: screen, numScreens: 1),
                                    action: action,
                                    lastAction: rectangleAction(last, lastRect),
                                    ignoreTodo: false)
    }

    private func rectangleAction(_ action: WindowAction?, _ rect: CGRect?) -> RectangleAction? {
        action.map { RectangleAction(action: $0, subAction: nil, rect: rect ?? .null, count: 1) }
    }
}

private final class RepeatedMaximizeTestScreen: NSScreen {
    private let testFrame: CGRect

    init(frame: CGRect) {
        testFrame = frame
        super.init()
    }

    override var frame: NSRect { testFrame }
    override var visibleFrame: NSRect { testFrame }
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
    override var hash: Int { ObjectIdentifier(self).hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as AnyObject?) === self
    }
}


final class WindowAnimationSettlementRoundingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func target(gap: Float = 7) -> CGRect {
        GapCalculation.applyGaps(CGRect(x: 500, y: 0, width: 500, height: 800),
                                 sharedEdges: .left, gapSize: gap)
    }

    private func placement(gap: CGFloat = 7) -> WindowAnimationPlacement {
        WindowAnimationPlacement(screenFrame: screen, sharedEdges: .right,
                                 constrainToScreen: true, gap: gap)
    }

    func testOddGapCompletesAfterOneRoundedPositionWrite() {
        let target = target()
        let actual = CGRect(x: 504, y: 7, width: 490, height: 786)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        let first = settlement.observe(ax: actual, server: actual, destination: target,
                                       placement: placement(), origin: actual, at: 1.0 / 60)
        guard case .align(let requested) = first else { return XCTFail("Expected an exact final position write") }
        XCTAssertEqual(requested.origin, target.origin)
        let second = settlement.observe(ax: actual, server: actual, destination: target,
                                        placement: placement(), origin: actual, at: 2.0 / 60)
        guard case .complete(let achieved) = second else { return XCTFail("Rounded placement must not enter a retry loop") }
        XCTAssertEqual(achieved, actual)
    }

    func testFractionalGapAcceptsHalfPointQuantizationAfterExactWrite() {
        let target = target(gap: 7.5)
        let actual = CGRect(x: 504, y: 7.5, width: 489, height: 785)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        _ = settlement.observe(ax: actual, server: actual, destination: target,
                               placement: placement(gap: 7.5), origin: actual, at: 1.0 / 60)
        let result = settlement.observe(ax: actual, server: actual, destination: target,
                                        placement: placement(gap: 7.5), origin: actual, at: 2.0 / 60)
        guard case .complete(let achieved) = result else { return XCTFail("Expected a verified rounded placement") }
        XCTAssertEqual(achieved, actual)
    }

    func testExactFractionalPositionIsUsedWhenAppAcceptsIt() {
        let target = target()
        let before = CGRect(x: 504, y: 7, width: 490, height: 786)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        let first = settlement.observe(ax: before, server: before, destination: target,
                                       placement: placement(), origin: before, at: 1.0 / 60)
        guard case .align(let requested) = first else { return XCTFail("Expected exact alignment") }
        let result = settlement.observe(ax: requested, server: requested, destination: target,
                                        placement: placement(), origin: before, at: 2.0 / 60)
        guard case .complete(let achieved) = result else { return XCTFail("Expected the accepted exact position") }
        XCTAssertEqual(achieved.origin, target.origin)
    }

    func testDisagreeingServerGeometryDoesNotEstablishRounding() {
        let target = target()
        let actual = CGRect(x: 504, y: 7, width: 490, height: 786)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        let first = settlement.observe(ax: actual, server: actual, destination: target,
                                       placement: placement(), origin: actual, at: 1.0 / 60)
        guard case .align(let requested) = first else { return XCTFail("Expected exact alignment") }
        let result = settlement.observe(ax: actual, server: requested, destination: target,
                                        placement: placement(), origin: actual, at: 2.0 / 60)
        if case .complete = result { XCTFail("Different AX and server positions can still be in flight") }
    }

    func testIntegerTargetStillRequiresExactPosition() {
        let target = CGRect(x: 503, y: 7, width: 490, height: 786)
        let actual = target.offsetBy(dx: 1, dy: 0)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        for step in 1...3 {
            let result = settlement.observe(ax: actual, server: actual, destination: target,
                                            placement: placement(), origin: actual, at: Double(step) / 60)
            if case .complete = result { XCTFail("A full-point residual must still be corrected") }
        }
    }
}

final class WindowAnimationRequestCancellationTests: XCTestCase {
    private final class QueuedWindow: AccessibilityElement {
        private(set) var minimumSizeReads = 0

        init() { super.init(AXUIElementCreateApplication(getpid()), windowID: .max) }
        override var pid: pid_t? { getpid() }
        override var bundleIdentifier: String? { nil }
        override var minimumSize: CGSize? {
            minimumSizeReads += 1
            return nil
        }
    }

    func testTimedOutLookupCancelsWithoutMainThreadPlacementFallback() throws {
        try assertLookupCompletion(.timedOut, cancels: true)
    }

    func testObsoleteLookupCancelsWithoutMainThreadPlacementFallback() throws {
        try assertLookupCompletion(.cancelled, cancels: true)
    }

    func testUnavailableLookupPreservesOrdinaryPlacementFallback() throws {
        try assertLookupCompletion(.unavailable, cancels: false)
    }

    private func assertLookupCompletion(_ result: WindowAccessibilityLookup.Result, cancels: Bool) throws {
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer { Defaults.experimentalWindowAnimations.enabled = saved }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by accessibility settings")
        let finished = expectation(description: "Lookup delivered its terminal callback")
        let executor = WindowAnimationExecutor(lookupWindow: { _, _, _, _, _ in
            XCTAssertFalse(Thread.isMainThread)
            return result
        })
        let window = QueuedWindow()
        var cancellations = 0
        var completions = 0
        executor.animate(window, to: CGRect(x: 100, y: 100, width: 500, height: 400),
                         duration: 0.18, resizeOnly: false, releasedSnap: false, placement: nil,
                         profile: .standard, offset: { .zero }, curve: WindowAnimationCurve.value,
                         cancellation: {
                             XCTAssertTrue(Thread.isMainThread)
                             cancellations += 1
                             finished.fulfill()
                         }) { frame in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(frame.isNull)
            completions += 1
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(cancellations, cancels ? 1 : 0)
        XCTAssertEqual(completions, cancels ? 0 : 1)
        XCTAssertNil(executor.destination(for: window))
        XCTAssertEqual(window.minimumSizeReads, 0)
    }

    func testQueuedAnimationDoesNotReadMinimumSizeBeforeWorkerCanStart() throws {
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer { Defaults.experimentalWindowAnimations.enabled = saved }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by accessibility settings")

        let executor = WindowAnimationExecutor()
        let workerStarted = expectation(description: "Worker is occupied")
        let workerDrained = expectation(description: "Cancelled preparation drained")
        let release = DispatchSemaphore(value: 0)
        executor.performPlacementWork {
            workerStarted.fulfill()
            _ = release.wait(timeout: .now() + 2)
        }
        wait(for: [workerStarted], timeout: 1)
        let window = QueuedWindow()
        let destination = CGRect(x: 100, y: 100, width: 500, height: 400)
        var cancellations = 0
        var completions = 0
        executor.animate(window, to: destination, duration: 0.18, resizeOnly: false, releasedSnap: false,
                         placement: nil, profile: .standard, offset: { .zero }, curve: WindowAnimationCurve.value,
                         cancellation: { cancellations += 1 }) { _ in completions += 1 }
        XCTAssertEqual(executor.destination(for: window), destination)
        XCTAssertEqual(window.minimumSizeReads, 0, "Optional AX metadata must never be queried through the main-thread handle")
        executor.cancel()
        executor.performPlacementWork { workerDrained.fulfill() }
        release.signal()
        wait(for: [workerDrained], timeout: 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(window.minimumSizeReads, 0)
    }

    func testCancellationRunsCleanupOnceAfterInvalidatingWrites() {
        var cancellations = 0
        var request: WindowAnimationRequest!
        request = WindowAnimationRequest(cancellation: {
            XCTAssertFalse(request.isCurrent)
            cancellations += 1
        })
        XCTAssertTrue(request.isCurrent)
        request.cancel()
        request.cancel()
        request.complete()
        XCTAssertEqual(cancellations, 1)
    }

    func testCompletedRequestDoesNotRunCancellationCleanup() {
        var cancellations = 0
        let request = WindowAnimationRequest(cancellation: { cancellations += 1 })
        request.complete()
        request.cancel()
        XCTAssertFalse(request.isCurrent)
        XCTAssertEqual(cancellations, 0)
    }

    func testCancelledPlacementDoesNotCallOrdinaryCompletion() {
        var completions = 0
        var dismissals = 0
        let parameters = ExecutionParameters(.rightHalf, source: .dragToSnap,
            completion: { completions += 1 }, cancellation: { dismissals += 1 })
        let request = WindowAnimationRequest(cancellation: parameters.cancellation)
        request.cancel()
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(completions, 0)
    }

    func testSupersededPendingWriteRunsOnlyCancellationCleanup() {
        let executor = WindowAnimationExecutor()
        let workerStarted = expectation(description: "Worker is occupied")
        let cancelled = expectation(description: "Pending placement was cancelled")
        let release = DispatchSemaphore(value: 0)
        executor.performPlacementWork {
            workerStarted.fulfill()
            _ = release.wait(timeout: .now() + 2)
        }
        wait(for: [workerStarted], timeout: 1)
        var completions = 0
        executor.afterPendingWrites(cancellation: { cancelled.fulfill() }) { completions += 1 }
        executor.cancel()
        release.signal()
        wait(for: [cancelled], timeout: 1)
        XCTAssertEqual(completions, 0)
    }
}

@MainActor
final class FootprintGeometrySynchronizationTests: XCTestCase {
    func testColdAndRepeatedPreviewKeepsMaterialInsideSurface() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let blur = Defaults.footprintBlur.toCodable()
        let alpha = Defaults.footprintAlpha.toCodable()
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintBlur.load(from: blur)
            Defaults.footprintAlpha.load(from: alpha)
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.footprintAlpha.value = 0.3
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        for blurred in [true, false] {
            Defaults.footprintBlur.enabled = blurred
            let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
            defer { window.close() }
            let surface = try XCTUnwrap(window.contentView?.subviews.last)
            let material = try XCTUnwrap(surface.subviews.first)
            for _ in 0..<2 {
                window.showPreview(in: target, from: CGPoint(x: target.minX + 4, y: target.midY), duration: 0.24)
                let until = CACurrentMediaTime() + 0.32
                while CACurrentMediaTime() < until {
                    try await Task.sleep(nanoseconds: 8_000_000)
                    let bounds = surface.layer?.presentation()?.bounds ?? surface.bounds
                    let inner = material.layer?.presentation()?.frame ?? material.frame
                    XCTAssertEqual(inner.width, bounds.width, accuracy: 1)
                    XCTAssertEqual(inner.height, bounds.height, accuracy: 1)
                }
                let settlementDeadline = CACurrentMediaTime() + 2
                while WindowAnimationCaptureGate.shared.isPaused && CACurrentMediaTime() < settlementDeadline {
                    try await Task.sleep(nanoseconds: 8_000_000)
                }
                XCTAssertEqual(surface.frame.width, target.width, accuracy: 1)
                XCTAssertEqual(surface.frame.height, target.height, accuracy: 1)
                XCTAssertFalse(WindowAnimationCaptureGate.shared.isPaused)
                window.orderOut(nil)
                try await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    func testRetargetAndCloseDoNotLeavePreviewGeometryRunning() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let left = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        window.showPreview(in: left, from: CGPoint(x: left.minX + 4, y: left.midY), duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        window.movePreview(to: left.offsetBy(dx: left.width, dy: 0), duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        window.close()
        let surface = try XCTUnwrap(window.contentView?.subviews.last)
        let closedFrame = surface.frame
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(surface.frame, closedFrame)
        XCTAssertFalse(window.realIsVisible)
        XCTAssertFalse(WindowAnimationCaptureGate.shared.isPaused)
    }
}


class VerticalEighthActionTests: XCTestCase {

    private let actions: [WindowAction] = [
        .firstVerticalEighth, .secondVerticalEighth, .thirdVerticalEighth, .fourthVerticalEighth,
        .fifthVerticalEighth, .sixthVerticalEighth, .seventhVerticalEighth, .lastVerticalEighth
    ]

    func testVerticalEighthActionsUseAvailableStableIdentifiers() {
        XCTAssertEqual([
            WindowAction.tileRows.rawValue,
            WindowAction.tileColumns.rawValue,
            WindowAction.cycleStackedWindows.rawValue,
            WindowAction.cycleStackedWindowsBackward.rawValue
        ], [129, 130, 131, 132])
        XCTAssertEqual(actions.map(\.rawValue), [133, 134, 135, 136, 137, 138, 139, 140])
        XCTAssertEqual(actions.map(\.name), [
            "firstVerticalEighth", "secondVerticalEighth", "thirdVerticalEighth", "fourthVerticalEighth",
            "fifthVerticalEighth", "sixthVerticalEighth", "seventhVerticalEighth", "lastVerticalEighth"
        ])
    }

    func testVerticalEighthActionsTileVisibleFrameIntoEightFullHeightColumns() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 3840, height: 1000)
        let expected = (0..<8).map { CGRect(x: CGFloat($0 * 480), y: 40, width: 480, height: 1000) }
        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalEighthActionsUseBoundaryRoundingAcrossNonDivisibleLandscapeWidth() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1003, height: 800)
        let expected = [
            CGRect(x: 20, y: 40, width: 125, height: 800),
            CGRect(x: 145, y: 40, width: 125, height: 800),
            CGRect(x: 270, y: 40, width: 126, height: 800),
            CGRect(x: 396, y: 40, width: 125, height: 800),
            CGRect(x: 521, y: 40, width: 125, height: 800),
            CGRect(x: 646, y: 40, width: 126, height: 800),
            CGRect(x: 772, y: 40, width: 125, height: 800),
            CGRect(x: 897, y: 40, width: 126, height: 800)
        ]

        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalEighthActionsRotateIntoTopToBottomRowsOnPortraitDisplays() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 1003)
        let expected = [
            CGRect(x: 20, y: 918, width: 800, height: 125),
            CGRect(x: 20, y: 793, width: 800, height: 125),
            CGRect(x: 20, y: 667, width: 800, height: 126),
            CGRect(x: 20, y: 542, width: 800, height: 125),
            CGRect(x: 20, y: 417, width: 800, height: 125),
            CGRect(x: 20, y: 291, width: 800, height: 126),
            CGRect(x: 20, y: 166, width: 800, height: 125),
            CGRect(x: 20, y: 40, width: 800, height: 126)
        ]

        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testFirstVerticalEighthCyclesForwardAndWraps() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            let results = repeatedResults(for: .firstVerticalEighth, count: 9, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map { $0.rect.minX }, [20, 120, 220, 320, 420, 520, 620, 720, 20])
        }
    }

    func testLastVerticalEighthCyclesBackwardAndWraps() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            let results = repeatedResults(for: .lastVerticalEighth, count: 9, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map { $0.rect.minX }, [720, 620, 520, 420, 320, 220, 120, 20, 720])
        }
    }

    func testEndpointCyclingResetsForUnrelatedOrOppositeLastAction() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            let unrelated = RectangleAction(action: .leftHalf, subAction: .leftThird, rect: .zero)
            XCTAssertEqual(calculate(.firstVerticalEighth, visibleFrame: visibleFrame, lastAction: unrelated).rect.minX, 20)
            XCTAssertEqual(calculate(.lastVerticalEighth, visibleFrame: visibleFrame, lastAction: unrelated).rect.minX, 720)

            let lastResult = calculate(.lastVerticalEighth, visibleFrame: visibleFrame)
            let lastEndpoint = RectangleAction(action: .lastVerticalEighth, subAction: lastResult.subAction, rect: lastResult.rect)
            XCTAssertEqual(calculate(.firstVerticalEighth, visibleFrame: visibleFrame, lastAction: lastEndpoint).rect.minX, 20)

            let firstResult = calculate(.firstVerticalEighth, visibleFrame: visibleFrame)
            let firstEndpoint = RectangleAction(action: .firstVerticalEighth, subAction: firstResult.subAction, rect: firstResult.rect)
            XCTAssertEqual(calculate(.lastVerticalEighth, visibleFrame: visibleFrame, lastAction: firstEndpoint).rect.minX, 720)
        }
    }

    func testEndpointCyclingIsDisabledWhenSubsequentExecutionModeIsNone() {
        withSubsequentExecutionMode(.none) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            XCTAssertEqual(repeatedResults(for: .firstVerticalEighth, count: 3, visibleFrame: visibleFrame).map { $0.rect.minX },
                           [20, 20, 20])
            XCTAssertEqual(repeatedResults(for: .lastVerticalEighth, count: 3, visibleFrame: visibleFrame).map { $0.rect.minX },
                           [720, 720, 720])
        }
    }

    func testMiddleVerticalEighthActionsStayAtTheirOwnOrdinalWhenRepeated() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            for (index, action) in actions.dropFirst().dropLast().enumerated() {
                let expectedX = CGFloat(120 + index * 100)
                let results = repeatedResults(for: action, count: 3, visibleFrame: visibleFrame)
                XCTAssertEqual(results.map { $0.rect.minX }, [expectedX, expectedX, expectedX])
            }
        }
    }

    func testVerticalEighthResultingSubActionsProvideLandscapeGapEdges() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1003, height: 800)
        let expected: [Edge] = [
            .right,
            [.left, .right], [.left, .right], [.left, .right],
            [.left, .right], [.left, .right], [.left, .right],
            .left
        ]

        for (index, action) in actions.enumerated() {
            XCTAssertEqual(calculate(action, visibleFrame: visibleFrame).subAction?.gapSharedEdge, expected[index])
        }
    }

    func testVerticalEighthResultingSubActionsProvidePortraitGapEdges() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 1003)
        let expected: [Edge] = [
            .bottom,
            [.top, .bottom], [.top, .bottom], [.top, .bottom],
            [.top, .bottom], [.top, .bottom], [.top, .bottom],
            .top
        ]

        for (index, action) in actions.enumerated() {
            XCTAssertEqual(calculate(action, visibleFrame: visibleFrame).subAction?.gapSharedEdge, expected[index])
        }
    }

    func testVerticalEighthActionsRemainTerminalConfigurableThroughActiveActionNames() {
        let suiteName = "VerticalEighthActionTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let shortcut = MASShortcut(keyCode: 18, modifierFlags: [.control, .option, .shift])
        let transformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        userDefaults.set(transformer.reverseTransformedValue(shortcut), forKey: WindowAction.firstVerticalEighth.name)

        XCTAssertTrue(WindowAction.active.contains(.firstVerticalEighth))
        let loaded = ShortcutCycle.shortcutsByAction(userDefaults: userDefaults)[.firstVerticalEighth]
        XCTAssertEqual(loaded?.keyCode, shortcut.keyCode)
        XCTAssertEqual(loaded?.modifierFlags, shortcut.modifierFlags)
    }

    func testVerticalEighthActionsAreHiddenFromNormalUI() throws {
        XCTAssertTrue(actions.allSatisfy(\.excludedFromMenu))
        XCTAssertTrue(actions.allSatisfy { !$0.isDragSnappable })

        let controller = ShortcutsViewController()
        _ = controller.view
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        let rootCount = controller.outlineView(outlineView, numberOfChildrenOfItem: nil)

        var found: [WindowAction] = []
        func collect(from item: Any?) {
            let count = controller.outlineView(outlineView, numberOfChildrenOfItem: item)
            for index in 0..<count {
                let child = controller.outlineView(outlineView, child: index, ofItem: item)
                if let shortcut = child as? ShortcutItem, actions.contains(shortcut.action) {
                    found.append(shortcut.action)
                }
                collect(from: child)
            }
        }

        for index in 0..<rootCount {
            collect(from: controller.outlineView(outlineView, child: index, ofItem: nil))
        }

        XCTAssertTrue(found.isEmpty)
    }

    private func calculate(_ action: WindowAction,
                           visibleFrame: CGRect,
                           lastAction: RectangleAction? = nil) -> RectResult {
        WindowCalculationFactory.calculationsByAction[action]!.calculateRect(
            RectCalculationParameters(window: Window(id: 1, rect: visibleFrame),
                                      visibleFrameOfScreen: visibleFrame,
                                      action: action,
                                      lastAction: lastAction)
        )
    }

    private func repeatedResults(for action: WindowAction,
                                 count: Int,
                                 visibleFrame: CGRect) -> [RectResult] {
        var lastAction: RectangleAction?
        return (0..<count).map { _ in
            let result = calculate(action, visibleFrame: visibleFrame, lastAction: lastAction)
            lastAction = RectangleAction(action: action, subAction: result.subAction, rect: result.rect)
            return result
        }
    }

    private func withSubsequentExecutionMode(_ mode: SubsequentExecutionMode, _ body: () -> Void) {
        let saved = Defaults.subsequentExecutionMode.value
        defer { Defaults.subsequentExecutionMode.value = saved }
        Defaults.subsequentExecutionMode.value = mode
        body()
    }

    private func findOutlineView(in view: NSView) -> NSOutlineView? {
        if let outlineView = view as? NSOutlineView { return outlineView }
        for subview in view.subviews {
            if let outlineView = findOutlineView(in: subview) { return outlineView }
        }
        return nil
    }
}

@MainActor
final class LayoutHelperKeyboardEntryTests: XCTestCase {
    private let region = CGRect(x: 40, y: 40, width: 640, height: 520)
    private var items: [LayoutHelperPanel.Item] {
        [.init(id: 1, title: "First", icon: nil, unavailableReason: nil),
         .init(id: 2, title: "Second", icon: nil, unavailableReason: nil)]
    }

    private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { (($0 as? NSButton).map { [$0] } ?? []) + buttons(in: $0) }
    }

    private func press(_ code: UInt16, in panel: LayoutHelperPanel) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        panel.sendEvent(event)
    }

    func testPointerEntryFirstNavigationSelectsFirst() throws {
        let panel = LayoutHelperPanel()
        defer { panel.close() }
        for code: UInt16 in [48, 123, 124, 125, 126] {
            panel.configure(in: region, items: items, offerPermission: false)
            panel.makeFirstResponder(panel.initialFirstResponder)
            XCTAssertTrue(panel.initialFirstResponder === panel.contentView)
            XCTAssertFalse(panel.keyboardSelection)
            try press(code, in: panel)
            XCTAssertTrue(panel.keyboardSelection)
            XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "First")
        }
        try press(124, in: panel)
        XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "Second")
    }

    func testKeyboardTriggeredNavigationAdvancesImmediately() throws {
        let panel = LayoutHelperPanel()
        defer { panel.close() }
        panel.configure(in: region, items: items, offerPermission: false, keyboardTriggered: true)
        panel.makeFirstResponder(panel.initialFirstResponder)
        XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "First")
        try press(124, in: panel)
        XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "Second")
    }

    func testPointerActivationSelectsFirstDespiteStaleResponder() throws {
        let panel = LayoutHelperPanel()
        defer { panel.close() }
        var selected: CGWindowID?
        panel.onSelect = { selected = $0 }
        for code: UInt16 in [36, 76, 49] {
            panel.configure(in: region, items: items, offerPermission: false)
            let root = try XCTUnwrap(panel.contentView)
            let staleResponder = try XCTUnwrap(buttons(in: root).first { $0.title == "Second" })
            XCTAssertTrue(panel.makeFirstResponder(staleResponder))
            selected = nil
            try press(code, in: panel)
            XCTAssertEqual(selected, 1)
        }
    }

    func testFirstNavigationSkipsDisabledAndHiddenCards() throws {
        let panel = LayoutHelperPanel()
        defer { panel.close() }
        let candidates: [LayoutHelperPanel.Item] = [
            .init(id: 1, title: "Disabled", icon: nil, unavailableReason: "Unavailable"),
            .init(id: 2, title: "Hidden", icon: nil, unavailableReason: nil),
            .init(id: 3, title: "Ready", icon: nil, unavailableReason: nil)]
        let image = NSImage(size: NSSize(width: 80, height: 50))
        panel.configure(in: region, items: candidates, offerPermission: false,
                        images: [1: image, 3: image], waitForPreviews: true)
        panel.makeFirstResponder(panel.initialFirstResponder)
        try press(124, in: panel)
        XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "Ready")
    }

    func testMouseInputRestartsKeyboardSelection() throws {
        let panel = LayoutHelperPanel()
        defer { panel.close() }
        panel.configure(in: region, items: items, offerPermission: false, keyboardTriggered: true)
        panel.makeFirstResponder(panel.initialFirstResponder)
        try press(124, in: panel)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 1, y: 1),
            modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        panel.sendEvent(event)
        XCTAssertFalse(panel.keyboardSelection)
        XCTAssertFalse(panel.firstResponder is NSButton)
        try press(124, in: panel)
        XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "First")
    }
}

final class LayoutHelperSnapPlacementTests: XCTestCase {
    private final class Window: AccessibilityElement {
        var actual: CGRect
        let canResize: Bool
        let minimum: CGSize
        let maximum: CGSize
        let aspectRatio: CGFloat?
        var resizeRequests = 0

        init(frame: CGRect, canResize: Bool = true, minimum: CGSize = .zero,
             maximum: CGSize = CGSize(width: 420, height: 360), aspectRatio: CGFloat? = nil) {
            actual = frame; self.canResize = canResize; self.minimum = minimum
            self.maximum = maximum; self.aspectRatio = aspectRatio
            super.init(AXUIElementCreateSystemWide())
        }
        override var frame: CGRect { actual }
        override var minimumSize: CGSize? { minimum }
        override func isResizable() -> Bool { canResize }
        override var isSystemDialog: Bool? { false }
        override var isWindow: Bool? { false }
        override func setFrame(_ target: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            let before = actual
            if adjustPosition { actual.origin = target.origin }
            if canResize, target.size != before.size {
                resizeRequests += 1
                actual.size = CGSize(width: min(maximum.width, max(minimum.width, target.width)),
                                     height: min(maximum.height, max(minimum.height, target.height)))
                if let aspectRatio { actual.size.height = actual.width / aspectRatio }
            }
        }
    }
    private var savedAlignment: EdgeAlignment!
    private var savedGap: Float!

    override func setUp() {
        super.setUp()
        savedAlignment = Defaults.moveFixedSizeToEdge.value
        savedGap = Defaults.gapSize.value
        Defaults.moveFixedSizeToEdge.value = .edgesAndCorners
        Defaults.gapSize.value = 0
    }
    override func tearDown() {
        Defaults.moveFixedSizeToEdge.value = savedAlignment
        Defaults.gapSize.value = savedGap
        super.tearDown()
    }

    private func snap(_ window: Window, to target: CGRect, initial: CGRect, bounds: CGRect) throws -> CGRect {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var calculation = WindowCalculationResult(rect: target.screenFlipped, screen: screen, resultingAction: .specified)
        calculation.initialRect = initial.screenFlipped
        let result = ResultParameters(windowId: nil, action: .specified, windowElement: window,
            calcResult: calculation, usableScreens: UsableScreens(currentScreen: screen, numScreens: 1),
            visibleFrameOfScreen: bounds.screenFlipped, source: .menuItem, isFixedSize: !window.canResize)
        return WindowManager().apply(result: result)
    }
    private func acknowledge(_ frame: CGRect, target: CGRect, initial: CGRect, bounds: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        let placement = WindowAnimationPlacement(screenFrame: bounds,
            sharedEdges: Defaults.moveFixedSizeToEdge.value.alignmentEdges(for: initial, in: bounds),
            constrainToScreen: true, gap: CGFloat(Defaults.gapSize.value))
        var state = WindowPlacementAcknowledgement(target: target, startedAt: 0, pendingWrite: false,
            bounds: bounds, placement: placement)
        guard case .waiting = state.observe(frame, at: 0) else {
            return XCTFail("A regular snap's accepted frame should settle without another resize", file: file, line: line)
        }
        guard case .complete(let actual) = state.observe(frame, at: 0.04) else {
            return XCTFail("An aligned size-limited window is a successful placement", file: file, line: line)
        }
        XCTAssertEqual(actual, frame, file: file, line: line)
    }

    func testMaximumSizeWindowUsesRegularRightSnapPlacement() throws {
        let bounds = CGRect(x: 0, y: 29, width: 1400, height: 900)
        let target = CGRect(x: 700, y: 29, width: 700, height: 900)
        let window = Window(frame: CGRect(x: 100, y: 100, width: 420, height: 360))
        let actual = try snap(window, to: target, initial: target, bounds: bounds)
        XCTAssertEqual(actual.maxX, bounds.maxX)
        XCTAssertEqual(actual.midY, target.midY, accuracy: 0.5)
        acknowledge(actual, target: target, initial: target, bounds: bounds)
    }

    func testFixedSizeWindowIsPlacedWithoutAnyResizeRequest() throws {
        let bounds = CGRect(x: 0, y: 29, width: 1400, height: 900)
        let target = CGRect(x: 700, y: 29, width: 700, height: 900)
        let window = Window(frame: CGRect(x: 100, y: 100, width: 420, height: 360), canResize: false)
        let actual = try snap(window, to: target, initial: target, bounds: bounds)
        XCTAssertEqual(window.resizeRequests, 0)
        XCTAssertEqual(actual.maxX, bounds.maxX)
        acknowledge(actual, target: target, initial: target, bounds: bounds)
    }

    func testFixedSizeWindowMovesWhenEitherDimensionAlreadyMatchesTheZone() throws {
        let bounds = CGRect(x: 0, y: 29, width: 1400, height: 900)
        let target = CGRect(x: 700, y: 29, width: 700, height: 900)
        for size in [CGSize(width: 700, height: 360), CGSize(width: 420, height: 900), target.size] {
            let window = Window(frame: CGRect(origin: CGPoint(x: 100, y: 100), size: size), canResize: false)
            let actual = try snap(window, to: target, initial: target, bounds: bounds)
            XCTAssertEqual(actual.maxX, bounds.maxX)
            XCTAssertEqual(actual.midY, target.midY, accuracy: 0.5)
            acknowledge(actual, target: target, initial: target, bounds: bounds)
        }
    }

    func testMinimumMaximumAndAspectRatioWindowsUseRegularSnapAlignment() throws {
        let bounds = CGRect(x: -2400, y: -600, width: 2400, height: 1400)
        let zones = [CGRect(x: bounds.midX, y: bounds.minY, width: 1200, height: 1400),
                     CGRect(x: bounds.minX, y: bounds.minY, width: 1200, height: 700),
                     CGRect(x: bounds.midX, y: bounds.midY, width: 1200, height: 700),
                     CGRect(x: bounds.minX, y: bounds.midY, width: 2400, height: 700)]
        for alignment in [EdgeAlignment.edgesAndCorners, .corners, .centered, .leadingCorner] {
            Defaults.moveFixedSizeToEdge.value = alignment
            for target in zones {
                for kind in 0..<4 {
                    let window = Window(frame: CGRect(x: -2000, y: -400, width: 500, height: 400),
                        minimum: kind == 0 ? CGSize(width: 1300, height: 800) : (kind == 3 ? CGSize(width: 2500, height: 1500) : .zero),
                        maximum: kind == 0 ? CGSize(width: 2000, height: 1200) : (kind == 3 ? CGSize(width: 3000, height: 2000) : CGSize(width: 900, height: 600)),
                        aspectRatio: kind == 2 ? 16.0 / 9.0 : nil)
                    let actual = try snap(window, to: target, initial: target, bounds: bounds)
                    acknowledge(actual, target: target, initial: target, bounds: bounds)
                }
            }
        }
    }

    func testGappedRightSnapKeepsTheScreenEdgeAlignment() throws {
        Defaults.gapSize.value = 12
        let bounds = CGRect(x: -1600, y: -870, width: 1600, height: 900)
        let initial = CGRect(x: -800, y: -870, width: 800, height: 900)
        let target = CGRect(x: -794, y: -870, width: 782, height: 888)
        let window = Window(frame: CGRect(x: -1400, y: -700, width: 420, height: 360))
        let actual = try snap(window, to: target, initial: initial, bounds: bounds)
        XCTAssertEqual(actual.maxX, bounds.maxX - 12)
        acknowledge(actual, target: target, initial: initial, bounds: bounds)
    }

    func testIgnoredPositionRequestStillFailsAfterBoundedRetries() {
        let bounds = CGRect(x: 0, y: 29, width: 1400, height: 900)
        let target = CGRect(x: 700, y: 29, width: 700, height: 900)
        let placement = WindowAnimationPlacement(screenFrame: bounds,
            sharedEdges: target.sharedEdges(withRect: bounds), constrainToScreen: true, gap: 0)
        let misplaced = CGRect(x: 100, y: 100, width: 420, height: 360)
        var state = WindowPlacementAcknowledgement(target: target, startedAt: 0, pendingWrite: false,
            bounds: bounds, placement: placement)
        for time: TimeInterval in [0, 0.7] {
            guard case .position = state.observe(misplaced, at: time) else { return XCTFail("Retry the refused move") }
        }
        guard case .failed = state.observe(misplaced, at: 1.4) else { return XCTFail("A refused move must not become success") }
    }

    func testRollbackRequiresTheOriginalSizeRatherThanAcceptingAClamp() {
        let original = CGRect(x: 100, y: 100, width: 420, height: 360)
        let refused = CGRect(x: 100, y: 100, width: 700, height: 878)
        var state = WindowPlacementAcknowledgement(target: original, startedAt: 0, pendingWrite: false,
            bounds: CGRect(x: 0, y: 29, width: 1440, height: 878))
        for time: TimeInterval in [0, 0.7] {
            guard case .size(let requested) = state.observe(refused, at: time) else { return XCTFail("Rollback must retry the original size") }
            XCTAssertEqual(requested, original.size)
        }
        guard case .failed = state.observe(refused, at: 1.4) else { return XCTFail("An inexact rollback must not be reported as restored") }
    }

    func testRelayoutNeedsAStableFrameAndMissingReadbackNeverSucceeds() {
        let bounds = CGRect(x: 0, y: 29, width: 1400, height: 900)
        let target = CGRect(x: 700, y: 29, width: 700, height: 900)
        let placement = WindowAnimationPlacement(screenFrame: bounds,
            sharedEdges: target.sharedEdges(withRect: bounds), constrainToScreen: true, gap: 0)
        var state = WindowPlacementAcknowledgement(target: target, startedAt: 0, pendingWrite: false,
            bounds: bounds, placement: placement)
        let first = placement.frame(for: target, actualSize: CGSize(width: 300, height: 200), origin: target, progress: 1)
        let second = placement.frame(for: target, actualSize: CGSize(width: 420, height: 360), origin: target, progress: 1)
        guard case .waiting = state.observe(nil, at: 0),
              case .waiting = state.observe(first, at: 0.01),
              case .waiting = state.observe(second, at: 0.06),
              case .complete(let actual) = state.observe(second, at: 0.10) else {
            return XCTFail("A changed size must settle again before committing")
        }
        XCTAssertEqual(actual, second)
    }
}


final class LayoutHelperMinimizedWindowTests: XCTestCase {
    private func desktop(_ display: String, id: UInt64, type: Int = 0) -> [String: Any] {
        ["Display Identifier": display, "Current Space": ["id64": NSNumber(value: id), "type": type],
         "Spaces": [["id64": NSNumber(value: id + 100), "type": 0]]]
    }

    func testDesktopScopeUsesOnlyEachDisplaysCurrentDesktop() {
        let result = LayoutHelperDesktopScope.activeDesktops([desktop("left", id: 11), desktop("right", id: 22)],
            displays: ["left": 1, "right": 2], separateSpaces: true)
        XCTAssertEqual(result, [11: [1], 22: [2]])
        XCTAssertNil(result[111], "Other desktops in the Spaces list are not candidates")
    }

    func testSharedDesktopCoversBothDisplaysAndFullscreenIsExcluded() {
        let displays: [String: CGDirectDisplayID] = ["left": 1, "right": 2]
        XCTAssertEqual(LayoutHelperDesktopScope.activeDesktops([desktop("left", id: 11)],
            displays: displays, separateSpaces: false), [11: [1, 2]])
        XCTAssertEqual(LayoutHelperDesktopScope.activeDesktops([desktop("Main", id: 11)],
            displays: displays, separateSpaces: true), [11: [1, 2]])
        XCTAssertTrue(LayoutHelperDesktopScope.activeDesktops([desktop("left", id: 11, type: 4)],
            displays: displays, separateSpaces: true).isEmpty)
    }

    func testUnknownDesktopMetadataDoesNotAdmitMinimizedWindows() {
        let invalid: [[String: Any]] = [desktop("disconnected", id: 11), desktop("left", id: 0),
            ["Display Identifier": "left", "Current Space": ["id64": 33]], [:]]
        XCTAssertTrue(LayoutHelperDesktopScope.activeDesktops(invalid, displays: ["left": 1], separateSpaces: true).isEmpty)
        XCTAssertFalse(LayoutHelperWindowCatalog.admits(onScreen: false, minimized: true, desktopDisplays: []))
        XCTAssertTrue(LayoutHelperWindowCatalog.admits(onScreen: false, minimized: true, desktopDisplays: [1]))
        XCTAssertFalse(LayoutHelperWindowCatalog.admits(onScreen: false, minimized: false, desktopDisplays: [1]))
        XCTAssertFalse(LayoutHelperWindowCatalog.admits(onScreen: false, minimized: nil, desktopDisplays: [1]))
        XCTAssertTrue(LayoutHelperWindowCatalog.admits(onScreen: true, minimized: nil, desktopDisplays: []))
    }

    func testRestoreWaitsForUnminimizedStateAndFreshGeometry() {
        var time: TimeInterval = 0, writes = 0, pauses = 0, frameReads = 0
        let actual = CGRect(x: 130, y: 80, width: 470, height: 290)
        let outcome = LayoutHelperWindowRestoration.acknowledge(isCurrent: { true },
            minimized: { pauses < 2 }, restore: { writes += 1; return .success },
            frame: { frameReads += 1; return pauses < 3 ? nil : actual },
            now: { time }, pause: { pauses += 1; time += 0.1 })
        guard case .placed(let frame) = outcome else { return XCTFail("Restoration must acknowledge actual state") }
        XCTAssertEqual(frame, actual)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(pauses, 3)
        XCTAssertEqual(frameReads, 2)
    }

    func testRestoreRefusalDoesNotReadPlacementGeometry() {
        var reads = 0
        let outcome = LayoutHelperWindowRestoration.acknowledge(isCurrent: { true }, minimized: { true },
            restore: { .attributeUnsupported }, frame: { reads += 1; return .zero })
        guard case .failed = outcome else { return XCTFail("Refused restoration must fail") }
        XCTAssertEqual(reads, 0)
    }

    func testCancelledRestoreAndAlreadyRestoredWindowDoNotWrite() {
        var writes = 0
        let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
        let cancelled = LayoutHelperWindowRestoration.acknowledge(isCurrent: { false }, minimized: { true },
            restore: { writes += 1; return .success }, frame: { rect })
        guard case .cancelled = cancelled else { return XCTFail("Cancelled selection must not restore") }
        let restored = LayoutHelperWindowRestoration.acknowledge(isCurrent: { true }, minimized: { false },
            restore: { writes += 1; return .success }, frame: { rect })
        guard case .placed = restored else { return XCTFail("An externally restored window remains selectable") }
        XCTAssertEqual(writes, 0)
    }

    func testUnacknowledgedRestorationTimesOutWithoutPlacement() {
        var time: TimeInterval = 0, frameReads = 0, writes = 0
        let outcome = LayoutHelperWindowRestoration.acknowledge(isCurrent: { true }, minimized: { true },
            restore: { writes += 1; return .success }, frame: { frameReads += 1; return .zero },
            now: { time }, pause: { time += 0.1 })
        guard case .unresponsive = outcome else { return XCTFail("An accepted write is not completed restoration") }
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(frameReads, 0)
        XCTAssertLessThan(time, 1.7)
    }

    @MainActor func testMinimizedFallbackAppearsOnlyAfterCaptureFailure() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let minimized = LayoutHelperPanel.Item(id: 7, title: "Small minimized window", icon: nil,
            unavailableReason: nil, sourceSize: CGSize(width: 90, height: 60), isMinimized: true)
        panel.configure(in: CGRect(x: 30, y: 30, width: 640, height: 480),
            items: [minimized, .init(id: 8, title: "Visible window", icon: nil, unavailableReason: nil)],
            offerPermission: false, waitForPreviews: true)
        func buttons(_ view: NSView) -> [NSButton] {
            view.subviews.flatMap { (($0 as? NSButton).map { [$0] } ?? []) + buttons($0) }
        }
        let cards = buttons(try XCTUnwrap(panel.contentView))
        let card = try XCTUnwrap(cards.first { $0.title == minimized.title })
        XCTAssertTrue(card.isHidden, "A pending minimized capture must not expose the white icon fallback")
        panel.previewFailed(for: 7)
        XCTAssertFalse(card.isHidden, "A failed capture must reveal a selectable fallback")
        XCTAssertTrue(card.accessibilityLabel()?.contains("Preview unavailable") == true)
        XCTAssertTrue(card.isEnabled)
        XCTAssertTrue(card.accessibilityLabel()?.contains("minimized") == true)
        XCTAssertTrue(cards.first { $0.title == "Visible window" }?.isHidden == true)
        var selected: CGWindowID?
        panel.onSelect = { selected = $0 }
        card.performClick(nil)
        XCTAssertEqual(selected, 7)
        panel.updateImage(NSImage(size: CGSize(width: 180, height: 120)), for: 7)
        XCTAssertFalse(card.accessibilityLabel()?.contains("Preview unavailable") == true)
    }
}

@MainActor
final class LayoutHelperMinimizedAspectTests: XCTestCase {
    private func cards(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { (($0 as? NSButton).map { [$0] } ?? []) + cards(in: $0) }
    }
    private func card(in panel: LayoutHelperPanel, title: String) throws -> NSButton {
        try XCTUnwrap(cards(in: try XCTUnwrap(panel.contentView)).first { $0.title == title })
    }
    private func image(_ size: CGSize) -> NSImage { NSImage(size: size) }
    private func assertAspect(_ frame: CGRect, source: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frame.width / (frame.height - LayoutHelperPreviewLayout.titleHeight), source.width / source.height,
                       accuracy: 0.001, file: file, line: line)
    }
    func testPortraitMinimizedWindowKeepsItsAspectOnFirstAndCachedLoads() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let source = CGSize(width: 240, height: 600)
        let item = LayoutHelperPanel.Item(id: 7, title: "Portrait minimized", icon: nil,
            unavailableReason: nil, sourceSize: source, isMinimized: true)
        let region = CGRect(x: 30, y: 30, width: 640, height: 480)
        panel.configure(in: region, items: [item], offerPermission: false, waitForPreviews: true)
        let cold = try card(in: panel, title: item.title)
        let initial = cold.frame
        XCTAssertTrue(cold.isHidden, "Reserve geometry without showing a white placeholder")
        XCTAssertGreaterThanOrEqual(initial.width, 200)
        assertAspect(initial, source: source)
        let preview = image(CGSize(width: 480, height: 1200))
        panel.updateImage(preview, for: 7)
        XCTAssertFalse(cold.isHidden)
        assertAspect(cold.frame, source: source)
        XCTAssertEqual(cold.frame, initial, "First preview delivery must not change an accurately reserved card")
        panel.configure(in: region, items: [item], offerPermission: false, images: [7: preview])
        let warm = try card(in: panel, title: item.title)
        XCTAssertFalse(warm.isHidden, "Cached captures should appear immediately")
        assertAspect(warm.frame, source: source)
        XCTAssertEqual(warm.frame, initial, "Cached and cold captures must reserve the same geometry")
        var selected: CGWindowID?
        panel.onSelect = { selected = $0 }
        warm.performClick(nil)
        XCTAssertEqual(selected, 7)
    }
    func testFirstMinimizedPreviewRevealsWithoutFadingFromWhite() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let item = LayoutHelperPanel.Item(id: 7, title: "Pending minimized", icon: nil,
            unavailableReason: nil, sourceSize: CGSize(width: 300, height: 200), isMinimized: true)
        panel.configure(in: CGRect(x: 30, y: 30, width: 640, height: 480), items: [item],
            offerPermission: false, waitForPreviews: true)
        panel.orderFront(nil)
        let pending = try card(in: panel, title: item.title)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(pending.isHidden)
        panel.updateImage(image(CGSize(width: 600, height: 400)), for: 7)
        XCTAssertFalse(pending.isHidden)
        let artwork = try XCTUnwrap(pending.subviews.first { String(describing: type(of: $0)) == "LayoutHelperPreviewContent" })
        XCTAssertNil(artwork.layer?.animation(forKey: kCATransition), "The first image must be rendered before card entrance")
    }
    func testWidthFloorPreservesMixedWindowAspectsWhenRowsShrinkOrOverflow() {
        let sizes = [CGSize(width: 240, height: 600), CGSize(width: 900, height: 300), CGSize(width: 400, height: 400)]
        for width: CGFloat in [180, 640, 900] {
            let result = LayoutHelperPreviewLayout.arrange(sizes: sizes, in: CGSize(width: width, height: 180),
                expandedCards: [true, true, true])
            for (source, frame) in zip(sizes, result.frames) {
                XCTAssertGreaterThanOrEqual(frame.width, min(width, 200))
                assertAspect(frame, source: source)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width + 0.001)
            }
            XCTAssertGreaterThan(result.height, 180, "Portrait cards overflow by scrolling instead of changing aspect")
        }
    }
    func testScreenshotRoundingFitsTheSlotUntilItsAspectIsRearranged() {
        let source = CGSize(width: 240, height: 601)
        let slot = LayoutHelperPreviewLayout.arrange(sizes: [source], in: CGSize(width: 600, height: 600),
            expandedCards: [true]).frames[0]
        let imageSize = CGSize(width: 207, height: 520)
        let frame = LayoutHelperPreviewLayout.cardFrame(for: imageSize, in: slot, isMinimized: true)
        XCTAssertTrue(slot.contains(frame), "Preview updates must never exceed their reserved geometry")
        assertAspect(frame, source: imageSize)
        let refreshedSlot = LayoutHelperPreviewLayout.arrange(sizes: [imageSize], in: CGSize(width: 600, height: 600),
            expandedCards: [true]).frames[0]
        let refreshed = LayoutHelperPreviewLayout.cardFrame(for: imageSize, in: refreshedSlot, isMinimized: true)
        XCTAssertGreaterThanOrEqual(refreshed.width, 200)
        assertAspect(refreshed, source: imageSize)
    }
    func testNoPermissionPortraitFallbackStillUsesCompactReadableCard() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let item = LayoutHelperPanel.Item(id: 7, title: "Portrait without permission", icon: nil,
            unavailableReason: nil, sourceSize: CGSize(width: 240, height: 600), isMinimized: true)
        panel.configure(in: CGRect(x: 30, y: 30, width: 640, height: 480), items: [item],
            offerPermission: true, images: [7: image(CGSize(width: 480, height: 1200))])
        let fallback = try card(in: panel, title: item.title)
        XCTAssertEqual(fallback.frame.size, CGSize(width: 200, height: 150))
        XCTAssertTrue(fallback.isEnabled)
        XCTAssertFalse(fallback.isHidden)
    }
}

@MainActor
final class LayoutHelperColdDeliveryLayoutTests: XCTestCase {
    private func buttons(_ view: NSView) -> [NSButton] {
        view.subviews.flatMap { (($0 as? NSButton).map { [$0] } ?? []) + buttons($0) }
    }
    func testMixedCardsNeverOverlapWhenCapturesFinishOutOfOrder() throws {
        let sizes = [CGSize(width:1000,height:600), CGSize(width:1000,height:600),
                     CGSize(width:1000,height:600), CGSize(width:1000,height:600),
                     CGSize(width:240,height:600), CGSize(width:1000,height:600)]
        let items = sizes.enumerated().map { index,size in
            LayoutHelperPanel.Item(id: CGWindowID(index+1),title: "Window \(index)",icon:nil,
                unavailableReason:nil,sourceSize:size,isMinimized:index==4 || index==0 || index==5)
        }
        for width: CGFloat in [480,640,900] {
            for delivery in [[4,0,1,3,2,5],[5,4,3,2,1,0],[0,1,2,3,4,5]] {
                let panel = LayoutHelperPanel()
                defer { panel.dismiss() }
                panel.configure(in:CGRect(x:30,y:30,width:width,height:800),items:items,
                    offerPermission:false,waitForPreviews:true)
                for index in delivery {
                    let visibleBefore = buttons(try XCTUnwrap(panel.contentView)).filter { !$0.isHidden }
                    let framesBefore = Dictionary(uniqueKeysWithValues:visibleBefore.map { ($0.title,$0.frame) })
                    panel.updateImage(NSImage(size:sizes[index]),for:CGWindowID(index+1))
                    let ready = buttons(try XCTUnwrap(panel.contentView)).filter { !$0.isHidden && $0.title.hasPrefix("Window ") }
                    for card in ready {
                        if let previous=framesBefore[card.title] { XCTAssertEqual(card.frame,previous,"New captures must not move cards already displayed") }
                    }
                    for a in ready.indices { for b in ready.indices where b>a {
                        XCTAssertFalse(ready[a].frame.intersects(ready[b].frame),"Cold delivery \(delivery), width \(width): \(ready[a].title) overlaps \(ready[b].title)")
                    }}
                }
            }
        }
    }
}

final class LayoutHelperPreviewContentValidationTests: XCTestCase {
    private func image(_ width: Int=32,_ height: Int=32,color: CGColor? = nil) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
            bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        if let color { context.setFillColor(color);context.fill(CGRect(x:0,y:0,width:width,height:height)) }
        return try XCTUnwrap(context.makeImage())
    }
    func testRejectsTransparentAndDegenerateCapturesButAcceptsSolidWindows() throws {
        XCTAssertFalse(LayoutHelperPreviewValidation.isValid(try image()))
        XCTAssertFalse(LayoutHelperPreviewValidation.isValid(try image(1,1,color:NSColor.gray.cgColor)))
        for color in [NSColor.white,NSColor.gray,NSColor.black] {
            XCTAssertTrue(LayoutHelperPreviewValidation.isValid(try image(color:color.cgColor)),"Solid content is not an empty capture")
        }
        XCTAssertFalse(LayoutHelperPreviewValidation.validSourceSize(CGSize(width:1,height:1)))
        XCTAssertFalse(LayoutHelperPreviewValidation.validSourceSize(CGSize(width:CGFloat.nan,height:600)))
        XCTAssertTrue(LayoutHelperPreviewValidation.validSourceSize(CGSize(width:240,height:600)))
    }
    func testBadRefreshKeepsLastGoodPreviewWithoutExtendingItsLifetime() throws {
        let cache = LayoutHelperImageCache<Int>()
        let good = try image(color:NSColor.blue.cgColor)
        cache.insert(good,for:7,now:0)
        let bytes=cache.byteCount
        cache.insert(try image(),for:7,now:100)
        XCTAssertTrue(cache.image(for:7,now:100) === good)
        XCTAssertEqual(cache.byteCount,bytes)
        cache.insert(try image(1,1,color:NSColor.gray.cgColor),for:7,now:110)
        XCTAssertTrue(cache.image(for:7,now:110) === good)
        XCTAssertNil(cache.image(for:7,now:121),"A failed refresh must not renew stale content")
    }
    func testLastGoodPreviewIdentityDoesNotCrossProcessRelaunchOrExpiry() throws {
        let cache=LayoutHelperImageCache<LayoutHelperPreviewKey>()
        let old=LayoutHelperPreviewKey(id:7,pid:42,launch:1,width:240,height:600)
        let current=LayoutHelperPreviewKey(id:7,pid:42,launch:1,width:1,height:1)
        let good=try image(color:NSColor.white.cgColor)
        cache.insert(good,for:old,now:0)
        func cached(_ key:LayoutHelperPreviewKey,now:TimeInterval)->CGImage? {
            cache.image(matching:{$0.id==key.id && $0.pid==key.pid && $0.launch==key.launch},now:now)
        }
        XCTAssertTrue(cached(current,now:20) === good)
        XCTAssertNil(cached(.init(id:7,pid:42,launch:2,width:1,height:1),now:20))
        XCTAssertNil(cached(.init(id:7,pid:43,launch:1,width:1,height:1),now:20))
        XCTAssertNil(cached(current,now:121))
    }
    func testScreenshotPreservesPortraitBudgetWithoutWindowFraming() {
        if #available(macOS 26, *) {
            let config = LayoutHelperPreviewStore.screenshotConfiguration(for: CGSize(width: 240, height: 600),
                limit: CGSize(width: 840, height: 520), sourceScale: 2)
            XCTAssertEqual(CGFloat(config.width) / CGFloat(config.height), 0.4, accuracy: 0.002)
            XCTAssertLessThanOrEqual(config.width, 840)
            XCTAssertLessThanOrEqual(config.height, 520)
            XCTAssertFalse(config.showsCursor)
            XCTAssertTrue(config.ignoreShadows)
            XCTAssertTrue(config.ignoreClipping)
        }
    }
}

final class LayoutHelperMinimizedPreparationTests: XCTestCase {
    private let target=CGRect(x:720,y:29,width:720,height:878)
    func testGeometryIsPreparedBeforeRestoreWhileWindowStaysMinimized() {
        var actual=CGRect(x:10,y:10,width:240,height:600)
        var order:[String]=[]
        let prepared=LayoutHelperWindowRestoration.prepare(target:target,isCurrent:{true},minimized:{true},
            size:{actual.size=$0;order.append("size");return .success},
            position:{actual.origin=$0;order.append("position");return .success},frame:{actual})
        XCTAssertTrue(prepared)
        XCTAssertEqual(actual,target)
        XCTAssertEqual(order,["size","position","size"])
    }
    func testRefusingApplicationFallsBackWithoutAdditionalWrites() {
        var positions=0
        XCTAssertFalse(LayoutHelperWindowRestoration.prepare(target:target,isCurrent:{true},minimized:{true},
            size:{_ in .attributeUnsupported},position:{_ in positions+=1;return .success},frame:{nil}))
        XCTAssertEqual(positions,0)
    }
    func testCancellationOrExternalRestoreStopsPreparation() {
        for cancel in [true,false] {
            var active=true,minimized=true,positions=0
            XCTAssertFalse(LayoutHelperWindowRestoration.prepare(target:target,isCurrent:{active},minimized:{minimized},
                size:{_ in if cancel {active=false}else{minimized=false};return .success},
                position:{_ in positions+=1;return .success},frame:{nil}))
            XCTAssertEqual(positions,0)
        }
    }
    func testSlowGeometryAcknowledgementIsBounded() {
        var time:TimeInterval=0
        XCTAssertFalse(LayoutHelperWindowRestoration.prepare(target:target,isCurrent:{true},minimized:{true},
            size:{_ in .success},position:{_ in .success},frame:{nil},now:{time},pause:{time+=0.025}))
        XCTAssertGreaterThanOrEqual(time,0.3)
        XCTAssertLessThan(time,0.4)
    }
}


@MainActor
final class LayoutHelperScrollingTests: XCTestCase {
    private func views<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
        root.subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + views($0, of: type) }
    }
    func testOverflowMarginsScrollAwayAndLastCardIsFullyReachable() throws {
        let previousClose = Defaults.layoutHelperCloseButton.enabled
        Defaults.layoutHelperCloseButton.enabled = true
        defer { Defaults.layoutHelperCloseButton.enabled = previousClose }
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let items = (1...24).map { LayoutHelperPanel.Item(id: CGWindowID($0), title: "Window \($0)",
            icon: nil, unavailableReason: nil, sourceSize: CGSize(width: 600, height: 400)) }
        panel.configure(in: CGRect(x: 0, y: 0, width: 640, height: 480), items: items, offerPermission: false)
        let root = try XCTUnwrap(panel.contentView)
        root.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(views(root, of: NSScrollView.self).first)
        let document = try XCTUnwrap(scroll.documentView)
        let cards = views(document, of: NSButton.self)
        let first = try XCTUnwrap(cards.first)
        let last = try XCTUnwrap(cards.last)
        XCTAssertEqual(scroll.frame, try XCTUnwrap(scroll.superview).bounds, "The viewport must not have fixed padding strips")
        XCTAssertGreaterThan(document.frame.height, scroll.contentSize.height)
        XCTAssertGreaterThanOrEqual(scroll.scrollerInsets.top, LayoutHelperAppearance.cornerRadius)
        XCTAssertGreaterThanOrEqual(scroll.scrollerInsets.bottom, LayoutHelperAppearance.cornerRadius)
        XCTAssertGreaterThan(scroll.scrollerInsets.right, 0)
        XCTAssertGreaterThanOrEqual(first.frame.minY, 40)
        XCTAssertGreaterThanOrEqual(cards.map { $0.frame.minX }.min()!, 20, "Side shadows need space inside the clip view")
        XCTAssertGreaterThanOrEqual(document.bounds.maxY - cards.map { $0.frame.maxY }.max()!, 20)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertLessThan(document.convert(first.frame.origin, to: scroll).y, 0,
            "The initial top margin must move with content")
        scroll.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertTrue(document.visibleRect.contains(last.frame), "The final card must be completely reachable")
        XCTAssertGreaterThanOrEqual(document.visibleRect.maxY - last.frame.maxY, 20)
        let close = try XCTUnwrap(views(root, of: NSButton.self).first { $0.accessibilityLabel() == "Dismiss Layout Helper" })
        let center = close.convert(CGPoint(x: close.bounds.midX, y: close.bounds.midY), to: root.superview)
        let hit = root.hitTest(center)
        XCTAssertTrue(hit === close || hit?.isDescendant(of: close) == true, "The expanded viewport must not intercept the fixed close button")
    }
    func testCloseBlurPreservesHitTargetAboveCards() throws {
        let previousClose = Defaults.layoutHelperCloseButton.enabled
        Defaults.layoutHelperCloseButton.enabled = true
        defer { Defaults.layoutHelperCloseButton.enabled = previousClose }
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        panel.configure(in: CGRect(x: 0, y: 0, width: 640, height: 480), items: [], offerPermission: false)
        let root = try XCTUnwrap(panel.contentView)
        let close = try XCTUnwrap(views(root, of: NSButton.self).first { $0.accessibilityLabel() == "Dismiss Layout Helper" })
        let material = try XCTUnwrap(views(root, of: LayoutHelperBlurView.self).first { close.superview === $0.content })
        XCTAssertEqual(material.blendingMode, .withinWindow)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(close.frame, material.content.bounds)
        XCTAssertNotNil(material.subviews.first as? NSVisualEffectView)
        let center = close.convert(CGPoint(x: close.bounds.midX, y: close.bounds.midY), to: root.superview)
        let hit = root.hitTest(center)
        XCTAssertTrue(hit === close || hit?.isDescendant(of: close) == true)
    }
    func testCloseButtonIsConcentricAndCanBeHiddenWithoutLosingDismissal() throws {
        let previous = Defaults.layoutHelperCloseButton.enabled
        defer { Defaults.layoutHelperCloseButton.enabled = previous }
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        Defaults.layoutHelperCloseButton.enabled = true
        let region = CGRect(x: 0, y: 0, width: 640, height: 480)
        panel.configure(in: region, items: [], offerPermission: false, keyboardTriggered: true)
        let root = try XCTUnwrap(panel.contentView)
        let close = try XCTUnwrap(views(root, of: NSButton.self).first { $0.accessibilityLabel() == "Dismiss Layout Helper" })
        let material = try XCTUnwrap(views(root, of: LayoutHelperBlurView.self).first { close.superview === $0.content })
        let surface = try XCTUnwrap(material.superview)
        XCTAssertEqual(material.frame.midX, surface.bounds.maxX - LayoutHelperAppearance.cornerRadius)
        XCTAssertEqual(material.frame.midY, LayoutHelperAppearance.cornerRadius)
        XCTAssertEqual(material.frame.minY, surface.bounds.maxX - material.frame.maxX)
        XCTAssertGreaterThanOrEqual(material.frame.minY, 10)
        XCTAssertTrue(Defaults.array.contains { $0.key == Defaults.layoutHelperCloseButton.key })
        Defaults.layoutHelperCloseButton.enabled = false
        panel.configure(in: region, items: [], offerPermission: false, keyboardTriggered: true)
        let hiddenRoot = try XCTUnwrap(panel.contentView)
        XCTAssertFalse(views(hiddenRoot, of: NSButton.self).contains { $0.accessibilityLabel() == "Dismiss Layout Helper" })
        XCTAssertFalse(panel.initialFirstResponder is NSButton)
        var dismissed = false
        panel.onDismiss = { dismissed = true }
        panel.cancelOperation(nil)
        XCTAssertTrue(dismissed)
        XCTAssertTrue(panel.isBackground(at: .zero))
    }
    func testPermissionFooterRemainsOutsideScrollingContent() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let items = (1...24).map { LayoutHelperPanel.Item(id: CGWindowID($0), title: "Window \($0)", icon: nil, unavailableReason: nil) }
        panel.configure(in: CGRect(x: 0, y: 0, width: 640, height: 480), items: items, offerPermission: true)
        let root = try XCTUnwrap(panel.contentView)
        let scroll = try XCTUnwrap(views(root, of: NSScrollView.self).first)
        let permission = try XCTUnwrap(views(root, of: NSButton.self).first { $0.toolTip?.contains("Screen Recording") == true })
        XCTAssertFalse(permission.isDescendant(of: try XCTUnwrap(scroll.documentView)))
        XCTAssertGreaterThanOrEqual(permission.frame.minY, scroll.frame.maxY)
    }
}


final class LayoutHelperReviewRegressionTests: XCTestCase {
    private func views<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
        root.subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + views($0, type) }
    }

    @MainActor func testStaleLandscapeCacheRefreshedToPortraitReservesNewRows() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let items = (1...3).map { LayoutHelperPanel.Item(id: CGWindowID($0), title: "Review window \($0)",
            icon: nil, unavailableReason: nil, sourceSize: CGSize(width: 240, height: 600), isMinimized: true) }
        panel.configure(in: CGRect(x: 30, y: 30, width: 480, height: 480), items: items,
            offerPermission: false, images: [1: NSImage(size: CGSize(width: 1000, height: 600))], waitForPreviews: true)
        panel.updateImage(NSImage(size: CGSize(width: 240, height: 600)), for: 1)
        panel.updateImage(NSImage(size: CGSize(width: 240, height: 600)), for: 2)
        panel.updateImage(NSImage(size: CGSize(width: 240, height: 600)), for: 3)
        let root = try XCTUnwrap(panel.contentView)
        let cards = views(root, NSButton.self).filter { $0.title.hasPrefix("Review window") }
        let document = try XCTUnwrap(views(root, NSScrollView.self).first?.documentView)
        XCTAssertEqual(cards.count, 3)
        for a in cards.indices {
            XCTAssertGreaterThanOrEqual(cards[a].frame.width, 200 - 0.001)
            XCTAssertTrue(document.bounds.contains(cards[a].frame))
            for b in cards.indices where b > a { XCTAssertFalse(cards[a].frame.intersects(cards[b].frame)) }
        }
        let card = try XCTUnwrap(cards.first { $0.title == "Review window 1" })
        XCTAssertEqual(card.frame.width / (card.frame.height - 40), 0.4, accuracy: 0.001)
    }

    @MainActor func testOffscreenFirstCompletionDoesNotFocusOrScroll() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let items = (1...6).map { LayoutHelperPanel.Item(id: CGWindowID($0), title: "Review window \($0)",
            icon: nil, unavailableReason: nil, sourceSize: CGSize(width: 240, height: 600), isMinimized: true) }
        panel.configure(in: CGRect(x: 0, y: 0, width: 320, height: 480), items: items,
            offerPermission: false, keyboardTriggered: true, waitForPreviews: true, separateBackground: true)
        panel.makeFirstResponder(panel.initialFirstResponder)
        let scroll = try XCTUnwrap(views(try XCTUnwrap(panel.contentView), NSScrollView.self).first)
        let origin = scroll.contentView.bounds.origin
        let focus = panel.firstResponder
        panel.updateImage(NSImage(size: CGSize(width: 240, height: 600)), for: 2)
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        XCTAssertTrue(panel.firstResponder === focus)
        panel.updateImage(NSImage(size: CGSize(width: 240, height: 600)), for: 1)
        XCTAssertEqual((panel.firstResponder as? NSButton)?.title, "Review window 1")
        XCTAssertEqual(scroll.contentView.bounds.origin, origin)
    }

    func testSparseAndEdgeCapturesRemainValidAcrossTileBoundaries() throws {
        for rect in [CGRect(x: 0, y: 0, width: 1, height: 1),
                     CGRect(x: 256, y: 256, width: 1, height: 1),
                     CGRect(x: 839, y: 519, width: 1, height: 1),
                     CGRect(x: 411, y: 0, width: 2, height: 520)] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 840, height: 520, bitsPerComponent: 8,
                bytesPerRow: 840 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(NSColor.white.withAlphaComponent(1.0 / 255).cgColor)
            context.fill(rect)
            XCTAssertTrue(LayoutHelperPreviewValidation.isValid(try XCTUnwrap(context.makeImage())), "Visible source alpha at \(rect)")
        }
        let transparent = try XCTUnwrap(CGContext(data: nil, width: 840, height: 520, bitsPerComponent: 8,
            bytesPerRow: 840 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        XCTAssertFalse(LayoutHelperPreviewValidation.isValid(try XCTUnwrap(transparent.makeImage())))
    }

    func testFailedRestoreRollsBackAndRetryRetainsOriginalGeometry() {
        let original = CGRect(x: 100, y: 100, width: 400, height: 600)
        let target = CGRect(x: 720, y: 29, width: 720, height: 878)
        var actual = original
        var remembered = LayoutHelperRestorationFrames()
        XCTAssertEqual(remembered.original(id: 7, pid: 42, launch: 1, frame: original, remember: true), original)
        XCTAssertTrue(LayoutHelperWindowRestoration.prepare(target: target, isCurrent: { true }, minimized: { true },
            size: { actual.size = $0; return .success }, position: { actual.origin = $0; return .success }, frame: { actual }))
        let outcome = LayoutHelperWindowRestoration.acknowledge(isCurrent: { true }, minimized: { true },
            restore: { .cannotComplete }, frame: { actual })
        guard case .unresponsive = outcome else { return XCTFail("Expected failed restore") }
        XCTAssertEqual(remembered.original(id: 7, pid: 42, launch: 1, frame: actual, remember: true), original)
        XCTAssertTrue(LayoutHelperWindowRestoration.rollback(original: original, isCurrent: { true },
            size: { actual.size = $0; return .success }, position: { actual.origin = $0; return .success }))
        XCTAssertEqual(actual, original)
        remembered.remove(id: 7, pid: 42, launch: 1)
        XCTAssertEqual(remembered.original(id: 7, pid: 42, launch: 1, frame: target, remember: false), target)
    }

    func testCancellationPreventsRollbackWritesAndKeepsOriginalForRetry() {
        let original = CGRect(x: 100, y: 100, width: 400, height: 600)
        let prepared = CGRect(x: 720, y: 29, width: 720, height: 878)
        var remembered = LayoutHelperRestorationFrames()
        _ = remembered.original(id: 7, pid: 42, launch: 1, frame: original, remember: true)
        var writes = 0
        XCTAssertFalse(LayoutHelperWindowRestoration.rollback(original: original, isCurrent: { false },
            size: { _ in writes += 1; return .success }, position: { _ in writes += 1; return .success }))
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(remembered.original(id: 7, pid: 42, launch: 1, frame: prepared, remember: false), original)
        XCTAssertEqual(remembered.original(id: 7, pid: 42, launch: 2, frame: prepared, remember: false), prepared)
        XCTAssertEqual(remembered.original(id: 7, pid: 43, launch: 1, frame: prepared, remember: false), prepared)
        var current = true
        XCTAssertFalse(LayoutHelperWindowRestoration.rollback(original: original, isCurrent: { current },
            size: { _ in writes += 1; current = false; return .success }, position: { _ in writes += 1; return .success }))
        XCTAssertEqual(writes, 1)
    }
}


@MainActor
final class LayoutHelperCatalogScreenTests: XCTestCase {
    private final class Screen: NSScreen {
        private let rectangle: CGRect
        init(_ rectangle: CGRect) { self.rectangle = rectangle; super.init() }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var frame: CGRect { rectangle }
        override func isEqual(_ object: Any?) -> Bool {
            XCTFail("Catalog membership must not invoke AppKit screen equality")
            return false
        }
    }

    func testCalculationScreenMatchesDisplayWithoutAppKitEquality() {
        let bounds = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let display = Screen(bounds)
        let calculation = Screen(bounds)
        let other = Screen(bounds.offsetBy(dx: 1440, dy: 0))
        XCTAssertTrue(LayoutHelperWindowCatalog.matchesScreen(display, requested: calculation))
        XCTAssertTrue(LayoutHelperWindowCatalog.matchesScreen(display, requested: display))
        XCTAssertFalse(LayoutHelperWindowCatalog.matchesScreen(other, requested: calculation))
        XCTAssertFalse(LayoutHelperWindowCatalog.matchesScreen(nil, requested: calculation))
    }
}

@MainActor
final class LayoutHelperCapturePriorityTests: XCTestCase {
    func testScrollingPrioritizesVisibleWindowsAlreadyWaitingForCapture() async {
        let initialStarted = expectation(description: "Both capture slots are occupied")
        initialStarted.expectedFulfillmentCount = 2
        let visibleStarted = expectation(description: "Newly visible window starts next")
        var started: [Int] = []
        var pending: [Int: CheckedContinuation<Int?, Never>] = [:]
        let queue = LayoutHelperCaptureQueue<Int, Int> { key in
            await withCheckedContinuation { continuation in
                pending[key] = continuation
                started.append(key)
                if key == 1 || key == 2 { initialStarted.fulfill() }
                else { visibleStarted.fulfill() }
            }
        }
        queue.replace(with: [1, 2, 3, 4, 5])
        await fulfillment(of: [initialStarted], timeout: 2)

        queue.replace(with: [5, 1, 2, 3, 4, 5])
        pending.removeValue(forKey: 1)?.resume(returning: 1)
        await fulfillment(of: [visibleStarted], timeout: 2)
        XCTAssertEqual(Set(started.prefix(2)), [1, 2])
        XCTAssertEqual(started.dropFirst(2), [5])
        XCTAssertEqual(queue.activeCount, 2)

        queue.stop()
        for continuation in pending.values { continuation.resume(returning: nil) }
    }

    func testReplacementDropsObsoleteWaitingWindows() async {
        let initialStarted = expectation(description: "Both capture slots are occupied")
        initialStarted.expectedFulfillmentCount = 2
        let replacementStarted = expectation(description: "Replacement window starts")
        var started: [Int] = []
        var pending: [Int: CheckedContinuation<Int?, Never>] = [:]
        let queue = LayoutHelperCaptureQueue<Int, Int> { key in
            await withCheckedContinuation { continuation in
                pending[key] = continuation
                started.append(key)
                if key == 1 || key == 2 { initialStarted.fulfill() }
                else { replacementStarted.fulfill() }
            }
        }
        queue.replace(with: [1, 2, 3, 4])
        await fulfillment(of: [initialStarted], timeout: 2)

        queue.replace(with: [4, 4])
        pending.removeValue(forKey: 1)?.resume(returning: 1)
        await fulfillment(of: [replacementStarted], timeout: 2)
        XCTAssertEqual(started.dropFirst(2), [4])

        queue.stop()
        for continuation in pending.values { continuation.resume(returning: nil) }
    }
}

@MainActor
final class WindowPlacementSchedulingTests: XCTestCase {
    func testIdlePlacementCompletionRunsSynchronously() {
        var completed = false
        WindowAnimator.shared.afterPendingWrites { completed = true }
        XCTAssertTrue(completed)
    }

    func testCompletionWaitsForPlacementWorker() {
        let started = expectation(description: "Worker started")
        let completed = expectation(description: "Writes completed")
        let release = DispatchSemaphore(value: 0)
        WindowAnimator.shared.performPlacementWork {
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
        }
        wait(for: [started], timeout: 2)
        var callbackRan = false
        WindowAnimator.shared.afterPendingWrites {
            XCTAssertTrue(Thread.isMainThread)
            callbackRan = true
            completed.fulfill()
        }
        XCTAssertFalse(callbackRan)
        release.signal()
        wait(for: [completed], timeout: 2)
    }
}

@MainActor
final class LayoutHelperContinuityTests: XCTestCase {
    private let region = CGRect(x: 40, y: 40, width: 480, height: 480)
    private func views<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
        root.subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + views($0, type) }
    }
    private func items(_ count: Int) -> [LayoutHelperPanel.Item] {
        (1...count).map { .init(id: CGWindowID($0), title: "Continuity \($0)", icon: nil,
            unavailableReason: nil, sourceSize: CGSize(width: 400, height: 600)) }
    }
    private func card(_ id: Int, _ panel: LayoutHelperPanel) throws -> NSButton {
        try XCTUnwrap(views(try XCTUnwrap(panel.contentView), NSButton.self).first { $0.title == "Continuity \(id)" })
    }
    private func scroll(_ panel: LayoutHelperPanel) throws -> NSScrollView {
        try XCTUnwrap(views(try XCTUnwrap(panel.contentView), NSScrollView.self).first)
    }
    func testCandidateAdditionPreservesCardsFocusAndScrolledViewport() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        panel.show(in: region, items: items(12), offerPermission: false, keyboardTriggered: true)
        let first = try card(1, panel)
        panel.makeFirstResponder(first)
        let originalScroll = try scroll(panel)
        originalScroll.contentView.scroll(to: CGPoint(x: 0, y: 350))
        originalScroll.reflectScrolledClipView(originalScroll.contentView)
        let origin = originalScroll.contentView.bounds.origin
        panel.show(in: region, items: items(13), offerPermission: false, keyboardTriggered: true)
        XCTAssertTrue(try card(1, panel) === first)
        XCTAssertTrue(panel.firstResponder === first)
        XCTAssertEqual(try scroll(panel).contentView.bounds.origin.y, origin.y, accuracy: 1)
    }
    func testNewCandidateWaitsForPreviewWithoutHidingExistingCards() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        let image = NSImage(size: CGSize(width: 400, height: 600))
        panel.show(in: region, items: items(1), offerPermission: false,
                   images: [1: image], waitForPreviews: true)
        let first = try card(1, panel)
        panel.show(in: region, items: items(2), offerPermission: false, waitForPreviews: true)
        XCTAssertTrue(try card(1, panel) === first)
        XCTAssertFalse(first.isHidden)
        XCTAssertTrue(try card(2, panel).isHidden)
        panel.updateImage(image, for: 2)
        XCTAssertFalse(try card(2, panel).isHidden)
    }
    func testConsecutiveCandidateRemovalsKeepDepartingCardsAttached() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { throw XCTSkip("Removal fades respect Reduce Motion") }
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        panel.show(in: region, items: items(3), offerPermission: false)
        let third = try card(3, panel)
        panel.show(in: region, items: items(2), offerPermission: false)
        panel.show(in: region, items: items(1), offerPermission: false)
        XCTAssertTrue(third.isDescendant(of: try XCTUnwrap(panel.contentView)))
        XCTAssertFalse(third.isEnabled)
        XCTAssertTrue(panel.isTransitioning)
    }
    func testDisjointContinuationUsesFadeAndRetainsCardIdentity() async throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        panel.show(in: region, items: items(1), offerPermission: false)
        let first = try card(1, panel)
        let next = region.offsetBy(dx: 600, dy: 0)
        panel.show(in: next, items: items(1), offerPermission: false, continuing: true)
        XCTAssertTrue(try card(1, panel) === first)
        XCTAssertEqual(panel.frame, next)
        try await Task.sleep(nanoseconds: 50_000_000)
        let owned = Set(NSApp.windows.filter { panel.owns($0) }.map { $0.windowNumber })
        let ordered = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]])?
            .compactMap { $0[kCGWindowNumber as String] as? Int }.filter { owned.contains($0) }
        XCTAssertEqual(ordered?.first, panel.windowNumber,
                       "Replacement backgrounds must remain below the retained cards: \(String(describing: ordered))")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = try XCTUnwrap(first.layer?.animation(forKey: "layoutHelperReflow") as? CABasicAnimation)
            XCTAssertEqual(animation.keyPath, "opacity")
        }
        panel.dismiss()
        XCTAssertFalse(panel.hasActiveSession)
        XCTAssertFalse(panel.isTransitioning)
    }
    func testOverlappingShrinkFadesCardsOutsideTheNewViewport() throws {
        let panel = LayoutHelperPanel()
        defer { panel.dismiss() }
        panel.show(in: region, items: items(1), offerPermission: false)
        let first = try card(1, panel)
        let smaller = CGRect(x: region.minX + 160, y: region.minY, width: 320, height: region.height)
        panel.show(in: smaller, items: items(1), offerPermission: false, continuing: true)
        XCTAssertTrue(try card(1, panel) === first)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let animation = try XCTUnwrap(first.layer?.animation(forKey: "layoutHelperReflow") as? CABasicAnimation)
            XCTAssertEqual(animation.keyPath, "opacity")
        }
    }

    func testBackdropRetargetingReachesLatestFrameAndResizesShadow() async throws {
        let surface = LayoutHelperSurface()
        defer { surface.stopFrameTransition(); surface.close() }
        surface.prepare(in: region)
        let target = CGRect(x: 50, y: 50, width: 640, height: 600)
        surface.transitionFrame(to: region.insetBy(dx: 20, dy: 20), duration: 0.18)
        surface.transitionFrame(to: target, duration: 0.05)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(surface.frame, target)
        XCTAssertNil(surface.destinationFrame)
        let root = try XCTUnwrap(surface.contentView)
        root.layoutSubtreeIfNeeded()
        let shadow = try XCTUnwrap(root.subviews.first { $0.layer?.shadowPath != nil })
        XCTAssertEqual(try XCTUnwrap(shadow.layer?.shadowPath).boundingBoxOfPath, shadow.bounds)
    }
}

@MainActor
final class LayoutHelperShortcutEntryTests: XCTestCase {
    private final class Bindings: ShortcutBindingStore {
        func configure() {}
        func registerDefaultShortcuts(_ shortcuts: [String: MASShortcut]) {}
        func bindShortcut(withDefaultsKey defaultsKey: String, toAction action: @escaping () -> Void) {}
        func breakBinding(withDefaultsKey defaultsKey: String) {}
    }
    private final class WindowManagerSpy: WindowManager {
        var received: ExecutionParameters?
        override func execute(_ parameters: ExecutionParameters) { received = parameters }
    }
    private final class MissingStackWindow: AccessibilityElement {
        init() { super.init(AXUIElementCreateApplication(getpid())) }
        override func getWindowId() -> CGWindowID? { nil }
    }
    func testStackCycleCommandsDismissHelperBeforeBypassingWindowManager() {
        let helper = LayoutHelperManager.shared
        defer { helper.cancel() }
        let manager = WindowManagerSpy()
        let router = ShortcutManager(windowManager: manager, bindingStore: Bindings(),
            notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
            shortcutsProvider: { [:] }, activeStateProvider: { false }, todoSessionStateChanged: { _ in })
        for action: WindowAction in [.cycleStackedWindows, .cycleStackedWindowsBackward] {
            let token = helper.cancel()
            let parameters = ExecutionParameters(action, windowElement: MissingStackWindow(), source: .keyboardShortcut)
            router.windowActionTriggered(notification: NSNotification(name: action.notificationName, object: parameters))
            XCTAssertNotEqual(helper.token, token, "Stack cycling must invalidate the previous Helper session")
            XCTAssertNil(manager.received, "Stack cycling is handled by MultiWindowManager")
        }
    }
    func testOrdinaryCommandsReachWindowManagerWithoutDismissingHelper() {
        let previous = Defaults.subsequentExecutionMode.value
        Defaults.subsequentExecutionMode.value = .none
        defer { Defaults.subsequentExecutionMode.value = previous; LayoutHelperManager.shared.cancel() }
        let windowManager = WindowManagerSpy()
        let router = ShortcutManager(windowManager: windowManager, bindingStore: Bindings(),
            notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter(),
            shortcutsProvider: { [:] }, activeStateProvider: { false }, todoSessionStateChanged: { _ in })
        for source: ExecutionSource in [.keyboardShortcut, .menuItem, .dragToSnap] {
            let token = LayoutHelperManager.shared.cancel()
            let parameters = ExecutionParameters(.leftHalf, source: source)
            router.windowActionTriggered(notification: NSNotification(name: WindowAction.leftHalf.notificationName, object: parameters))
            XCTAssertEqual(windowManager.received?.action, .leftHalf)
            XCTAssertEqual(LayoutHelperManager.shared.token, token,
                           "WindowManager must decide continuity after resolving the target window")
        }
    }
}

@MainActor
final class LayoutHelperCatalogSchedulingTests: XCTestCase {
    private final class Calls {
        private let lock = NSLock()
        private var count = 0
        private var active = 0
        private var maximum = 0
        func begin() -> Int {
            lock.lock(); defer { lock.unlock() }
            count += 1; active += 1; maximum = max(maximum, active)
            return count
        }
        func end() { lock.lock(); active -= 1; lock.unlock() }
        var totals: (count: Int, maximum: Int) {
            lock.lock(); defer { lock.unlock() }; return (count, maximum)
        }
    }

    func testRepeatedRefreshAndStopResumeKeepOneWindowServerRequest() async {
        let first = expectation(description: "First inventory is blocked")
        let second = expectation(description: "Newest inventory starts after release")
        let released = expectation(description: "Latest inventory completed")
        let release = DispatchSemaphore(value: 0)
        let calls = Calls()
        let catalog = LayoutHelperWindowCatalog(windowList: {
            XCTAssertFalse(Thread.isMainThread)
            let index = calls.begin()
            defer { calls.end() }
            if index == 1 {
                first.fulfill()
                _ = release.wait(timeout: .now() + 3)
            } else if index == 2 { second.fulfill() }
            return []
        }, desktopWindows: { _, _ in [:] })
        defer { release.signal(); catalog.stop() }
        catalog.refresh()
        await fulfillment(of: [first], timeout: 2)
        for _ in 0..<20 { catalog.refresh() }
        catalog.stop()
        catalog.didUpdate = { released.fulfill() }
        for _ in 0..<20 { catalog.refresh() }
        XCTAssertTrue(catalog.isRefreshing)
        release.signal()
        await fulfillment(of: [second, released], timeout: 3)
        XCTAssertEqual(calls.totals.count, 2)
        XCTAssertEqual(calls.totals.maximum, 1)
    }

    func testStoppingDropsPendingInventoryDemand() async {
        let started = expectation(description: "Inventory started")
        let stale = expectation(description: "Stopped inventory must not deliver")
        stale.isInverted = true
        let release = DispatchSemaphore(value: 0)
        let calls = Calls()
        let catalog = LayoutHelperWindowCatalog(windowList: {
            let index = calls.begin()
            defer { calls.end() }
            if index == 1 { started.fulfill(); _ = release.wait(timeout: .now() + 3) }
            return []
        }, desktopWindows: { _, _ in [:] })
        defer { release.signal(); catalog.stop() }
        catalog.didUpdate = { stale.fulfill() }
        catalog.refresh()
        await fulfillment(of: [started], timeout: 2)
        catalog.refresh()
        catalog.stop()
        XCTAssertFalse(catalog.isRefreshing)
        release.signal()
        await fulfillment(of: [stale], timeout: 0.15)
        XCTAssertEqual(calls.totals.count, 1)
    }
}

@MainActor
final class LayoutHelperCancelledCaptureTests: XCTestCase {
    func testCancelledCapturesKeepSlotsAndDiscardResultsBeforeRestartingSameKey() async {
        let initial = expectation(description: "Both captures started")
        initial.expectedFulfillmentCount = 2
        let restarted = expectation(description: "Latest request starts after old slot returns")
        let delivered = expectation(description: "Only latest capture is delivered")
        var pending: [Int: CheckedContinuation<Int?, Never>] = [:]
        var started: [Int] = []
        var values: [Int] = []
        let queue = LayoutHelperCaptureQueue<Int, Int> { key in
            await withCheckedContinuation { continuation in
                pending[key] = continuation
                started.append(key)
                if started.count <= 2 { initial.fulfill() } else { restarted.fulfill() }
            }
        }
        queue.completed = { _, value in values.append(value); delivered.fulfill() }
        queue.replace(with: [1, 2])
        await fulfillment(of: [initial], timeout: 2)
        queue.stop()
        queue.replace(with: [1])
        XCTAssertEqual(queue.activeCount, 2)
        pending.removeValue(forKey: 1)?.resume(returning: 10)
        await fulfillment(of: [restarted], timeout: 2)
        XCTAssertEqual(Set(started.prefix(2)), [1, 2])
        XCTAssertEqual(Array(started.dropFirst(2)), [1])
        XCTAssertEqual(queue.activeCount, 2)
        pending.removeValue(forKey: 1)?.resume(returning: 11)
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(values, [11])
        queue.stop()
        for continuation in pending.values { continuation.resume(returning: nil) }
    }
}

final class WindowDividerWorkerSettlementTests: XCTestCase {
    func testDelayedAcknowledgementPreservesWriteOrderAndStableReveal() throws {
        var frames = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 510, y: 0, width: 490, height: 800)]
        var time: TimeInterval = 0
        var pending: (Int, CGRect, TimeInterval)?
        var writes: [Int] = []
        let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
            divider: 405, minimumLeft: 100, minimumRight: 100,
            write: { isLeft, target, _ in
                XCTAssertNil(pending, "A second property cannot replace an unacknowledged write")
                let index = isLeft ? 0 : 1
                writes.append(index); pending = (index, target, time + 0.12)
                return true
            }, read: { frames[$0 ? 0 : 1] }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: {
            time += 0.025
            if let update = pending, time >= update.2 { frames[update.0] = update.1; pending = nil }
        }))
        XCTAssertEqual(writes.first, 0, "Shrink the left window before expanding the right")
        XCTAssertEqual(result.left, CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(result.right, CGRect(x: 410, y: 0, width: 590, height: 800))
        XCTAssertFalse(result.minimumSizeReached)
        XCTAssertLessThan(time, 6)
    }

    @MainActor func testCancellationDoesNotWaitForSlowWriteOrSendAnotherProperty() async {
        let started = expectation(description: "Worker is inside a slow AX write")
        let completed = expectation(description: "Cancelled worker releases placement ownership")
        let release = DispatchSemaphore(value: 0)
        let cancellation = WindowPlacementCoordinator.Cancellation()
        WindowAnimator.shared.performPlacementWork {
            var frames = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 510, y: 0, width: 490, height: 800)]
            var writes = 0
            let placement = WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
                divider: 405, minimumLeft: 100, minimumRight: 100,
                write: { isLeft, target, _ in
                    XCTAssertFalse(Thread.isMainThread)
                    writes += 1; started.fulfill()
                    _ = release.wait(timeout: .now() + 3)
                    frames[isLeft ? 0 : 1] = target
                    return true
                }, read: { frames[$0 ? 0 : 1] })!
            XCTAssertNil(placement.settle(isCurrent: { !cancellation.isCancelled }))
            XCTAssertEqual(writes, 1)
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled, "Main-thread cancellation must not wait on the blocked writer")
        release.signal()
        await fulfillment(of: [completed], timeout: 2)
        let drained = expectation(description: "Placement queue is idle before the next test")
        WindowAnimator.shared.afterPendingWrites { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
    }
}


@MainActor
final class LayoutHelperSnapResponsivenessTests: XCTestCase {
    private final class Window: AccessibilityElement {
        private(set) var minimizedReads = 0
        init() { super.init(AXUIElementCreateSystemWide()) }
        override var isMinimized: Bool? { minimizedReads += 1; return true }
    }

    func testDidSnapDefersVisibilityValidationWithoutReadingAXMinimized() throws {
        guard !StageUtil.stageEnabled else { throw XCTSkip("Layout Helper is disabled while Stage Manager is enabled") }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let savedHelper = Defaults.layoutHelper.enabled
        let savedDivider = Defaults.windowDivider.enabled
        let savedGap = Defaults.gapSize.value
        Defaults.layoutHelper.enabled = true
        Defaults.windowDivider.enabled = false
        Defaults.gapSize.value = 0
        let manager = LayoutHelperManager.shared
        defer {
            manager.cancel()
            Defaults.layoutHelper.enabled = savedHelper
            Defaults.windowDivider.enabled = savedDivider
            Defaults.gapSize.value = savedGap
        }
        let bounds = screen.adjustedVisibleFrame().screenFlipped
        let frame = CGRect(x: bounds.minX, y: bounds.minY, width: floor(bounds.width / 2), height: bounds.height)
        let window = Window()
        let token = manager.cancel()
        let calculation = WindowCalculationResult(rect: frame.screenFlipped, screen: screen, resultingAction: .leftHalf)
        let result = ResultParameters(windowId: nil, action: .leftHalf, windowElement: window,
            calcResult: calculation, usableScreens: UsableScreens(currentScreen: screen, numScreens: 1),
            visibleFrameOfScreen: bounds.screenFlipped, source: .dragToSnap, isFixedSize: false,
            layoutHelperToken: token)
        manager.didSnap(result: result, frame: frame)
        XCTAssertEqual(window.minimizedReads, 0, "The snap callback must not wait on the target application's AX reply")
        XCTAssertEqual(manager.token, token, "Visibility must be checked by the deferred WindowServer observation")
    }
}


class VerticalEighthActionTests: XCTestCase {

    private let actions: [WindowAction] = [
        .firstVerticalEighth, .secondVerticalEighth, .thirdVerticalEighth, .fourthVerticalEighth,
        .fifthVerticalEighth, .sixthVerticalEighth, .seventhVerticalEighth, .lastVerticalEighth
    ]

    func testVerticalEighthActionsUseAvailableStableIdentifiers() {
        XCTAssertEqual([
            WindowAction.tileRows.rawValue,
            WindowAction.tileColumns.rawValue,
            WindowAction.cycleStackedWindows.rawValue,
            WindowAction.cycleStackedWindowsBackward.rawValue
        ], [129, 130, 131, 132])
        XCTAssertEqual(actions.map(\.rawValue), [133, 134, 135, 136, 137, 138, 139, 140])
        XCTAssertEqual(actions.map(\.name), [
            "firstVerticalEighth", "secondVerticalEighth", "thirdVerticalEighth", "fourthVerticalEighth",
            "fifthVerticalEighth", "sixthVerticalEighth", "seventhVerticalEighth", "lastVerticalEighth"
        ])
    }

    func testVerticalEighthActionsTileVisibleFrameIntoEightFullHeightColumns() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 3840, height: 1000)
        let expected = (0..<8).map { CGRect(x: CGFloat($0 * 480), y: 40, width: 480, height: 1000) }
        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalEighthActionsUseBoundaryRoundingAcrossNonDivisibleLandscapeWidth() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1003, height: 800)
        let expected = [
            CGRect(x: 20, y: 40, width: 125, height: 800),
            CGRect(x: 145, y: 40, width: 125, height: 800),
            CGRect(x: 270, y: 40, width: 126, height: 800),
            CGRect(x: 396, y: 40, width: 125, height: 800),
            CGRect(x: 521, y: 40, width: 125, height: 800),
            CGRect(x: 646, y: 40, width: 126, height: 800),
            CGRect(x: 772, y: 40, width: 125, height: 800),
            CGRect(x: 897, y: 40, width: 126, height: 800)
        ]

        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalEighthActionsRotateIntoTopToBottomRowsOnPortraitDisplays() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 1003)
        let expected = [
            CGRect(x: 20, y: 918, width: 800, height: 125),
            CGRect(x: 20, y: 793, width: 800, height: 125),
            CGRect(x: 20, y: 667, width: 800, height: 126),
            CGRect(x: 20, y: 542, width: 800, height: 125),
            CGRect(x: 20, y: 417, width: 800, height: 125),
            CGRect(x: 20, y: 291, width: 800, height: 126),
            CGRect(x: 20, y: 166, width: 800, height: 125),
            CGRect(x: 20, y: 40, width: 800, height: 126)
        ]

        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testFirstVerticalEighthCyclesForwardAndWraps() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            let results = repeatedResults(for: .firstVerticalEighth, count: 9, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map { $0.rect.minX }, [20, 120, 220, 320, 420, 520, 620, 720, 20])
        }
    }

    func testLastVerticalEighthCyclesBackwardAndWraps() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            let results = repeatedResults(for: .lastVerticalEighth, count: 9, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map { $0.rect.minX }, [720, 620, 520, 420, 320, 220, 120, 20, 720])
        }
    }

    func testEndpointCyclingResetsForUnrelatedOrOppositeLastAction() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            let unrelated = RectangleAction(action: .leftHalf, subAction: .leftThird, rect: .zero)
            XCTAssertEqual(calculate(.firstVerticalEighth, visibleFrame: visibleFrame, lastAction: unrelated).rect.minX, 20)
            XCTAssertEqual(calculate(.lastVerticalEighth, visibleFrame: visibleFrame, lastAction: unrelated).rect.minX, 720)

            let lastResult = calculate(.lastVerticalEighth, visibleFrame: visibleFrame)
            let lastEndpoint = RectangleAction(action: .lastVerticalEighth, subAction: lastResult.subAction, rect: lastResult.rect)
            XCTAssertEqual(calculate(.firstVerticalEighth, visibleFrame: visibleFrame, lastAction: lastEndpoint).rect.minX, 20)

            let firstResult = calculate(.firstVerticalEighth, visibleFrame: visibleFrame)
            let firstEndpoint = RectangleAction(action: .firstVerticalEighth, subAction: firstResult.subAction, rect: firstResult.rect)
            XCTAssertEqual(calculate(.lastVerticalEighth, visibleFrame: visibleFrame, lastAction: firstEndpoint).rect.minX, 720)
        }
    }

    func testEndpointCyclingIsDisabledWhenSubsequentExecutionModeIsNone() {
        withSubsequentExecutionMode(.none) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            XCTAssertEqual(repeatedResults(for: .firstVerticalEighth, count: 3, visibleFrame: visibleFrame).map { $0.rect.minX },
                           [20, 20, 20])
            XCTAssertEqual(repeatedResults(for: .lastVerticalEighth, count: 3, visibleFrame: visibleFrame).map { $0.rect.minX },
                           [720, 720, 720])
        }
    }

    func testMiddleVerticalEighthActionsStayAtTheirOwnOrdinalWhenRepeated() {
        withSubsequentExecutionMode(.resize) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 400)
            for (index, action) in actions.dropFirst().dropLast().enumerated() {
                let expectedX = CGFloat(120 + index * 100)
                let results = repeatedResults(for: action, count: 3, visibleFrame: visibleFrame)
                XCTAssertEqual(results.map { $0.rect.minX }, [expectedX, expectedX, expectedX])
            }
        }
    }

    func testVerticalEighthResultingSubActionsProvideLandscapeGapEdges() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1003, height: 800)
        let expected: [Edge] = [
            .right,
            [.left, .right], [.left, .right], [.left, .right],
            [.left, .right], [.left, .right], [.left, .right],
            .left
        ]

        for (index, action) in actions.enumerated() {
            XCTAssertEqual(calculate(action, visibleFrame: visibleFrame).subAction?.gapSharedEdge, expected[index])
        }
    }

    func testVerticalEighthResultingSubActionsProvidePortraitGapEdges() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 1003)
        let expected: [Edge] = [
            .bottom,
            [.top, .bottom], [.top, .bottom], [.top, .bottom],
            [.top, .bottom], [.top, .bottom], [.top, .bottom],
            .top
        ]

        for (index, action) in actions.enumerated() {
            XCTAssertEqual(calculate(action, visibleFrame: visibleFrame).subAction?.gapSharedEdge, expected[index])
        }
    }

    func testVerticalEighthActionsRemainTerminalConfigurableThroughActiveActionNames() {
        let suiteName = "VerticalEighthActionTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let shortcut = MASShortcut(keyCode: 18, modifierFlags: [.control, .option, .shift])
        let transformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        userDefaults.set(transformer.reverseTransformedValue(shortcut), forKey: WindowAction.firstVerticalEighth.name)

        XCTAssertTrue(WindowAction.active.contains(.firstVerticalEighth))
        let loaded = ShortcutCycle.shortcutsByAction(userDefaults: userDefaults)[.firstVerticalEighth]
        XCTAssertEqual(loaded?.keyCode, shortcut.keyCode)
        XCTAssertEqual(loaded?.modifierFlags, shortcut.modifierFlags)
    }

    func testVerticalEighthActionsAreHiddenFromNormalUI() throws {
        XCTAssertTrue(actions.allSatisfy(\.excludedFromMenu))
        XCTAssertTrue(actions.allSatisfy { !$0.isDragSnappable })

        let controller = ShortcutsViewController()
        _ = controller.view
        let outlineView = try XCTUnwrap(findOutlineView(in: controller.view))
        let rootCount = controller.outlineView(outlineView, numberOfChildrenOfItem: nil)

        var found: [WindowAction] = []
        func collect(from item: Any?) {
            let count = controller.outlineView(outlineView, numberOfChildrenOfItem: item)
            for index in 0..<count {
                let child = controller.outlineView(outlineView, child: index, ofItem: item)
                if let shortcut = child as? ShortcutItem, actions.contains(shortcut.action) {
                    found.append(shortcut.action)
                }
                collect(from: child)
            }
        }

        for index in 0..<rootCount {
            collect(from: controller.outlineView(outlineView, child: index, ofItem: nil))
        }

        XCTAssertTrue(found.isEmpty)
    }

    private func calculate(_ action: WindowAction,
                           visibleFrame: CGRect,
                           lastAction: RectangleAction? = nil) -> RectResult {
        WindowCalculationFactory.calculationsByAction[action]!.calculateRect(
            RectCalculationParameters(window: Window(id: 1, rect: visibleFrame),
                                      visibleFrameOfScreen: visibleFrame,
                                      action: action,
                                      lastAction: lastAction)
        )
    }

    private func repeatedResults(for action: WindowAction,
                                 count: Int,
                                 visibleFrame: CGRect) -> [RectResult] {
        var lastAction: RectangleAction?
        return (0..<count).map { _ in
            let result = calculate(action, visibleFrame: visibleFrame, lastAction: lastAction)
            lastAction = RectangleAction(action: action, subAction: result.subAction, rect: result.rect)
            return result
        }
    }

    private func withSubsequentExecutionMode(_ mode: SubsequentExecutionMode, _ body: () -> Void) {
        let saved = Defaults.subsequentExecutionMode.value
        defer { Defaults.subsequentExecutionMode.value = saved }
        Defaults.subsequentExecutionMode.value = mode
        body()
    }

    private func findOutlineView(in view: NSView) -> NSOutlineView? {
        if let outlineView = view as? NSOutlineView { return outlineView }
        for subview in view.subviews {
            if let outlineView = findOutlineView(in: subview) { return outlineView }
        }
        return nil
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
}


final class TrackpadGestureRegressionTests: XCTestCase {
    private func frame(_ count: Int, x: Double, y: Double = 0.5, time: Double) -> TrackpadTouchFrame {
        .init(timestamp: time, touches: (0..<count).map {
            .init(identifier: $0, position: .init(x: x, y: y), velocity: .init(x: 2, y: 0))
        })
    }

    func testOnlyOneActionPerPhysicalContactSession() {
        var recognizer = TrackpadGestureRecognizer(config: .default)
        XCTAssertNil(recognizer.process(frame(3, x: 0.2, time: 1)))
        XCTAssertEqual(recognizer.process(frame(3, x: 0.5, time: 1.1))?.direction, .right)
        XCTAssertNil(recognizer.process(frame(4, x: 0.5, time: 1.2)))
        XCTAssertNil(recognizer.process(frame(4, x: 0.9, time: 1.3)))
        XCTAssertNil(recognizer.process(frame(0, x: 0, time: 2)))
        XCTAssertNil(recognizer.process(frame(4, x: 0.2, time: 2.1)))
        XCTAssertEqual(recognizer.process(frame(4, x: 0.6, time: 2.2))?.fingers, 4)
    }

    func testDroppingFourthFingerCannotBecomeThreeFingerGesture() {
        var recognizer = TrackpadGestureRecognizer(config: .default)
        XCTAssertNil(recognizer.process(frame(4, x: 0.2, time: 1)))
        XCTAssertNil(recognizer.process(frame(3, x: 0.3, time: 1.1)))
        XCTAssertNil(recognizer.process(frame(3, x: 0.8, time: 1.2)))
    }

    func testTwoFingerScrollingAndConflictingFingerCountPassThrough() {
        let gate = TrackpadExclusiveGestureGate()
        gate.setAllowedFingerCounts([4])
        gate.setEnabled(true)
        gate.observeContactCount(2)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
        gate.observeContactCount(3)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
        gate.observeContactCount(0)
        gate.observeContactCount(4)
        XCTAssertTrue(gate.shouldSuppressScroll(phase: .active))
        gate.setEnabled(false)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
    }

    func testAlreadyLeakedScrollCannotBeTakenOverMidGesture() {
        let gate = TrackpadExclusiveGestureGate()
        gate.setAllowedFingerCounts([4])
        gate.setEnabled(true)
        gate.observeContactCount(3)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
        gate.observeContactCount(4)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
        gate.observeContactCount(0)
        gate.observeContactCount(4)
        XCTAssertTrue(gate.shouldSuppressScroll(phase: .active))
    }

    func testAlreadyLeakedTwoFingerScrollCannotBeTakenOverMidGesture() {
        let gate = TrackpadExclusiveGestureGate()
        gate.setAllowedFingerCounts([4])
        gate.setEnabled(true)
        gate.observeContactCount(2)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
        XCTAssertTrue(gate.hasLeakedScrollInSession)
        gate.observeContactCount(4)
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .active))
        XCTAssertTrue(gate.hasLeakedScrollInSession,
                      "Capture must reject window actions after scrolling has already reached the app")
        gate.observeContactCount(0)
        gate.observeContactCount(4)
        XCTAssertTrue(gate.shouldSuppressScroll(phase: .active))
        XCTAssertFalse(gate.hasLeakedScrollInSession)
    }

    func testFreshTwoFingerScrollEndsPreviousExclusiveDrain() {
        let clock = TrackpadGestureTestClock()
        let gate = TrackpadExclusiveGestureGate(now: { clock.time })
        gate.setAllowedFingerCounts([4])
        gate.setEnabled(true)
        gate.observeContactCount(4)
        XCTAssertTrue(gate.shouldSuppressScroll(phase: .active))
        gate.observeContactCount(0)

        clock.time = 0.02
        gate.observeContactCount(2)
        for time in [0.02, 0.10, 0.20, 0.30, 0.40, 0.50] {
            clock.time = time
            XCTAssertFalse(gate.shouldSuppressScroll(phase: .active),
                           "A new two-finger scroll must pass through even during the old drain interval")
        }
    }

    func testContactFreeMomentumTailStaysSuppressedUntilItEnds() {
        let clock = TrackpadGestureTestClock()
        let gate = TrackpadExclusiveGestureGate(now: { clock.time })
        gate.setAllowedFingerCounts([4])
        gate.setEnabled(true)
        gate.observeContactCount(4)
        gate.observeContactCount(0)

        for time in [0.10, 0.20, 0.30] {
            clock.time = time
            XCTAssertTrue(gate.shouldSuppressScroll(phase: .active),
                          "Contact-free momentum must extend the existing drain")
        }
        clock.time = 0.40
        XCTAssertTrue(gate.shouldSuppressScroll(phase: .momentumEnded))
        XCTAssertFalse(gate.shouldSuppressScroll(phase: .none))
    }

    func testInvalidConfigCannotAssignBatchActionsToCursorWindow() {
        var settings = TrackpadGestureSettings()
        settings.fingers = 5
        settings.left = WindowAction.tileAll.rawValue
        settings.up = Int.max
        settings.right = WindowAction.rightHalf.rawValue
        let result = settings.validated
        XCTAssertEqual(result.fingers, 4)
        XCTAssertEqual(result.left, TrackpadGestureAction.none)
        XCTAssertEqual(result.up, TrackpadGestureAction.none)
        XCTAssertEqual(result.right, WindowAction.rightHalf.rawValue)
    }
}

private final class TrackpadGestureTestClock: @unchecked Sendable {
    var time: TimeInterval = 0
}

@MainActor
final class TrackpadMinimizeExecutionTests: XCTestCase {
    func testMinimizeRemainsCurrentAfterItsOwnActionNotification() {
        let manager = TrackpadGestureManager.shared
        manager.start()
        let isCurrent = manager.beginAction(TrackpadGestureAction.minimize, runtimeIsCurrent: { true })
        XCTAssertTrue(isCurrent(), "Minimize must not cancel itself before its pending AX write")
        Notification.Name.windowActionWillExecute.post()
        XCTAssertFalse(isCurrent(), "A later shortcut must cancel the pending minimize")
    }

    func testNewGestureCancelsThePreviousPendingAction() {
        let manager = TrackpadGestureManager.shared
        manager.start()
        let previous = manager.beginAction(WindowAction.leftHalf.rawValue, runtimeIsCurrent: { true })
        XCTAssertTrue(previous())
        let current = manager.beginAction(WindowAction.rightHalf.rawValue, runtimeIsCurrent: { true })
        XCTAssertFalse(previous())
        XCTAssertTrue(current())
    }

    func testRuntimeInvalidationCancelsPendingMinimize() {
        let manager = TrackpadGestureManager.shared
        manager.start()
        var healthy = true
        let isCurrent = manager.beginAction(TrackpadGestureAction.minimize, runtimeIsCurrent: { healthy })
        XCTAssertTrue(isCurrent())
        healthy = false
        XCTAssertFalse(isCurrent())
    }

    func testDownSwipeSelectsMinimizeForBothFingerCounts() {
        let settings = TrackpadGestureSettings()
        for fingers in [3, 4] {
            var recognizer = TrackpadGestureRecognizer(config: .default)
            func frame(_ y: Double, time: Double) -> TrackpadTouchFrame {
                .init(timestamp: time, touches: (0..<fingers).map {
                    .init(identifier: $0, position: .init(x: 0.5, y: y), velocity: .init(x: 0, y: -2))
                })
            }
            XCTAssertNil(recognizer.process(frame(0.8, time: 1)))
            let event = recognizer.process(frame(0.5, time: 1.1))
            XCTAssertEqual(event?.direction, .down)
            XCTAssertEqual(event?.fingers, fingers)
            XCTAssertEqual(event.map { settings[$0.direction] }, TrackpadGestureAction.minimize)
        }
    }
}

final class TrackpadTargetLookupConcurrencyTests: XCTestCase {
    func testBlockedLookupDoesNotBlockRecognitionAndDeliversWhenReady() {
        let lookupStarted = DispatchSemaphore(value: 0)
        let releaseLookup = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "trackpad-test.lookup")
        let target = TrackpadCursorWindowShortcutTargeter.Target(
            window: AXUIElementCreateApplication(getpid()), pid: getpid())
        let targeter = TrackpadCursorWindowShortcutTargeter(cursorLocation: { .zero }, findWindow: { _ in
            lookupStarted.signal()
            releaseLookup.wait()
            return target
        }, lookupQueue: queue, now: { 0 })
        targeter.observeFrame(contactCount: 4)
        XCTAssertEqual(lookupStarted.wait(timeout: .now() + 1), .success)
        defer { releaseLookup.signal(); queue.sync {} }

        let registrationReturned = DispatchSemaphore(value: 0)
        let delivered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            targeter.withPreparedWindow { selected in
                XCTAssertTrue(selected === target)
                delivered.signal()
            }
            registrationReturned.signal()
        }
        XCTAssertEqual(registrationReturned.wait(timeout: .now() + 1), .success,
                       "Recognition must return while AX lookup is still blocked")
        XCTAssertEqual(delivered.wait(timeout: .now()), .timedOut)
        targeter.observeFrame(contactCount: 0)
        releaseLookup.signal()
        XCTAssertEqual(delivered.wait(timeout: .now() + 1), .success)
    }

    func testEndedSessionsAreSkippedBeforeStartingTheirQueuedAXLookup() {
        let firstStarted = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "trackpad-test.lookup")
        let state = TrackpadLookupTestState()
        let target = TrackpadCursorWindowShortcutTargeter.Target(
            window: AXUIElementCreateApplication(getpid()), pid: getpid())
        let targeter = TrackpadCursorWindowShortcutTargeter(cursorLocation: { state.nextCursor() }, findWindow: { point in
            state.recordLookup(Int(point.x))
            if point.x == 0 { firstStarted.signal(); releaseFirst.wait() }
            return target
        }, lookupQueue: queue)
        targeter.observeFrame(contactCount: 4)
        XCTAssertEqual(firstStarted.wait(timeout: .now() + 1), .success)
        for _ in 0..<20 {
            targeter.observeFrame(contactCount: 0)
            targeter.observeFrame(contactCount: 4)
        }
        releaseFirst.signal()
        queue.sync {}
        XCTAssertEqual(state.lookups, [0, 20], "Only the newest waiting session may query the app")
    }

    func testResetAndExpiredGraceDiscardCallbacksFromAnUnfinishedLookup() {
        for reset in [false, true] {
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            let queue = DispatchQueue(label: "trackpad-test.lookup")
            let state = TrackpadLookupTestState()
            let target = TrackpadCursorWindowShortcutTargeter.Target(
                window: AXUIElementCreateApplication(getpid()), pid: getpid())
            let targeter = TrackpadCursorWindowShortcutTargeter(cursorLocation: { .zero }, findWindow: { _ in
                started.signal()
                release.wait()
                return target
            }, lookupQueue: queue, now: { state.time })
            targeter.observeFrame(contactCount: 4)
            XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
            targeter.withPreparedWindow { _ in XCTFail("Reset or an expired grace period must discard the target") }
            state.time = 1
            if reset { targeter.reset() } else { targeter.observeFrame(contactCount: 0) }
            release.signal()
            queue.sync {}
        }
    }
}

private final class TrackpadLookupTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var cursor = 0
    private var recorded: [Int] = []
    private var currentTime: TimeInterval = 0
    var time: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return currentTime }
        set { lock.lock(); currentTime = newValue; lock.unlock() }
    }
    func nextCursor() -> CGPoint {
        lock.lock()
        defer { lock.unlock() }
        defer { cursor += 1 }
        return CGPoint(x: cursor, y: 0)
    }
    func recordLookup(_ value: Int) {
        lock.lock()
        recorded.append(value)
        lock.unlock()
    }
    var lookups: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

@MainActor
final class TrackpadRuntimeQueueTests: XCTestCase {
    func testNewestRecognizedGestureReplacesActionsWaitingOnMain() {
        let source = TrackpadRuntimeTestSource()
        let capture = TrackpadRuntimeTestCapture()
        let queue = DispatchQueue(label: "trackpad-test.lookup")
        let target = TrackpadCursorWindowShortcutTargeter.Target(
            window: AXUIElementCreateApplication(getpid()), pid: getpid())
        let targeter = TrackpadCursorWindowShortcutTargeter(cursorLocation: { .zero }, findWindow: { _ in target }, lookupQueue: queue)
        let runtime = TrackpadGestureRuntime(source: source, capture: capture, targeter: targeter)
        var settings = TrackpadGestureSettings()
        settings.enabled = true
        settings.fingers = 4
        var actions: [Int] = []
        let delivered = expectation(description: "newest gesture delivered")
        runtime.onAction = { action, _, _, _ in actions.append(action); delivered.fulfill() }
        runtime.start(settings: settings, systemFingers: [])
        defer { runtime.stop() }

        source.send(x: 0.2, time: 1)
        queue.sync {}
        source.send(x: 0.7, time: 1.1)
        source.lift(time: 1.2)
        source.send(x: 0.7, time: 2)
        queue.sync {}
        source.send(x: 0.2, time: 2.1)
        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(actions, [settings.left], "The old main-queued gesture must not activate or move its target")
    }

    func testStopInvalidatesActionAlreadyQueuedOnMain() {
        let source = TrackpadRuntimeTestSource()
        let queue = DispatchQueue(label: "trackpad-test.lookup")
        let target = TrackpadCursorWindowShortcutTargeter.Target(
            window: AXUIElementCreateApplication(getpid()), pid: getpid())
        let targeter = TrackpadCursorWindowShortcutTargeter(cursorLocation: { .zero }, findWindow: { _ in target }, lookupQueue: queue)
        let runtime = TrackpadGestureRuntime(source: source, capture: TrackpadRuntimeTestCapture(), targeter: targeter)
        var settings = TrackpadGestureSettings()
        settings.enabled = true
        settings.fingers = 4
        runtime.onAction = { _, _, _, _ in XCTFail("Stopped runtimes must not execute queued actions") }
        runtime.start(settings: settings, systemFingers: [])
        source.send(x: 0.2, time: 1)
        queue.sync {}
        source.send(x: 0.7, time: 1.1)
        runtime.stop()
        let drained = expectation(description: "main action queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

private final class TrackpadRuntimeTestSource: TrackpadTouchSource {
    var onDeviceOverlap: (() -> Void)?
    var onContactCount: ((Int) -> Void)?
    var onFrame: ((TrackpadTouchFrame) -> Void)?
    var deviceCount: Int { 1 }
    func start() {}
    func stop() {}
    func send(x: Double, time: Double) {
        onContactCount?(4)
        onFrame?(.init(timestamp: time, touches: (0..<4).map {
            .init(identifier: $0, position: .init(x: x, y: 0.5), velocity: .init(x: x < 0.5 ? -2 : 2, y: 0))
        }))
    }
    func lift(time: Double) {
        onContactCount?(0)
        onFrame?(.init(timestamp: time, touches: []))
    }
}

private final class TrackpadRuntimeTestCapture: TrackpadExclusiveGestureCapturing, @unchecked Sendable {
    var isHealthy = true
    var onHealthChange: (@Sendable (Bool) -> Void)?
    func start() { isHealthy = true }
    func stop() { isHealthy = false }
    func recheck(accessibilityTrusted: Bool) {}
    func setAccessibilityTrusted(_ trusted: Bool) {}
    func setEnabled(_ enabled: Bool) {}
    func setAllowedFingerCounts(_ counts: Set<Int>) {}
    func observeContactCount(_ count: Int) {}
    func contaminateSession() {}
    func performIfHealthy(_ action: () -> Void) -> Bool {
        guard isHealthy else { return false }
        action()
        return true
    }
    func reset() {}
}


@MainActor
final class LiquidGlassBlurTests: XCTestCase {
    private var previousGlass = false
    private var previousBlur = false

    override func setUp() {
        previousGlass = Defaults.liquidGlassForBlur.enabled
        previousBlur = Defaults.footprintBlur.enabled
    }
    override func tearDown() {
        Defaults.liquidGlassForBlur.enabled = previousGlass
        Defaults.footprintBlur.enabled = previousBlur
        Notification.Name.blurStyleChanged.post()
    }

    @MainActor
    func testGlassMaterialTracksColdAndRepeatedAnimatedPreview() async throws {
        guard #available(macOS 26, *), let screen = NSScreen.main else { throw XCTSkip("Requires native glass and a screen") }
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.liquidGlassForBlur.enabled = true
        Defaults.footprintBlur.enabled = true
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        for _ in 0..<2 {
            window.showPreview(in: target, from: CGPoint(x: target.minX + 4, y: target.midY), duration: 0.24)
            try await assertGlassTracksSurface(window, for: 0.32)
            window.orderOut(nil)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    @MainActor
    func testGlassRetargetingStyleSwitchAndCloseRetireAnimation() async throws {
        guard #available(macOS 26, *), let screen = NSScreen.main else { throw XCTSkip("Requires native glass and a screen") }
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.liquidGlassForBlur.enabled = true
        Defaults.footprintBlur.enabled = true
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let left = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        let right = left.offsetBy(dx: left.width, dy: 0)
        window.showPreview(in: left, from: CGPoint(x: left.minX + 4, y: left.midY), duration: 0.24)
        try await assertGlassTracksSurface(window, for: 0.05)
        window.movePreview(to: right, duration: 0.24)
        try await assertGlassTracksSurface(window, for: 0.05)
        window.orderOut(nil)
        window.showPreview(in: left, from: CGPoint(x: left.minX + 4, y: left.midY), duration: 0.24)
        try await assertGlassTracksSurface(window, for: 0.05)
        Defaults.liquidGlassForBlur.enabled = false
        Notification.Name.blurStyleChanged.post()
        window.movePreview(to: right, duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        Defaults.liquidGlassForBlur.enabled = true
        Notification.Name.blurStyleChanged.post()
        try await assertGlassTracksSurface(window, for: 0.05)
        window.movePreview(to: left, duration: 0.24)
        window.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(window.realIsVisible)
    }

    @MainActor
    @available(macOS 26, *)
    private func assertGlassTracksSurface(_ window: FootprintWindow, for duration: TimeInterval,
                                         file: StaticString = #filePath, line: UInt = #line) async throws {
        func material(in view: NSView) -> BlurSurfaceView? {
            if let surface = view as? BlurSurfaceView { return surface }
            return view.subviews.lazy.compactMap { material(in: $0) }.first
        }
        let surface = try XCTUnwrap(window.contentView.flatMap { material(in: $0) }, file: file, line: line)
        let until = CACurrentMediaTime() + duration
        var samples = 0
        while CACurrentMediaTime() < until {
            try await Task.sleep(nanoseconds: 8_000_000)
            let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView, file: file, line: line)
            let outer = surface.layer?.presentation()?.bounds ?? surface.bounds
            let inner = glass.layer?.presentation()?.frame ?? glass.frame
            XCTAssertEqual(inner.width, outer.width, accuracy: 1, file: file, line: line)
            XCTAssertEqual(inner.height, outer.height, accuracy: 1, file: file, line: line)
            samples += 1
        }
        XCTAssertGreaterThan(samples, 0, file: file, line: line)
    }

    func testSwitchingMaterialRetainsContentAndResizesWithoutLegacyBlur() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Native glass requires macOS 26") }
        Defaults.liquidGlassForBlur.enabled = false
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), flipped: true)
        let button = NSButton(title: "Choose", target: nil, action: nil)
        surface.content.addSubview(button)
        XCTAssertEqual(surface.subviews.filter { $0 is NSVisualEffectView }.count, 1)
        for enabled in [true, false, true] {
            Defaults.liquidGlassForBlur.enabled = enabled
            Notification.Name.blurStyleChanged.post()
            XCTAssertEqual(surface.usesLiquidGlass, enabled)
            XCTAssertTrue(button.superview === surface.content)
            XCTAssertTrue(surface.content.isFlipped)
            if enabled {
                let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView)
                XCTAssertTrue(glass.contentView === surface.content)
                XCTAssertNil(glass.tintColor)
                XCTAssertEqual(glass.style, .regular)
                XCTAssertFalse(surface.subviews.contains { $0 is NSVisualEffectView })
                XCTAssertFalse(surface.layer?.masksToBounds ?? false)
            } else {
                XCTAssertTrue(surface.content.superview === surface)
            }
            surface.setFrameSize(CGSize(width: 360, height: 210))
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(surface.content.frame, surface.bounds)
            if enabled {
                surface.setFrameSize(CGSize(width: 1, height: 1))
                surface.layoutSubtreeIfNeeded()
                let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView)
                XCTAssertTrue(glass.isHidden, "Do not render native glass with degenerate animation geometry")
                surface.setFrameSize(CGSize(width: 360, height: 210))
            }
        }
    }

    func testFootprintGlassIgnoresLegacyTintAndLetsSystemHandleTransparency() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Native glass requires macOS 26") }
        Defaults.liquidGlassForBlur.enabled = true
        Defaults.footprintBlur.enabled = true
        let window = FootprintWindow(accessibility: { .init(reduceMotion: true, reduceTransparency: true) })
        defer { window.close() }
        XCTAssertTrue(window.usesLiquidGlass)
        XCTAssertTrue(window.presentation.usesBlur)
        XCTAssertEqual(window.presentation.alpha, 1)
        XCTAssertFalse(window.presentation.fades)
        XCTAssertFalse(window.presentation.animates)
        window.showPreview(in: CGRect(x: 60, y: 60, width: 320, height: 260), from: nil, duration: 0)
        window.contentView?.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.childWindows?.allSatisfy { !$0.isVisible } ?? true, "Custom shadow must be hidden")
        XCTAssertFalse(root.layer?.masksToBounds ?? true)
        XCTAssertTrue(root.subviews.compactMap { $0 as? NSBox }.allSatisfy(\.isHidden))
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let material = try XCTUnwrap(descendants(root).compactMap { $0 as? BlurSurfaceView }.first)
        let preview = try XCTUnwrap(material.superview)
        XCTAssertFalse(preview.layer?.masksToBounds ?? true)
        XCTAssertTrue(preview.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.allSatisfy(\.isHidden) ?? true)
        if preview !== root {
            XCTAssertTrue(root.subviews.filter { $0 !== preview }.allSatisfy(\.isHidden), "Custom shadow must be hidden")
        }
        XCTAssertTrue(material.subviews.first is NSGlassEffectView)
        XCTAssertFalse(material.subviews.contains { $0 is NSVisualEffectView })
        Defaults.footprintBlur.enabled = false
        XCTAssertFalse(window.usesLiquidGlass)
        XCTAssertFalse(window.presentation.usesBlur)
    }



    func testWarningContentSurvivesMaterialSwitch() throws {
        guard #available(macOS 26, *), let screen = NSScreen.main else { throw XCTSkip("Requires macOS 26 and a screen") }
        let warningPreference = Defaults.showMinimumWindowSizeWarning.toCodable()
        Defaults.showMinimumWindowSizeWarning.enabled = true
        defer { Defaults.showMinimumWindowSizeWarning.load(from: warningPreference) }
        Defaults.liquidGlassForBlur.enabled = true
        let warning = WindowSizeWarning()
        defer { warning.close() }
        warning.show(on: screen)
        let surface = try XCTUnwrap(warning.contentView as? BlurSurfaceView)
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.usesLiquidGlass)
        XCTAssertTrue(surface.subviews.first is NSGlassEffectView)
        XCTAssertGreaterThan(warning.frame.width, 100)
        XCTAssertGreaterThan(warning.frame.height, 30)
        func labels(in view: NSView) -> [NSTextField] {
            view.subviews.flatMap { child in
                (child as? NSTextField).map { [$0] } ?? labels(in: child)
            }
        }
        let labels = labels(in: surface.content)
        XCTAssertEqual(labels.count, 1)
        Defaults.liquidGlassForBlur.enabled = false
        Notification.Name.blurStyleChanged.post()
        warning.show(on: screen)
        XCTAssertFalse(surface.usesLiquidGlass)
        XCTAssertTrue(labels.first?.isDescendant(of: surface.content) == true)
        XCTAssertGreaterThan(warning.frame.height, 30)
    }

    func testPreferenceParticipatesInConfigAndViewModel() {
        Defaults.liquidGlassForBlur.enabled = true
        let preference = Defaults.array.first { $0.key == "liquidGlassForBlur" }
        XCTAssertNotNil(preference)
        XCTAssertEqual(preference?.toCodable().bool, true)
        let model = SnapAreaViewModel()
        XCTAssertTrue(model.liquidGlassForBlur)
        model.liquidGlassForBlur = false
        XCTAssertFalse(Defaults.liquidGlassForBlur.enabled)
    }
}

@MainActor
final class BlurDefaultSelectionTests: XCTestCase {
    private var savedBlur = false
    private var savedGlass = false
    private var storedBlur: Any?
    private var storedGlass: Any?
    override func setUp() {
        savedBlur = Defaults.footprintBlur.enabled
        savedGlass = Defaults.liquidGlassForBlur.enabled
        storedBlur = UserDefaults.standard.object(forKey: Defaults.footprintBlur.key)
        storedGlass = UserDefaults.standard.object(forKey: Defaults.liquidGlassForBlur.key)
        Defaults.footprintBlur.enabled = false
        Defaults.liquidGlassForBlur.enabled = false
        UserDefaults.standard.removeObject(forKey: Defaults.footprintBlur.key)
        UserDefaults.standard.removeObject(forKey: Defaults.liquidGlassForBlur.key)
    }
    override func tearDown() {
        Defaults.footprintBlur.enabled = savedBlur
        Defaults.liquidGlassForBlur.enabled = savedGlass
        for (key, value) in [(Defaults.footprintBlur.key, storedBlur), (Defaults.liquidGlassForBlur.key, storedGlass)] {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        Notification.Name.blurStyleChanged.post()
    }
    func testOpeningAndReloadingSettingsDoesNotCreateMaterialChoices() {
        let model = SnapAreaViewModel()
        model.syncDefaults()
        XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintBlur.key))
        XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.liquidGlassForBlur.key))
    }
    func testFirstUserEnablingBlurSelectsGlassOnlyOnSupportedSystems() {
        let model = SnapAreaViewModel()
        model.footprintBlur = true
        XCTAssertTrue(Defaults.footprintBlur.enabled)
        if #available(macOS 26, *) {
            XCTAssertTrue(model.liquidGlassForBlur)
            XCTAssertTrue(Defaults.liquidGlassForBlur.enabled)
        } else {
            XCTAssertFalse(Defaults.liquidGlassForBlur.enabled)
        }
    }
    func testExplicitlyDisabledGlassSurvivesBlurOffOnAndReload() {
        let model = SnapAreaViewModel()
        model.footprintBlur = true
        model.liquidGlassForBlur = false
        model.footprintBlur = false
        model.syncDefaults()
        model.footprintBlur = true
        XCTAssertFalse(model.liquidGlassForBlur)
        XCTAssertFalse(Defaults.liquidGlassForBlur.enabled)
    }
    func testImportedDisabledChoiceIsRespectedBeforeFirstBlurToggle() {
        Defaults.liquidGlassForBlur.load(from: CodableDefault(bool: false))
        let model = SnapAreaViewModel()
        model.footprintBlur = true
        XCTAssertFalse(model.liquidGlassForBlur)
        XCTAssertFalse(Defaults.liquidGlassForBlur.enabled)
    }
}
