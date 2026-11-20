/// WindowSizeConstraintTests.swift

import XCTest
@testable import Rectangle

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

    func testCharacterCellTerminalsAllowUpToACell() {
        let withinCell = CGRect(x: 0, y: 0, width: requested.width + 17, height: requested.height + 30)
        XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: requested, actual: withinCell,
                                                       action: .firstThird, bundleId: { "com.apple.Terminal" }))
        XCTAssertTrue(WindowSizeConstraint.isExceeded(requested: requested, actual: withinCell,
                                                      action: .firstThird, bundleId: { "com.example.app" }))
        XCTAssertTrue(WindowSizeConstraint.isExceeded(requested: requested, actual: withinCell,
                                                      action: .firstThird, bundleId: { nil }))

        let beyondCell = CGRect(x: 0, y: 0, width: requested.width + 100, height: requested.height)
        XCTAssertTrue(WindowSizeConstraint.isExceeded(requested: requested, actual: beyondCell,
                                                      action: .firstThird, bundleId: { "com.apple.Terminal" }))
    }

    func testBundleIdIsOnlyLookedUpWhenLargerThanRequested() {
        var lookups = 0
        XCTAssertFalse(WindowSizeConstraint.isExceeded(requested: requested, actual: requested, action: .firstThird,
                                                       bundleId: { lookups += 1; return "com.apple.Terminal" }))
        XCTAssertEqual(lookups, 0)
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
            (Defaults.todo, CodableDefault(int: 2)),
            (Defaults.showMinimumWindowSizeWarning, CodableDefault(int: 1))
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
                                        placement: ImmediateWindowPlacement? = nil) {
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
                                        placement: ImmediateWindowPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            currentFrame = acceptedFrame(frame)
        }
    }

    private final class RecordingSizeConstraint: WindowSizeConstraint {
        private(set) var warningScreens: [NSScreen] = []
        private(set) var hideCount = 0
        private(set) var warningVisible = false

        override func showWarning(on screen: NSScreen) {
            warningScreens.append(screen)
            warningVisible = true
        }

        override func hideWarning() {
            hideCount += 1
            warningVisible = false
        }
    }

    private final class TestWindowManager: WindowManager {
        private let recorder: RecordingSizeConstraint
        var warningScreens: [NSScreen] { recorder.warningScreens }
        var hideCount: Int { recorder.hideCount }
        var warningVisible: Bool { recorder.warningVisible }
        var didFinish: (() -> Void)?

        init(screenDetection: ScreenDetection) {
            let recorder = RecordingSizeConstraint()
            self.recorder = recorder
            super.init(screenDetection: screenDetection, sizeConstraint: recorder)
        }

        override func windowMovedAcrossDisplays(windowElement: AccessibilityElement, windowId: CGWindowID?,
                                                resultingRect: CGRect, destination: NSScreen, preservesFocus: Bool) {}

        override func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
            super.postProcess(result: result, resultingRect: resultingRect, incrementCount: incrementCount)
            didFinish?()
        }
    }
}
