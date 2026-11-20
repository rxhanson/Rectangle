/// BandTilingTests.swift

import XCTest
@testable import Rectangle

class BandTilingTests: XCTestCase {

    private typealias Manager = MultiWindowManager

    /// The real Todo window, when Todo is on where the tests run, can share a window id
    /// with a test window, so tests that aren't about Todo must not consult `TodoManager`.
    private static let noTodoWindow: (AccessibilityElement) -> Bool = { _ in false }

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
                                                          isActiveTodoWindow: Self.noTodoWindow, screenFor: { detection.detectScreens(using: $0)?.currentScreen }).windows
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
                                              isActiveTodoWindow: Self.noTodoWindow, screenFor: { detection.detectScreens(using: $0)?.currentScreen }).windows
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
                                                  isActiveTodoWindow: Self.noTodoWindow, screenFor: { $0 === otherDisplay ? otherScreen : screen }).windows
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
                                                      isActiveTodoWindow: Self.noTodoWindow, screenFor: { $0 === focused ? left : right }).windows
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
