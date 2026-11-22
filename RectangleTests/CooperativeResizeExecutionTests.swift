//
//  CooperativeResizeExecutionTests.swift
//  RectangleTests
//
//  Pins what WindowManager.execute does end to end for cooperative resize and
//  for completion handling, so the placement code can be restructured safely.
//

import XCTest
@testable import Rectangle

final class CooperativeResizeExecutionTests: XCTestCase {
    private let screen = TestScreen(frame: CGRect(x: 0, y: 0, width: 1200, height: 900))
    private let secondScreen = TestScreen(frame: CGRect(x: 1200, y: 0, width: 1200, height: 900))
    private var writes: [CGWindowID] = []
    private var savedDefaults: [(Default, CodableDefault)] = []
    private var savedRestoreRects: [CGWindowID: CGRect] = [:]
    private var savedActions: [CGWindowID: RectangleAction] = [:]
    private var savedLogging = false

    private let focusedId: CGWindowID = 610_001
    private let neighborId: CGWindowID = 610_002
    private let stackedId: CGWindowID = 610_003

    override func setUp() {
        super.setUp()
        let settings: [(Default, CodableDefault)] = [
            (Defaults.subsequentExecutionMode, CodableDefault(int: SubsequentExecutionMode.resize.rawValue)),
            (Defaults.cooperativeCornerResize, CodableDefault(bool: true)),
            (Defaults.cornerCycleExpansionAxis, CodableDefault(int: CornerCycleExpansionMode.vertical.rawValue)),
            (Defaults.experimentalWindowAnimations, CodableDefault(bool: false)),
            (Defaults.useCursorScreenDetection, CodableDefault(bool: false)),
            (Defaults.moveFixedSizeToEdge, CodableDefault(int: EdgeAlignment.edgesAndCorners.rawValue)),
            (Defaults.horizontalSplitRatio, CodableDefault(float: 50)),
            (Defaults.verticalSplitRatio, CodableDefault(float: 50)),
            (Defaults.halvesPreserveOtherAxisSize, CodableDefault(bool: false)),
            (Defaults.cycleSizesIsChanged, CodableDefault(bool: false)),
            (Defaults.gapSize, CodableDefault(float: 0)),
            (Defaults.skipGapTopEdge, CodableDefault(bool: false)),
            (Defaults.stageSize, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapLeft, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapRight, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapTop, CodableDefault(float: 0)),
            (Defaults.screenEdgeGapBottom, CodableDefault(float: 0)),
            (Defaults.cyclingOverlapOffset, CodableDefault(int: 2)),
            (Defaults.combinedDisplayMode, CodableDefault(int: 2)),
            (Defaults.moveCursor, CodableDefault(int: 2)),
            (Defaults.moveCursorAcrossDisplays, CodableDefault(int: 2)),
            (Defaults.showMinimumWindowSizeWarning, CodableDefault(int: 2)),
            (Defaults.todo, CodableDefault(int: 2))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
        savedRestoreRects = AppDelegate.windowHistory.restoreRects
        savedActions = AppDelegate.windowHistory.lastRectangleActions
        for id in [focusedId, neighborId, stackedId] {
            AppDelegate.windowHistory.restoreRects.removeValue(forKey: id)
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: id)
        }
        ActiveSideSplitRatios.shared.resetAll()
        savedLogging = Logger.logging
        Logger.logging = false
        writes = []
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        AppDelegate.windowHistory.restoreRects = savedRestoreRects
        AppDelegate.windowHistory.lastRectangleActions = savedActions
        ActiveSideSplitRatios.shared.resetAll()
        Logger.logging = savedLogging
        super.tearDown()
    }

    // MARK: - Cooperative placement

    func testRepeatedCornerActionResizesNeighborBeforeExpandingFocusedWindow() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 450))
        let neighbor = window(neighborId, CGRect(x: 0, y: 450, width: 600, height: 450))
        seedHistory(focused, action: .bottomLeft)

        execute(.bottomLeft, on: focused, among: [focused, neighbor])

        assertFrame(focused, CGRect(x: 0, y: 0, width: 600, height: 600))
        assertFrame(neighbor, CGRect(x: 0, y: 600, width: 600, height: 300))
        assertWritten(neighborId, before: focusedId)
        assertHistory(focused, action: .bottomLeft, count: 2)
        assertHistory(neighbor, action: .topLeft, count: 1)
        XCTAssertEqual(ActiveSideSplitRatios.shared.verticalRatio(for: screen.frame), 300.0 / 900.0, accuracy: 0.001)
    }

    func testRepeatedSideActionCyclesAndOrdersWritesByDirection() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900))
        seedHistory(focused, action: .leftHalf)
        seedHistory(neighbor, action: .rightHalf)

        // Expanding: the neighbor makes room first.
        execute(.leftHalf, on: focused, among: [focused, neighbor])
        assertFrame(focused, CGRect(x: 0, y: 0, width: 800, height: 900))
        assertFrame(neighbor, CGRect(x: 800, y: 0, width: 400, height: 900))
        assertWritten(neighborId, before: focusedId)
        assertHistory(focused, action: .leftHalf, count: 2)
        assertHistory(neighbor, action: .rightHalf, count: 2)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), 800.0 / 1200.0, accuracy: 0.001)

        // Shrinking: the focused window gives up the room first.
        writes = []
        execute(.leftHalf, on: focused, among: [focused, neighbor])
        assertFrame(focused, CGRect(x: 0, y: 0, width: 400, height: 900))
        assertFrame(neighbor, CGRect(x: 400, y: 0, width: 800, height: 900))
        assertWritten(focusedId, before: neighborId)
        assertHistory(focused, action: .leftHalf, count: 3)
        assertHistory(neighbor, action: .rightHalf, count: 3)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), 400.0 / 1200.0, accuracy: 0.001)
    }

    func testSideSwitchMovesWindowWithoutResizingNeighbor() {
        Defaults.subsequentExecutionMode.value = .switchSides
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.leftHalf, on: focused, among: [focused, neighbor])

        assertFrame(focused, CGRect(x: 600, y: 0, width: 600, height: 900))
        assertUntouched(neighbor)
    }

    func testNeighborMinimumTriggersCorrectionPassThatPreservesHistoryCounts() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        // The neighbor enforces a minimum width that it doesn't report through AX.
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900)) { requested in
            var accepted = requested
            accepted.size.width = max(requested.width, 500)
            return accepted
        }
        seedHistory(focused, action: .leftHalf)
        seedHistory(neighbor, action: .rightHalf)

        execute(.leftHalf, on: focused, among: [focused, neighbor])

        assertFrame(focused, CGRect(x: 0, y: 0, width: 700, height: 900))
        assertFrame(neighbor, CGRect(x: 700, y: 0, width: 500, height: 900))
        // The correction runs before the focused window moves, so it never gets the width that doesn't fit.
        XCTAssertEqual(focused.requestedFrames.map(\.width), [700])
        assertHistory(focused, action: .leftHalf, count: 2)
        // Advanced once by the first pass, and not again by the correction.
        XCTAssertEqual(history(of: neighbor)?.count, 2)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), 700.0 / 1200.0, accuracy: 0.001)
    }

    func testFocusedMinimumTriggersSettlingPassThatPreservesHistoryCounts() {
        // The focused window refuses the size only when it is written, after the neighbor has
        // already moved, so only the final settling pass can repair the layout.
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 800, height: 900)) { requested in
            var accepted = requested
            accepted.size.width = max(requested.width, 500)
            return accepted
        }
        let neighbor = window(neighborId, CGRect(x: 800, y: 0, width: 400, height: 900))
        seedHistory(focused, action: .leftHalf, count: 2)
        seedHistory(neighbor, action: .rightHalf, count: 2)

        execute(.leftHalf, on: focused, among: [focused, neighbor])

        assertFrame(focused, CGRect(x: 0, y: 0, width: 500, height: 900))
        assertFrame(neighbor, CGRect(x: 500, y: 0, width: 700, height: 900))
        assertHistory(focused, action: .leftHalf, count: 3)
        // Advanced once by the first pass, and not again by settling.
        assertHistory(neighbor, action: .rightHalf, count: 3)
        XCTAssertEqual(history(of: neighbor)?.rect, neighbor.frame)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), 500.0 / 1200.0, accuracy: 0.001)
    }

    func testWritesMatchingAndAdjacentWindowsInOrderOfDirection() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let stacked = window(stackedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900))
        seedHistory(focused, action: .leftHalf)

        // Expanding: the adjacent window makes room before the matching one grows into it.
        execute(.leftHalf, on: focused, among: [focused, stacked, neighbor])
        assertFrame(stacked, CGRect(x: 0, y: 0, width: 800, height: 900))
        assertFrame(neighbor, CGRect(x: 800, y: 0, width: 400, height: 900))
        assertWritten(neighborId, before: stackedId)

        // Shrinking: the matching window gives up the room before the adjacent one takes it.
        writes = []
        execute(.leftHalf, on: focused, among: [focused, stacked, neighbor])
        assertFrame(stacked, CGRect(x: 0, y: 0, width: 400, height: 900))
        assertFrame(neighbor, CGRect(x: 400, y: 0, width: 800, height: 900))
        assertWritten(stackedId, before: neighborId)
    }

    func testReportedFocusedMinimumRevisesTheRequestedTarget() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 800, height: 900))
        focused.reportedMinimumSize = CGSize(width: 700, height: 100)
        let neighbor = window(neighborId, CGRect(x: 800, y: 0, width: 400, height: 900))
        seedHistory(focused, action: .leftHalf, count: 2)
        let manager = makeManager(windows: [focused, neighbor])

        manager.execute(ExecutionParameters(.leftHalf, windowElement: focused))

        assertFrame(focused, CGRect(x: 0, y: 0, width: 700, height: 900))
        assertFrame(neighbor, CGRect(x: 700, y: 0, width: 500, height: 900))
        XCTAssertEqual(manager.lastResult?.calcResult.rect, CGRect(x: 0, y: 0, width: 700, height: 900))
    }

    func testCycleLookAheadRecordsTheFrameItSkippedTo() {
        // A neighbor already between the two smallest cycle sizes can't give up the room
        // the next size needs, so that press moves on to the following size.
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 700, height: 900))
        let neighbor = window(neighborId, CGRect(x: 700, y: 0, width: 500, height: 900))
        seedHistory(focused, action: .leftHalf)
        let manager = makeManager(windows: [focused, neighbor])

        manager.execute(ExecutionParameters(.leftHalf, windowElement: focused))

        assertFrame(focused, CGRect(x: 0, y: 0, width: 400, height: 900))
        assertFrame(neighbor, CGRect(x: 400, y: 0, width: 800, height: 900))
        XCTAssertEqual(manager.lastResult?.calcResult.initialRect, CGRect(x: 0, y: 0, width: 400, height: 900))
    }

    func testFinalFrameIsReadAgainAfterCleanupMovesTheFocusedWindow() {
        // The ratio puts the right half directly beside the window left behind, so the
        // cleanup that shrinks that window also grows the focused one.
        ActiveSideSplitRatios.shared.recordSideAction(.leftHalf, targetFrame: CGRect(x: 0, y: 0, width: 500, height: 900),
                                                      screenFrame: screen.frame)
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let stacked = window(stackedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.rightHalf, on: focused, among: [focused, stacked])

        assertFrame(stacked, CGRect(x: 0, y: 0, width: 400, height: 900))
        assertFrame(focused, CGRect(x: 400, y: 0, width: 800, height: 900))
        XCTAssertEqual(history(of: focused)?.rect, focused.frame)
    }

    func testCleanupShrinksRemainingSourceWindowAfterFocusedWindowLeaves() {
        // Both left windows sit in the band between the two smallest cycle sizes.
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let stacked = window(stackedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let neighbor = window(neighborId, CGRect(x: 500, y: 0, width: 700, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.maximize, on: focused, among: [focused, stacked, neighbor])

        assertFrame(stacked, CGRect(x: 0, y: 0, width: 400, height: 900))
        assertFrame(neighbor, CGRect(x: 400, y: 0, width: 800, height: 900))
        assertHistory(focused, action: .maximize, count: 1)
    }

    func testMenuItemSourceDoesNotRunCleanup() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let stacked = window(stackedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let neighbor = window(neighborId, CGRect(x: 500, y: 0, width: 700, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.maximize, on: focused, among: [focused, stacked, neighbor], source: .menuItem)

        assertFrame(focused, CGRect(x: 0, y: 0, width: 1200, height: 900))
        assertUntouched(stacked)
        assertUntouched(neighbor)
    }

    func testCooperativeNoOpRecordsAchievedRatioWithoutWritingFrames() {
        // Within layout tolerance of the half split. Without a plan this would write 600.
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 598, height: 900))
        let neighbor = window(neighborId, CGRect(x: 598, y: 0, width: 602, height: 900))
        var completions = 0
        let manager = makeManager(windows: [focused, neighbor])

        manager.execute(ExecutionParameters(.leftHalf, windowElement: focused, completion: { completions += 1 }))

        XCTAssertEqual(writes, [])
        XCTAssertEqual(completions, 1)
        // A no-op must not count as a placement, which would also supersede a pending one.
        XCTAssertEqual(manager.postProcessCount, 0)
        assertHistory(focused, action: .leftHalf, count: 1)
        XCTAssertEqual(history(of: focused)?.rect, focused.frame)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), 598.0 / 1200.0, accuracy: 0.001)
    }

    func testFeatureOffLeavesNeighborAloneAndRecordsNoSideRatio() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.leftHalf, on: focused, among: [focused, neighbor])

        assertFrame(focused, CGRect(x: 0, y: 0, width: 800, height: 900))
        assertUntouched(neighbor)
        assertHistory(focused, action: .leftHalf, count: 2)

        // A move made while off must not affect the split once the feature is on.
        Defaults.cooperativeCornerResize.enabled = true
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), 0.5, accuracy: 0.001)
    }

    func testDifferentNonCooperativeActionIsNotARepeat() {
        let savedResizeOnDirectionalMove = Defaults.resizeOnDirectionalMove.enabled
        defer { Defaults.resizeOnDirectionalMove.enabled = savedResizeOnDirectionalMove }
        Defaults.resizeOnDirectionalMove.enabled = true
        let fullScreen = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let rightSide = CGRect(x: 600, y: 0, width: 600, height: 900)

        assertFirstPress(of: .centerHalf, after: .maximize, from: fullScreen, landsAt: CGRect(x: 300, y: 0, width: 600, height: 900))
        assertFirstPress(of: .moveLeft, after: .maximize, from: fullScreen, landsAt: CGRect(x: 0, y: 0, width: 600, height: 900))
        assertFirstPress(of: .moveLeft, after: .moveRight, from: rightSide, landsAt: CGRect(x: 0, y: 0, width: 600, height: 900))
    }

    func testSameNonCooperativeActionStillCycles() {
        let focused = window(focusedId, CGRect(x: 300, y: 0, width: 600, height: 900))
        seedHistory(focused, action: .centerHalf)

        execute(.centerHalf, on: focused, among: [focused])

        assertFrame(focused, CGRect(x: 200, y: 0, width: 800, height: 900))
    }

    func testHalfAndCornerOnTheSameEdgeAreNotRepeats() {
        Defaults.cornerCycleExpansionAxis.value = .horizontal
        assertFirstPress(of: .topLeft, after: .leftHalf, from: CGRect(x: 0, y: 0, width: 600, height: 900),
                         landsAt: CGRect(x: 0, y: 450, width: 600, height: 450))
        assertFirstPress(of: .leftHalf, after: .topLeft, from: CGRect(x: 0, y: 450, width: 600, height: 450),
                         landsAt: CGRect(x: 0, y: 0, width: 600, height: 900))

        Defaults.cornerCycleExpansionAxis.value = .vertical
        assertFirstPress(of: .topLeft, after: .topHalf, from: CGRect(x: 0, y: 450, width: 1200, height: 450),
                         landsAt: CGRect(x: 0, y: 450, width: 600, height: 450))
        assertFirstPress(of: .topHalf, after: .topLeft, from: CGRect(x: 0, y: 450, width: 600, height: 450),
                         landsAt: CGRect(x: 0, y: 450, width: 1200, height: 450))
    }

    private func assertFirstPress(of action: WindowAction, after previous: WindowAction, from start: CGRect, landsAt expected: CGRect,
                                  file: StaticString = #filePath, line: UInt = #line) {
        ActiveSideSplitRatios.shared.resetAll()
        let focused = window(focusedId, start)
        seedHistory(focused, action: previous)

        execute(action, on: focused, among: [focused])

        assertFrame(focused, expected, file: file, line: line)
    }

    func testCrossDisplayMoveHasNoPlanAndNoCleanup() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let stacked = window(stackedId, CGRect(x: 0, y: 0, width: 500, height: 900))
        let sourceNeighbor = window(neighborId, CGRect(x: 500, y: 0, width: 700, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.rightHalf, on: focused, among: [focused, stacked, sourceNeighbor], screen: secondScreen)

        assertFrame(focused, CGRect(x: 1800, y: 0, width: 600, height: 900))
        assertUntouched(stacked)
        assertUntouched(sourceNeighbor)
    }

    func testMenuItemSourceDoesNotCooperate() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900))
        seedHistory(focused, action: .leftHalf)

        execute(.leftHalf, on: focused, among: [focused, neighbor], source: .menuItem)

        assertFrame(focused, CGRect(x: 0, y: 0, width: 800, height: 900))
        assertUntouched(neighbor)
    }

    func testSettingDisablesAnimationForActionsThatCannotCooperate() throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        Defaults.cooperativeCornerResize.enabled = true
        XCTAssertFalse(WindowAnimator.enabled)
        let focused = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 400))

        // Only an animated placement reports its history count as already incremented.
        let manager = makeManager(windows: [focused])
        manager.execute(ExecutionParameters(.maximize, windowElement: focused))
        XCTAssertEqual(manager.lastIncrementCount, true)

        Defaults.cooperativeCornerResize.enabled = false
        focused.setFrame(CGRect(x: 100, y: 100, width: 400, height: 400).screenFlipped)
        let control = makeManager(windows: [focused])
        control.execute(ExecutionParameters(.maximize, windowElement: focused))
        XCTAssertEqual(control.lastIncrementCount, false)
    }

    // MARK: - Hooks

    func testGapAdjusterOnlyChangesTheTargetWhenGapsAreSet() {
        let target = CGRect(x: 0, y: 0, width: 600, height: 900)
        var result = WindowCalculationResult(rect: target, screen: screen, resultingAction: .leftHalf)

        GapTargetAdjuster().adjust(&result, action: .leftHalf, windowId: focusedId)
        XCTAssertEqual(result.rect, target)

        Defaults.gapSize.value = 10
        GapTargetAdjuster().adjust(&result, action: .leftHalf, windowId: focusedId)
        XCTAssertNotEqual(result.rect, target)
        XCTAssertTrue(target.contains(result.rect))
    }

    func testOverlapOffsetAdjusterLeavesTheTargetAloneWhileDisabled() {
        let target = CGRect(x: 0, y: 0, width: 1200, height: 900)
        var result = WindowCalculationResult(rect: target, screen: screen, resultingAction: .maximize)

        OverlapOffsetTargetAdjuster().adjust(&result, action: .maximize, windowId: focusedId)

        XCTAssertEqual(result.rect, target)
    }

    func testDelegateRevisedTargetIsPlacedAndSettled() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 400))
        let revised = CGRect(x: 0, y: 0, width: 500, height: 900)
        let manager = makeManager(windows: [focused])
        var stub: StubDelegate?
        manager.delegate = { request in
            stub = StubDelegate(request)
            stub?.calcResult.rect = revised
            return stub
        }

        manager.execute(ExecutionParameters(.leftHalf, windowElement: focused))

        assertFrame(focused, revised)
        XCTAssertEqual(manager.lastResult?.calcResult.rect, revised)
        XCTAssertEqual(stub?.placeCount, 1)
        XCTAssertEqual(stub?.settledCount, 1)
    }

    func testDelegateThatReportsAchievedSkipsPlacement() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 400))
        let manager = makeManager(windows: [focused])
        var completions = 0
        manager.delegate = { request in
            let stub = StubDelegate(request)
            stub.achieved = true
            return stub
        }

        manager.execute(ExecutionParameters(.leftHalf, windowElement: focused, completion: { completions += 1 }))

        XCTAssertEqual(writes, [])
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(manager.postProcessCount, 0)
        assertHistory(focused, action: .leftHalf, count: 1)
    }

    func testDelegatePlacesAndIsSettledOnlyOnTheSourceScreen() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 400))
        let manager = makeManager(windows: [focused])
        var stub: StubDelegate?
        manager.delegate = { request in
            stub = StubDelegate(request)
            return stub
        }

        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: focused))

        assertFrame(focused, CGRect(x: 1800, y: 0, width: 600, height: 900))
        XCTAssertEqual(stub?.placeCount, 1)
        XCTAssertEqual(stub?.settledCount, 0)
    }

    func testMinimumSizeIsNotReadWhileCooperativeResizeIsOff() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 400))

        execute(.leftHalf, on: focused, among: [focused])

        assertFrame(focused, CGRect(x: 0, y: 0, width: 600, height: 900))
        XCTAssertEqual(focused.minimumSizeReads, 0)
    }

    // MARK: - Fit and cooperative resize

    func testFitClaimFillsRemaining480WithoutChangingTheAnchorOldGroupOrRatio() {
        let oldGroup = CGRect(x: 0, y: 0, width: 500, height: 900)
        let anchor = window(neighborId, CGRect(x: 0, y: 0, width: 720, height: 900))
        let incoming = window(focusedId, oldGroup)
        let oldNeighbor = window(stackedId, oldGroup)
        seedHistory(incoming, action: .leftHalf)
        ActiveSideSplitRatios.shared.recordSideAction(.leftHalf, targetFrame: oldGroup, screenFrame: screen.frame)
        let ratio = ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame)
        let target = CGRect(x: 720, y: 0, width: 480, height: 900)
        let fit = fitProvider(anchor: anchor) { request, opportunity in
            XCTAssertEqual(request.action, .rightHalf)
            return .fit(SnappedWindowFit(target: target.screenFlipped, neighbor: opportunity))
        }
        let manager = makeManager(windows: [incoming, anchor, oldNeighbor], beforeCooperative: [fit])
        let completed = expectation(description: "Fit placement completed")

        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, completion: { completed.fulfill() }))
        wait(for: [completed], timeout: 2)

        assertFrame(incoming, target)
        assertUntouched(anchor)
        assertUntouched(oldNeighbor)
        XCTAssertEqual(ActiveSideSplitRatios.shared.horizontalRatio(for: screen.frame), ratio)
        assertHistory(incoming, action: .rightHalf, count: 1)
        XCTAssertEqual(history(of: incoming)?.rect, incoming.frame)
    }

    func testAlreadyAchievedFitClaimsWithoutWritingOrInvokingCooperativeResize() {
        let target = CGRect(x: 720, y: 0, width: 480, height: 900)
        let anchor = window(neighborId, CGRect(x: 0, y: 0, width: 720, height: 900))
        let incoming = window(focusedId, target)
        let fit = fitProvider(anchor: anchor) { _, opportunity in
            .fit(SnappedWindowFit(target: target.screenFlipped, neighbor: opportunity))
        }
        let manager = makeManager(windows: [incoming, anchor], beforeCooperative: [fit])
        var completions = 0

        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, completion: { completions += 1 }))

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(manager.postProcessCount, 0)
        assertHistory(incoming, action: .rightHalf, count: 1)
    }

    func testFitPassLetsCooperativeResizeCycleBothWindows() {
        let incoming = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let neighbor = window(neighborId, CGRect(x: 600, y: 0, width: 600, height: 900))
        seedHistory(incoming, action: .leftHalf)
        seedHistory(neighbor, action: .rightHalf)
        let fit = fitProvider(anchor: neighbor) { _, _ in .unchanged }
        let manager = makeManager(windows: [incoming, neighbor], beforeCooperative: [fit])

        manager.execute(ExecutionParameters(.leftHalf, windowElement: incoming))

        assertFrame(incoming, CGRect(x: 0, y: 0, width: 800, height: 900))
        assertFrame(neighbor, CGRect(x: 800, y: 0, width: 400, height: 900))
        assertWritten(neighborId, before: focusedId)
        assertHistory(incoming, action: .leftHalf, count: 2)
    }

    func testFitRejectionPreservesStaleHistoryAndDoesNotSupersedePriorCrossDisplayRetry() {
        let retrying = clampingWindow()
        let anchor = window(neighborId, CGRect(x: 0, y: 0, width: 995, height: 900))
        let incoming = window(stackedId, CGRect(x: 100, y: 100, width: 400, height: 400))
        let priorFrame = CGRect(x: 50, y: 50, width: 500, height: 350)
        let priorRestore = CGRect(x: 20, y: 60, width: 500, height: 300)
        AppDelegate.windowHistory.lastRectangleActions[stackedId] = RectangleAction(action: .centerHalf,
                                                                                    rect: priorFrame, count: 2)
        AppDelegate.windowHistory.restoreRects[stackedId] = priorRestore
        var fitEnabled = false
        let fit = fitProvider(anchor: anchor, enabled: { fitEnabled }) { _, _ in .noRoom }
        let manager = makeManager(windows: [incoming, anchor, retrying], beforeCooperative: [fit])
        let retryFinished = expectation(description: "Earlier cross-display retry still finished")
        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: retrying,
                                            completion: { retryFinished.fulfill() }))
        XCTAssertEqual(manager.postProcessCount, 0)
        fitEnabled = true
        var completions = 0

        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, completion: { completions += 1 }))

        XCTAssertEqual(completions, 1)
        assertUntouched(incoming)
        assertUntouched(anchor)
        assertHistory(incoming, action: .centerHalf, count: 2)
        XCTAssertEqual(history(of: incoming)?.rect, priorFrame)
        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[stackedId], priorRestore)
        XCTAssertEqual(manager.postProcessCount, 0)
        wait(for: [retryFinished], timeout: 1)
        XCTAssertEqual(retrying.frame.size, CGSize(width: 600, height: 900))
        XCTAssertEqual(manager.postProcessCount, 1)
    }

    func testFitLosingItsAnchorDuringTheWriteRestoresTheIncomingWindowAndPriorHistory() {
        assertFitRollback(refused: false)
    }

    func testFitWithARefusedRollbackRetainsThePhysicalOriginForRestoreAndForgetsTheAction() {
        assertFitRollback(refused: true)
    }

    func testFitLosingItsAnchorBeforeDelayedCrossDisplayRetryRollsBackAndCallsCompletionOnce() {
        assertFitInterruptedBeforeDelayedRetry(.anchorChanged)
    }

    func testDisplayChangeBeforeDelayedFitRetryKeepsPartialFrameAndClearsOldAction() {
        // The fake AX identity makes the requested animation fall back to direct placement.
        // Its animation monitor has stopped before the delayed display retry starts.
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        assertFitInterruptedBeforeDelayedRetry(.environmentChanged)
    }

    private func assertFitInterruptedBeforeDelayedRetry(_ reason: WindowPlacementInvalidation) {
        let anchor = window(neighborId, CGRect(x: 1200, y: 0, width: 720, height: 900))
        let origin = CGRect(x: 100, y: 100, width: 400, height: 500)
        let target = CGRect(x: 1920, y: 0, width: 480, height: 900)
        let incoming = window(focusedId, origin) { requested in
            guard requested == target else { return requested }
            var clamped = requested
            clamped.size.width -= 100
            return clamped
        }
        seedHistory(incoming, action: .leftHalf, count: 2)
        let priorRestore = CGRect(x: 30, y: 40, width: 300, height: 300)
        AppDelegate.windowHistory.restoreRects[focusedId] = priorRestore
        var anchorIsCurrent = true
        let notifications = NotificationCenter()
        let fit = fitProvider(anchor: anchor, on: secondScreen, notifications: notifications,
                              validateNeighbor: { _ in anchorIsCurrent }) { _, opportunity in
            .fit(SnappedWindowFit(target: target.screenFlipped, neighbor: opportunity))
        }
        let manager = makeManager(windows: [incoming, anchor], beforeCooperative: [fit])
        let events = PlacementEvents()
        let finished = expectation(description: "Interrupted retry finished")
        var completions = 0

        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: incoming, source: .dragToSnap,
                                            completion: { completions += 1; finished.fulfill() }))
        XCTAssertEqual(incoming.requestedFrames.filter { $0 == target }.count, 2)
        XCTAssertEqual(completions, 0)
        let partial = incoming.frame
        let writesBeforeInterruption = incoming.requestedFrames
        XCTAssertNotEqual(partial, origin.screenFlipped)
        XCTAssertNotEqual(partial, target.screenFlipped)
        switch reason {
        case .anchorChanged: anchorIsCurrent = false
        case .environmentChanged: NSApplication.didChangeScreenParametersNotification.post(center: notifications)
        }
        wait(for: [finished], timeout: 2)

        XCTAssertEqual(incoming.requestedFrames.filter { $0 == target }.count, 2)
        switch reason {
        case .anchorChanged:
            assertFrame(incoming, origin)
            assertHistory(incoming, action: .leftHalf, count: 2)
            XCTAssertEqual(history(of: incoming)?.rect, origin.screenFlipped)
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], priorRestore)
        case .environmentChanged:
            XCTAssertEqual(incoming.frame, partial)
            XCTAssertEqual(incoming.requestedFrames, writesBeforeInterruption)
            XCTAssertNil(history(of: incoming))
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], origin.screenFlipped)
        }
        assertUntouched(anchor)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(events.legacyCompletions, 0)
        XCTAssertTrue(events.settlements.isEmpty)
    }

    func testFitAnimationFallbackKeepsPreviousCountAndFrameUntilPlacementSettles() throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        let origin = CGRect(x: 100, y: 100, width: 400, height: 500)
        let anchor = window(neighborId, CGRect(x: 0, y: 0, width: 720, height: 900))
        let target = CGRect(x: 720, y: 0, width: 480, height: 900)
        let incoming = window(focusedId, origin)
        XCTAssertTrue(incoming.canAnimate)
        seedHistory(incoming, action: .rightHalf, count: 2)
        let fit = fitProvider(anchor: anchor) { _, opportunity in
            .fit(SnappedWindowFit(target: target.screenFlipped, neighbor: opportunity))
        }
        let manager = makeManager(windows: [incoming, anchor], beforeCooperative: [fit])
        let events = PlacementEvents()
        let applied = expectation(description: "Animator used synchronous fallback for the synthetic window")
        manager.afterNextApply = {
            XCTAssertEqual(incoming.frame, target.screenFlipped)
            self.assertHistory(incoming, action: .rightHalf, count: 2)
            XCTAssertEqual(self.history(of: incoming)?.rect, origin.screenFlipped)
            XCTAssertTrue(events.settlements.isEmpty)
            applied.fulfill()
        }
        let request = ExecutionParameters(.rightHalf, windowElement: incoming)

        manager.execute(request)
        wait(for: [applied], timeout: 2)

        assertHistory(incoming, action: .rightHalf, count: 3)
        XCTAssertEqual(history(of: incoming)?.rect, target.screenFlipped)
        XCTAssertEqual(events.settlements, [request.requestID])
        assertUntouched(anchor)
    }

    func testAnimatorCancellationFollowedByEnvironmentChangeLeavesTheInterruptedFrameAlone() throws {
        try assertInterruptedAnimation(reason: .environmentChanged, animatorCancelsFirst: true)
    }

    func testAnchorLossBeforeAnimatorCancellationRollsBackAndCancelsOnlyOnce() throws {
        try assertInterruptedAnimation(reason: .anchorChanged, animatorCancelsFirst: false)
    }

    func testAnimatorCancellationFollowedByAnchorLossStillRecoversTheOriginalFrame() throws {
        try assertInterruptedAnimation(reason: .anchorChanged, animatorCancelsFirst: true)
    }

    private func assertInterruptedAnimation(reason: WindowPlacementInvalidation, animatorCancelsFirst: Bool) throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        let origin = CGRect(x: 130, y: 180, width: 400, height: 450)
        let partial = CGRect(x: 380, y: 90, width: 480, height: 620)
        let incoming = window(focusedId, origin)
        let previousRestore = CGRect(x: 70, y: 80, width: 500, height: 300)
        AppDelegate.windowHistory.restoreRects[focusedId] = previousRestore
        seedHistory(incoming, action: .leftHalf, count: 2)
        let manager = makeManager(windows: [incoming])
        let condition = TestPlacementCondition()
        manager.delegate = { StubDelegate($0, condition: condition) }
        let animation = HeldAnimation()
        manager.heldAnimation = animation
        let events = PlacementEvents()
        var successes = 0
        var cancellations = 0
        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming,
                                            completion: { successes += 1 }, cancellation: { cancellations += 1 }))
        let invalidate = try XCTUnwrap(condition.pendingCancellation)
        let animatorCancelled = try XCTUnwrap(animation.cancellation)
        let animatorCompleted = try XCTUnwrap(animation.completion)
        manager.heldAnimation = nil
        incoming.setFrame(partial.screenFlipped)

        if animatorCancelsFirst {
            animatorCancelled()
            XCTAssertEqual(cancellations, 0)
        }
        condition.invalidation = reason
        invalidate(reason)
        if !animatorCancelsFirst { animatorCancelled() }
        drainMainQueue()

        // A callback can have been queued before its monitor or animator stopped.
        invalidate(reason)
        animatorCancelled()
        animatorCompleted(partial.screenFlipped)
        drainMainQueue()

        switch reason {
        case .environmentChanged:
            assertFrame(incoming, partial)
            XCTAssertEqual(incoming.requestedFrames, [partial])
            XCTAssertNil(history(of: incoming))
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], origin.screenFlipped)
        case .anchorChanged:
            assertFrame(incoming, origin)
            XCTAssertEqual(incoming.requestedFrames, [partial, origin])
            assertHistory(incoming, action: .leftHalf, count: 2)
            XCTAssertEqual(history(of: incoming)?.rect, origin.screenFlipped)
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], previousRestore)
        }
        XCTAssertEqual(condition.stopCount, 1)
        XCTAssertNil(condition.pendingCancellation)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(successes, 0)
        XCTAssertEqual(events.legacyCompletions, 0)
        XCTAssertTrue(events.settlements.isEmpty)
    }

    func testSettledCrossDisplayAnimationIgnoresLateMonitorAndAnimatorCallbacks() throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        let incoming = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 300))
        let target = CGRect(x: 1800, y: 0, width: 600, height: 900)
        let manager = makeManager(windows: [incoming])
        let condition = TestPlacementCondition()
        manager.delegate = { StubDelegate($0, condition: condition) }
        let animation = HeldAnimation()
        manager.heldAnimation = animation
        let events = PlacementEvents()
        var successes = 0
        var cancellations = 0
        let request = ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: incoming, source: .dragToSnap,
                                          completion: { successes += 1 }, cancellation: { cancellations += 1 })

        manager.execute(request)
        let invalidate = try XCTUnwrap(condition.pendingCancellation)
        let animatorCompleted = try XCTUnwrap(animation.completion)
        let animatorCancelled = try XCTUnwrap(animation.cancellation)
        manager.heldAnimation = nil
        incoming.setFrame(target.screenFlipped)
        animatorCompleted(incoming.frame)
        XCTAssertEqual(successes, 1)
        XCTAssertNil(condition.pendingCancellation)
        condition.invalidation = .anchorChanged
        invalidate(.anchorChanged)
        animatorCancelled()
        animatorCompleted(nil)
        drainMainQueue()

        XCTAssertEqual(condition.stopCount, 1)
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(events.legacyCompletions, 1)
        XCTAssertEqual(events.settlements, [request.requestID])
        XCTAssertEqual(incoming.requestedFrames, [target])
        assertHistory(incoming, action: .rightHalf, count: 1)
        XCTAssertEqual(history(of: incoming)?.rect, target.screenFlipped)
    }

    func testConditionalRecoveryRetainsItsWindowAfterAnUnrelatedAction() throws {
        try assertWindowScopedRecovery(sameWindow: false, anchorLost: true)
    }

    func testConditionalRecoveryCannotOverwriteANewerActionOnItsWindow() throws {
        try assertWindowScopedRecovery(sameWindow: true, anchorLost: true)
    }

    func testUnrelatedAnimationPreemptionPreservesThePhysicalRestoreOrigin() throws {
        try assertWindowScopedRecovery(sameWindow: false, anchorLost: false)
    }

    private func assertWindowScopedRecovery(sameWindow: Bool, anchorLost: Bool) throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        let origin = CGRect(x: 100, y: 100, width: 400, height: 300)
        let incoming = window(focusedId, origin)
        let other = window(stackedId, CGRect(x: 200, y: 150, width: 300, height: 250))
        let previousRestore = CGRect(x: 50, y: 60, width: 350, height: 280).screenFlipped
        seedHistory(incoming, action: .centerHalf, count: 3)
        AppDelegate.windowHistory.restoreRects[focusedId] = previousRestore
        let manager = makeManager(windows: [incoming, other])
        let condition = TestPlacementCondition()
        manager.delegate = { request in
            request.windowId == self.focusedId && request.action == .rightHalf
                ? StubDelegate(request, condition: condition) : nil
        }
        let animation = HeldAnimation()
        manager.heldAnimation = animation
        var drainCompletion: (() -> Void)?
        manager.drainWrites = { _, completion in drainCompletion = completion }
        let events = PlacementEvents()
        var successes = 0
        var cancellations = 0
        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, source: .dragToSnap,
                                            completion: { successes += 1 }, cancellation: { cancellations += 1 }))
        let cancelAnimation = try XCTUnwrap(animation.cancellation)
        incoming.setFrame(CGRect(x: 400, y: 0, width: 500, height: 900).screenFlipped)
        if anchorLost {
            condition.invalidation = .anchorChanged
            try XCTUnwrap(condition.pendingCancellation)(.anchorChanged)
            XCTAssertNotNil(drainCompletion)
        } else {
            cancelAnimation()
        }

        manager.heldAnimation = nil
        Defaults.experimentalWindowAnimations.enabled = false
        let newerID = UUID()
        let newerWindow = sameWindow ? incoming : other
        manager.execute(ExecutionParameters(.maximize, windowElement: newerWindow, requestID: newerID))
        if anchorLost { try XCTUnwrap(drainCompletion)() }
        drainMainQueue()

        assertFrame(newerWindow, screen.frame)
        assertHistory(newerWindow, action: .maximize, count: 1)
        if !sameWindow {
            if anchorLost {
                assertFrame(incoming, origin)
                assertHistory(incoming, action: .centerHalf, count: 3)
                XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], previousRestore)
            } else {
                XCTAssertNil(history(of: incoming))
                XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], origin.screenFlipped)
            }
        }
        XCTAssertEqual(successes, 0)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(events.settlements, [newerID])
        XCTAssertEqual(events.legacyCompletions, 1)
    }

    func testAlreadyAchievedPlacementSupersedesConditionalRecoveryOnItsWindow() throws {
        try assertTerminalActionSupersedesRecovery(.leftHalf)
    }

    func testRestoreWithoutAStoredFrameSupersedesConditionalRecoveryOnItsWindow() throws {
        try assertTerminalActionSupersedesRecovery(.restore)
    }

    private func assertTerminalActionSupersedesRecovery(_ action: WindowAction) throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        let incoming = window(focusedId, CGRect(x: 100, y: 100, width: 400, height: 300))
        seedHistory(incoming, action: .centerHalf, count: 2)
        let manager = makeManager(windows: [incoming])
        let condition = TestPlacementCondition()
        manager.delegate = { request in
            request.action == .rightHalf ? StubDelegate(request, condition: condition) : nil
        }
        manager.heldAnimation = HeldAnimation()
        var drainCompletion: (() -> Void)?
        manager.drainWrites = { _, completion in drainCompletion = completion }
        let events = PlacementEvents()
        var cancellations = 0
        manager.execute(ExecutionParameters(.rightHalf, updateRestoreRect: false, windowElement: incoming,
                                            source: .dragToSnap, cancellation: { cancellations += 1 }))
        condition.invalidation = .anchorChanged
        try XCTUnwrap(condition.pendingCancellation)(.anchorChanged)
        XCTAssertNotNil(drainCompletion)
        let current = CGRect(x: 0, y: 0, width: 600, height: 900)
        incoming.setFrame(current.screenFlipped)
        let writes = incoming.requestedFrames
        manager.heldAnimation = nil
        Defaults.experimentalWindowAnimations.enabled = false
        let newerID = UUID()
        var completions = 0
        manager.execute(ExecutionParameters(action, windowElement: incoming,
                                            completion: { completions += 1 }, requestID: newerID))
        let restoreAfterCommand = AppDelegate.windowHistory.restoreRects[focusedId]
        try XCTUnwrap(drainCompletion)()
        drainMainQueue()

        assertFrame(incoming, current)
        XCTAssertEqual(incoming.requestedFrames, writes)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], restoreAfterCommand)
        if action == .restore {
            XCTAssertNil(history(of: incoming))
            XCTAssertTrue(events.settlements.isEmpty)
        } else {
            assertHistory(incoming, action: action, count: 1)
            XCTAssertEqual(events.settlements, [newerID])
        }
    }

    func testAlreadyAchievedPlacementSupersedesADelayedRetryOnItsWindow() {
        Defaults.experimentalWindowAnimations.enabled = false
        Defaults.cooperativeCornerResize.enabled = false
        let incoming = clampingWindow()
        let manager = makeManager(windows: [incoming])
        let events = PlacementEvents()
        let earlierFinished = expectation(description: "Superseded retry completed")
        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: incoming,
                                            completion: { earlierFinished.fulfill() }))
        XCTAssertTrue(events.settlements.isEmpty)
        incoming.stopClamping()
        let current = CGRect(x: 1200, y: 0, width: 600, height: 900)
        incoming.setFrame(current.screenFlipped)
        let writes = incoming.requestedFrames
        let newerID = UUID()
        manager.execute(ExecutionParameters(.leftHalf, screen: secondScreen, windowElement: incoming,
                                            requestID: newerID))
        let restoreAfterCommand = AppDelegate.windowHistory.restoreRects[focusedId]
        wait(for: [earlierFinished], timeout: 2)

        assertFrame(incoming, current)
        XCTAssertEqual(incoming.requestedFrames, writes)
        assertHistory(incoming, action: .leftHalf, count: 1)
        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], restoreAfterCommand)
        XCTAssertEqual(events.settlements, [newerID])
    }

    func testAlreadyAchievedPlacementPreservesAnUnrelatedPendingDisplayRetry() {
        Defaults.experimentalWindowAnimations.enabled = false
        Defaults.cooperativeCornerResize.enabled = false
        let incoming = clampingWindow()
        let other = window(stackedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let manager = makeManager(windows: [incoming, other])
        let events = PlacementEvents()
        let earlierFinished = expectation(description: "Unrelated retry completed")
        let earlierID = UUID()
        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: incoming,
                                            completion: { earlierFinished.fulfill() }, requestID: earlierID))
        XCTAssertTrue(events.settlements.isEmpty)
        let newerID = UUID()
        manager.execute(ExecutionParameters(.leftHalf, windowElement: other, requestID: newerID))
        wait(for: [earlierFinished], timeout: 2)

        assertFrame(incoming, CGRect(x: 1800, y: 0, width: 600, height: 900))
        assertHistory(incoming, action: .rightHalf, count: 1)
        assertUntouched(other)
        assertHistory(other, action: .leftHalf, count: 1)
        XCTAssertEqual(events.settlements, [newerID, earlierID])
    }

    func testSynchronousConditionInvalidationPreventsStartingTheAnimation() throws {
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        try XCTSkipUnless(WindowAnimator.enabled, "Animations are unavailable on this machine")
        let origin = CGRect(x: 100, y: 100, width: 400, height: 300)
        let incoming = window(focusedId, origin)
        let manager = makeManager(windows: [incoming])
        let condition = TestPlacementCondition()
        condition.invalidateWhenMonitoring = true
        manager.delegate = { StubDelegate($0, condition: condition) }
        let animation = HeldAnimation()
        manager.heldAnimation = animation
        var drainCompletion: (() -> Void)?
        manager.drainWrites = { _, completion in drainCompletion = completion }
        var cancellations = 0
        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, source: .dragToSnap,
                                            cancellation: { cancellations += 1 }))
        XCTAssertNil(animation.cancellation)
        XCTAssertNil(animation.completion)
        XCTAssertNotNil(drainCompletion)
        XCTAssertEqual(incoming.writeCount, 0)
        try XCTUnwrap(drainCompletion)()
        drainMainQueue()

        assertFrame(incoming, origin)
        XCTAssertEqual(incoming.writeCount, 0)
        XCTAssertEqual(cancellations, 1)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "Deferred cancellation arbitration finished")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    private func assertFitRollback(refused: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let anchor = window(neighborId, CGRect(x: 0, y: 0, width: 720, height: 900))
        let origin = CGRect(x: 150, y: 0, width: 350, height: 900)
        let target = CGRect(x: 720, y: 0, width: 480, height: 900)
        var anchorIsCurrent = true
        let incoming = window(focusedId, origin) { requested in
            if requested == target { anchorIsCurrent = false }
            return refused && requested == origin ? target : requested
        }
        // A prior external move made the stored action stale. Planning could replace
        // both entries, so verifying these distinct values exercises history rollback.
        let previousActionFrame = CGRect(x: 50, y: 60, width: 500, height: 350)
        let previousRestore = CGRect(x: 20, y: 80, width: 400, height: 300)
        AppDelegate.windowHistory.lastRectangleActions[focusedId] = RectangleAction(action: .centerHalf,
                                                                                     rect: previousActionFrame, count: 3)
        AppDelegate.windowHistory.restoreRects[focusedId] = previousRestore
        let fit = fitProvider(anchor: anchor, validateNeighbor: { _ in anchorIsCurrent }) { _, opportunity in
            .fit(SnappedWindowFit(target: target.screenFlipped, neighbor: opportunity))
        }
        let manager = makeManager(windows: [incoming, anchor], beforeCooperative: [fit])
        let events = PlacementEvents()
        let cancelled = expectation(description: "Fit cancellation finished")
        var cancellations = 0
        var successes = 0

        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, completion: { successes += 1 },
                                            cancellation: { cancellations += 1; cancelled.fulfill() }))
        wait(for: [cancelled], timeout: 2)

        XCTAssertEqual(incoming.requestedFrames.first, target, file: file, line: line)
        XCTAssertEqual(incoming.requestedFrames.last, origin, file: file, line: line)
        if refused {
            assertFrame(incoming, target, file: file, line: line)
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], origin.screenFlipped, file: file, line: line)
            XCTAssertNil(history(of: incoming), file: file, line: line)
        } else {
            assertFrame(incoming, origin, file: file, line: line)
            XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], previousRestore, file: file, line: line)
            assertHistory(incoming, action: .centerHalf, count: 3, file: file, line: line)
            XCTAssertEqual(history(of: incoming)?.rect, previousActionFrame, file: file, line: line)
        }
        assertUntouched(anchor, file: file, line: line)
        XCTAssertEqual(cancellations, 1, file: file, line: line)
        XCTAssertEqual(successes, 0, file: file, line: line)
        XCTAssertEqual(manager.postProcessCount, 0, file: file, line: line)
        XCTAssertEqual(events.legacyCompletions, 0, file: file, line: line)
        XCTAssertTrue(events.settlements.isEmpty, file: file, line: line)
    }

    func testCommandTakingOverAfterFitApplyOwnsTheFinalFrameHistoryAndSettlement() {
        let anchor = window(neighborId, CGRect(x: 0, y: 0, width: 720, height: 900))
        let target = CGRect(x: 720, y: 0, width: 480, height: 900)
        var anchorIsCurrent = true
        let incoming = window(focusedId, CGRect(x: 150, y: 0, width: 350, height: 900)) { requested in
            if requested == target { anchorIsCurrent = false }
            return requested
        }
        let fit = fitProvider(anchor: anchor, validateNeighbor: { _ in anchorIsCurrent }) { _, opportunity in
            .fit(SnappedWindowFit(target: target.screenFlipped, neighbor: opportunity))
        }
        let manager = makeManager(windows: [incoming, anchor], beforeCooperative: [fit])
        let events = PlacementEvents()
        let newerID = UUID()
        var newerRestore: CGRect?
        let newerCompleted = expectation(description: "Maximize finished")
        let oldFinished = expectation(description: "Superseded Fit finished")
        manager.afterNextApply = {
            XCTAssertEqual(incoming.frame, target.screenFlipped)
            manager.execute(ExecutionParameters(.maximize, windowElement: incoming, completion: {
                newerRestore = AppDelegate.windowHistory.restoreRects[self.focusedId]
                newerCompleted.fulfill()
            }, requestID: newerID))
        }

        manager.execute(ExecutionParameters(.rightHalf, windowElement: incoming, completion: { oldFinished.fulfill() },
                                            cancellation: { oldFinished.fulfill() }))
        wait(for: [newerCompleted, oldFinished], timeout: 2)

        assertFrame(incoming, screen.frame)
        assertHistory(incoming, action: .maximize, count: 1)
        XCTAssertEqual(history(of: incoming)?.rect, incoming.frame)
        XCTAssertNotNil(newerRestore)
        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], newerRestore)
        assertUntouched(anchor)
        XCTAssertEqual(events.legacyCompletions, 1)
        XCTAssertEqual(events.settlements, [newerID])
    }

    // MARK: - Completion

    func testCompletionFiresOnceWhenWindowIsRejected() {
        let sheet = window(focusedId, CGRect(x: 0, y: 0, width: 400, height: 400))
        sheet.sheet = true
        var completions = 0

        execute(.leftHalf, on: sheet, among: [sheet]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(writes, [])
    }

    func testCompletionFiresOnceWhenRestoring() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        AppDelegate.windowHistory.restoreRects[focusedId] = CGRect(x: 40, y: 50, width: 300, height: 200)
        seedHistory(focused, action: .leftHalf)
        var completions = 0

        execute(.restore, on: focused, among: [focused]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(focused.frame, CGRect(x: 40, y: 50, width: 300, height: 200))
        XCTAssertNil(history(of: focused))
    }

    func testPendingRestoreStillRunsAfterAnUnrelatedAcceptedMove() {
        Defaults.cooperativeCornerResize.enabled = false
        let a = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let c = window(stackedId, CGRect(x: 100, y: 100, width: 400, height: 400))
        let restored = CGRect(x: 40, y: 50, width: 300, height: 200)
        AppDelegate.windowHistory.restoreRects[focusedId] = restored
        seedHistory(a, action: .leftHalf)
        let fence = WindowWriteFence()
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen),
                                        windows: [a, c], writeFence: fence)
        let release = DispatchSemaphore(value: 0)
        let external = fence.claim([.init(element: a, windowID: focusedId)])
        fence.perform(external, work: { release.wait(timeout: .now() + 3) }) { result in
            XCTAssertEqual(result, .success)
        }
        let finished = expectation(description: "Accepted Restore on A completed")
        manager.execute(ExecutionParameters(.restore, windowElement: a, completion: { finished.fulfill() }))
        XCTAssertEqual(a.writeCount, 0)

        manager.execute(ExecutionParameters(.rightHalf, windowElement: c))
        assertFrame(c, CGRect(x: 600, y: 0, width: 600, height: 900))
        XCTAssertEqual(a.writeCount, 0)

        release.signal()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(a.frame, restored)
        XCTAssertNil(history(of: a))
    }

    func testRestoreWithoutTargetSupersedesDrainedExternalWriteBeforeItsCompletion() {
        Defaults.cooperativeCornerResize.enabled = false
        let subject = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        seedHistory(subject, action: .leftHalf)
        XCTAssertNil(AppDelegate.windowHistory.restoreRects[focusedId])
        let fence = WindowWriteFence()
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen),
                                        windows: [subject], writeFence: fence)
        let release = DispatchSemaphore(value: 0)
        let external = fence.claim([.init(element: subject, windowID: focusedId)])
        let writerFinished = expectation(description: "External write returned")
        var restoreCompletions = 0
        fence.perform(external, work: { release.wait(timeout: .now() + 3) }) { outcome in
            XCTAssertEqual(outcome, .success)
            XCTAssertEqual(restoreCompletions, 1)
            XCTAssertFalse(external.isCurrent)
            if external.isCurrent {
                AppDelegate.windowHistory.lastRectangleActions[self.focusedId] = RectangleAction(
                    action: .rightHalf, rect: subject.frame)
                AppDelegate.windowHistory.restoreRects[self.focusedId] = subject.frame
            }
            fence.finish(external)
            writerFinished.fulfill()
        }

        manager.execute(ExecutionParameters(.restore, windowElement: subject,
                                            completion: { restoreCompletions += 1 }))
        XCTAssertEqual(restoreCompletions, 0)
        XCTAssertTrue(external.isCurrent)
        release.signal()
        wait(for: [writerFinished], timeout: 5)
        XCTAssertEqual(restoreCompletions, 1)
        XCTAssertNil(history(of: subject))
        XCTAssertNil(AppDelegate.windowHistory.restoreRects[focusedId])
        XCTAssertEqual(subject.writeCount, 0)
    }

    func testResumedRestoreDoesNotSupersedeAnUnrelatedPendingDisplayRetry() {
        Defaults.cooperativeCornerResize.enabled = false
        let a = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        let c = clampingWindow(id: stackedId)
        let restored = CGRect(x: 40, y: 50, width: 300, height: 200)
        AppDelegate.windowHistory.restoreRects[focusedId] = restored
        let fence = WindowWriteFence()
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen),
                                        windows: [a, c], writeFence: fence)
        let release = DispatchSemaphore(value: 0)
        let external = fence.claim([.init(element: a, windowID: focusedId)])
        fence.perform(external, work: { release.wait(timeout: .now() + 3) }) {
            XCTAssertEqual($0, .success)
        }

        let restoreFinished = expectation(description: "Older restore on A ran")
        manager.execute(ExecutionParameters(.restore, windowElement: a, completion: { restoreFinished.fulfill() }))
        let retryFinished = expectation(description: "Newer retry on C settled")
        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: c,
                                            completion: { retryFinished.fulfill() }))
        XCTAssertEqual(manager.postProcessCount, 0)

        // The older writer can retire before the queue hands the window to A.
        fence.finish(external)
        release.signal()
        wait(for: [restoreFinished, retryFinished], timeout: 5, enforceOrder: true)
        XCTAssertEqual(a.frame, restored)
        XCTAssertEqual(c.frame.size, CGSize(width: 600, height: 900))
        XCTAssertEqual(manager.postProcessCount, 1)
    }

    func testNewestDeferredNoOpDiscardsAnOlderMoveOnTheSameWindow() {
        Defaults.cooperativeCornerResize.enabled = false
        let original = CGRect(x: 0, y: 0, width: 600, height: 900)
        let window = window(focusedId, original)
        let fence = WindowWriteFence()
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen),
                                        windows: [window], writeFence: fence)
        let release = DispatchSemaphore(value: 0)
        let external = fence.claim([.init(element: window, windowID: focusedId)])
        fence.perform(external, work: { release.wait(timeout: .now() + 3) }) {
            XCTAssertEqual($0, .success)
        }
        fence.finish(external)

        let older = expectation(description: "Superseded right-half command completed")
        let newer = expectation(description: "Left-half no-op completed")
        manager.execute(ExecutionParameters(.rightHalf, windowElement: window, completion: { older.fulfill() }))
        manager.execute(ExecutionParameters(.leftHalf, windowElement: window, completion: { newer.fulfill() }))

        release.signal()
        wait(for: [older, newer], timeout: 5)
        assertFrame(window, original)
        XCTAssertEqual(window.writeCount, 0)
        assertHistory(window, action: .leftHalf, count: 1)
    }

    func testDeferredPlanReadsTheDrainedFrameBeforeSavingHistoryOrReportingSuccess() {
        Defaults.cooperativeCornerResize.enabled = false
        let original = CGRect(x: 100, y: 100, width: 400, height: 400)
        let externalResult = CGRect(x: 160, y: 110, width: 420, height: 370)
        let subject = window(focusedId, original)
        let fence = WindowWriteFence()
        let manager = TestWindowManager(screenDetection: TestScreenDetection(source: screen),
                                        windows: [subject], writeFence: fence)
        let release = DispatchSemaphore(value: 0)
        let external = fence.claim([.init(element: subject, windowID: focusedId)])
        fence.perform(external, work: {
            guard release.wait(timeout: .now() + 3) == .success else { return false }
            subject.setFrame(externalResult.screenFlipped)
            subject.refusesWrites = true
            return true
        }) { XCTAssertTrue($0) }

        let finished = expectation(description: "Refused placement completed")
        let command = ExecutionParameters(.leftHalf, windowElement: subject,
                                          completion: { finished.fulfill() })
        let observer = Notification.Name.windowPlacementSettled.onPost { note in
            if (note.object as? WindowPlacementSettlement)?.requestID == command.requestID {
                XCTFail("A refused write must not publish the other operation's frame")
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        manager.execute(command)
        XCTAssertNil(AppDelegate.windowHistory.restoreRects[focusedId])

        release.signal()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[focusedId], externalResult.screenFlipped)
        assertFrame(subject, externalResult)
    }

    func testCompletionFiresOnceWhenThereIsNothingToRestore() {
        let focused = window(focusedId, CGRect(x: 0, y: 0, width: 600, height: 900))
        var completions = 0

        execute(.restore, on: focused, among: [focused]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(writes, [])
    }

    func testCompletionFiresOnceWhenRestoringWindowWithoutAnId() {
        let focused = window(nil, CGRect(x: 0, y: 0, width: 600, height: 900))
        var completions = 0

        execute(.restore, on: focused, among: [focused]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(writes, [])
    }

    func testCompletionWaitsForCrossDisplayRetryAndFiresOnce() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = clampingWindow()
        let manager = makeManager(windows: [focused])
        let finished = expectation(description: "Retry completed")
        var completions = 0

        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: focused,
                                            completion: { completions += 1; finished.fulfill() }))

        XCTAssertEqual(completions, 0)
        XCTAssertEqual(manager.postProcessCount, 0)

        wait(for: [finished], timeout: 1)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(manager.postProcessCount, 1)
        XCTAssertEqual(focused.frame.size, CGSize(width: 600, height: 900))
    }

    func testAbandonedDisplayRetryReleasesItsWindowAndCompletesOnce() {
        Defaults.cooperativeCornerResize.enabled = false
        let fence = WindowWriteFence()
        let finished = expectation(description: "Abandoned retry completed")
        weak var retainedWindow: FakeWindow?
        weak var retainedManager: TestWindowManager?
        var completions = 0

        autoreleasepool {
            let focused = clampingWindow()
            retainedWindow = focused
            var manager: TestWindowManager? = TestWindowManager(screenDetection: TestScreenDetection(source: screen),
                                                                windows: [focused], writeFence: fence)
            retainedManager = manager
            manager?.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: focused,
                                                 completion: { completions += 1; finished.fulfill() }))
            XCTAssertEqual(completions, 0)
            manager = nil
            XCTAssertNil(retainedManager)
        }

        wait(for: [finished], timeout: 1)
        drainMainQueue()
        XCTAssertEqual(completions, 1)
        XCTAssertNil(retainedWindow)
        withExtendedLifetime(fence) {}
    }

    func testSupersededRetryStillCompletesOnceWithoutPlacing() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = clampingWindow()
        let manager = makeManager(windows: [focused])
        let firstFinished = expectation(description: "Superseded execution completed")
        var firstCompletions = 0
        var secondCompletions = 0

        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: focused,
                                            completion: { firstCompletions += 1; firstFinished.fulfill() }))
        XCTAssertEqual(firstCompletions, 0)

        // An accepted move on the same display takes over before the retry fires.
        focused.stopClamping()
        manager.execute(ExecutionParameters(.maximize, screen: secondScreen, windowElement: focused,
                                            completion: { secondCompletions += 1 }))
        XCTAssertEqual(secondCompletions, 1)
        let settled = focused.frame
        XCTAssertEqual(manager.postProcessCount, 1)

        wait(for: [firstFinished], timeout: 1)
        XCTAssertEqual(firstCompletions, 1)
        XCTAssertEqual(secondCompletions, 1)
        XCTAssertEqual(manager.postProcessCount, 1)
        XCTAssertEqual(focused.frame, settled)
    }

    func testRejectedRequestDoesNotSupersedePendingRetry() {
        Defaults.cooperativeCornerResize.enabled = false
        let focused = clampingWindow()
        let manager = makeManager(windows: [focused])
        let finished = expectation(description: "Retry completed")

        manager.execute(ExecutionParameters(.rightHalf, screen: secondScreen, windowElement: focused,
                                            completion: { finished.fulfill() }))

        let sheet = window(stackedId, CGRect(x: 0, y: 0, width: 400, height: 400))
        sheet.sheet = true
        manager.execute(ExecutionParameters(.leftHalf, windowElement: sheet))

        wait(for: [finished], timeout: 1)
        XCTAssertEqual(manager.postProcessCount, 1)
        XCTAssertEqual(focused.frame.size, CGSize(width: 600, height: 900))
    }

    // MARK: - Helpers

    private func window(_ id: CGWindowID?, _ frame: CGRect,
                        accepted: @escaping (CGRect) -> CGRect = { $0 }) -> FakeWindow {
        FakeWindow(id: id, normalizedFrame: frame, accepted: accepted) { [weak self] in
            if let id { self?.writes.append(id) }
        }
    }

    /// Clamps the width of a window landing at half the second display twice, like macOS can across displays.
    private func clampingWindow(id: CGWindowID? = nil) -> FakeWindow {
        var attempts = 0
        var clamping = true
        let window = FakeWindow(id: id ?? focusedId, normalizedFrame: CGRect(x: 100, y: 100, width: 800, height: 500)) { requested in
            guard clamping, requested.size == CGSize(width: 600, height: 900) else { return requested }
            attempts += 1
            guard attempts <= 2 else { return requested }
            var accepted = requested
            accepted.size.width -= 200
            return accepted
        } onWrite: {}
        window.onStopClamping = { clamping = false }
        return window
    }

    private func fitProvider(anchor: FakeWindow, on anchorScreen: NSScreen? = nil, enabled: @escaping () -> Bool = { true },
                             notifications: NotificationCenter = NotificationCenter(),
                             validateNeighbor: @escaping (SnappedWindowFit) -> Bool = { _ in true },
                             resolve: @escaping (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution) -> SnappedWindowFitProvider {
        let session = SnappedWindowFitSession(observeWorkspace: false, verify: { _, _ in true })
        session.record(SnappedWindowFitOpportunity(id: neighborId, pid: 500, launch: 1, action: .leftHalf,
                                                   frame: anchor.frame, bounds: (anchorScreen ?? screen).frame.screenFlipped,
                                                   createdAt: ProcessInfo.processInfo.systemUptime))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in session.current != nil }, object: nil)
        wait(for: [ready], timeout: 2)
        return SnappedWindowFitProvider(enabled: enabled, session: { session }, resolve: resolve,
                                        validateNeighbor: validateNeighbor, notifications: notifications)
    }

    private func makeManager(windows: [AccessibilityElement], beforeCooperative: [WindowManagerDelegateProvider] = []) -> TestWindowManager {
        TestWindowManager(screenDetection: TestScreenDetection(source: screen), windows: windows,
                          beforeCooperative: beforeCooperative)
    }

    private func execute(_ action: WindowAction, on focused: FakeWindow, among windows: [AccessibilityElement],
                         source: ExecutionSource = .keyboardShortcut, screen: NSScreen? = nil,
                         completion: (() -> Void)? = nil) {
        makeManager(windows: windows).execute(ExecutionParameters(action, screen: screen, windowElement: focused,
                                                                  source: source, completion: completion))
    }

    private func seedHistory(_ window: FakeWindow, action: WindowAction, count: Int = 1) {
        guard let id = window.getWindowId() else { return }
        AppDelegate.windowHistory.lastRectangleActions[id] = RectangleAction(action: action, rect: window.frame, count: count)
    }

    private func history(of window: FakeWindow) -> RectangleAction? {
        window.getWindowId().flatMap { AppDelegate.windowHistory.lastRectangleActions[$0] }
    }

    private func assertFrame(_ window: FakeWindow, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(window.frame.screenFlipped, expected, file: file, line: line)
    }

    private func assertUntouched(_ window: FakeWindow, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(window.writeCount, 0, file: file, line: line)
    }

    private func assertHistory(_ window: FakeWindow, action: WindowAction, count: Int,
                               file: StaticString = #filePath, line: UInt = #line) {
        let recorded = history(of: window)
        XCTAssertEqual(recorded?.action, action, file: file, line: line)
        XCTAssertEqual(recorded?.count, count, file: file, line: line)
    }

    private func assertWritten(_ first: CGWindowID, before second: CGWindowID,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let firstIndex = writes.firstIndex(of: first), let secondIndex = writes.firstIndex(of: second) else {
            XCTFail("Expected writes to both windows, got \(writes)", file: file, line: line)
            return
        }
        XCTAssertLessThan(firstIndex, secondIndex, "Write order was \(writes)", file: file, line: line)
    }

    // MARK: - Test doubles

    private final class PlacementEvents {
        var legacyCompletions = 0
        var settlements: [UUID] = []
        private var observers: [NSObjectProtocol] = []

        init() {
            observers.append(Notification.Name.windowActionCompleted.onPost { [weak self] _ in self?.legacyCompletions += 1 })
            observers.append(Notification.Name.windowPlacementSettled.onPost { [weak self] note in
                if let placement = note.object as? WindowPlacementSettlement { self?.settlements.append(placement.requestID) }
            })
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    private final class FakeWindow: AccessibilityElement {
        private let id: CGWindowID?
        private var currentFrame: CGRect
        private let accepted: (CGRect) -> CGRect
        private let onWrite: () -> Void
        private(set) var writeCount = 0
        private(set) var requestedFrames: [CGRect] = []
        var reportedMinimumSize: CGSize?
        var sheet = false
        var refusesWrites = false
        var onStopClamping: (() -> Void)?

        init(id: CGWindowID?, normalizedFrame: CGRect, accepted: @escaping (CGRect) -> CGRect = { $0 },
             onWrite: @escaping () -> Void) {
            self.id = id
            currentFrame = normalizedFrame.screenFlipped
            self.accepted = accepted
            self.onWrite = onWrite
            super.init(AXUIElementCreateApplication(pid_t(20_000 + Int(id ?? 0) % 10_000)))
        }

        func stopClamping() { onStopClamping?() }

        override var frame: CGRect { currentFrame }
        private(set) var minimumSizeReads = 0
        override var minimumSize: CGSize? {
            minimumSizeReads += 1
            return reportedMinimumSize
        }
        override var isWindow: Bool? { true }
        override var isSheet: Bool? { sheet }
        override var isMinimized: Bool? { false }
        override var isFullScreen: Bool? { false }
        override var isHidden: Bool? { false }
        override var isSystemDialog: Bool? { false }
        override func getWindowId() -> CGWindowID? { id }
        override func isResizable() -> Bool { true }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: ImmediateWindowPlacement? = nil) {
            setFrame(target, adjustSizeFirst: sizeFirst)
        }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            writeCount += 1
            onWrite()
            // Windows are clamped in screen coordinates, with their top left held in place.
            let requested = frame.screenFlipped
            requestedFrames.append(requested)
            guard !refusesWrites else { return }
            var result = accepted(requested)
            result.origin.y = requested.maxY - result.height
            currentFrame = result.screenFlipped
        }
    }

    /// Revises nothing unless told to, places the window through the manager's movers, and counts its hooks.
    private final class TestPlacementCondition: WindowPlacementCondition {
        var invalidation: WindowPlacementInvalidation?
        var pendingCancellation: ((WindowPlacementInvalidation) -> Void)?
        private(set) var stopCount = 0
        var invalidateWhenMonitoring = false

        func isValid() -> Bool { invalidation == nil }

        func whilePending(cancel: @escaping (WindowPlacementInvalidation) -> Void) {
            pendingCancellation = cancel
            if invalidateWhenMonitoring {
                invalidation = .anchorChanged
                cancel(.anchorChanged)
            }
        }

        func stopMonitoring() {
            stopCount += 1
            pendingCancellation = nil
        }
    }

    private final class HeldAnimation {
        var cancellation: (() -> Void)?
        var completion: ((CGRect?) -> Void)?
    }

    private final class StubDelegate: WindowManagerDelegate {
        var calcResult: WindowCalculationResult
        var achieved: Bool?
        var placementCondition: WindowPlacementCondition?
        private(set) var placeCount = 0
        private(set) var settledCount = 0

        init(_ request: WindowMoveRequest, condition: WindowPlacementCondition? = nil) {
            calcResult = request.calcResult
            placementCondition = condition
        }

        func isAlreadyAchieved() -> Bool? { achieved }

        func place(result: ResultParameters, moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect? {
            placeCount += 1
            moveWindow(result.calcResult.rect, result)
            return result.windowElement.frame
        }

        func moveDidSettle(resultingRect: CGRect, screenFrame: CGRect) { settledCount += 1 }
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
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    private final class TestScreenDetection: ScreenDetection {
        let source: NSScreen

        init(source: NSScreen) { self.source = source }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            UsableScreens(currentScreen: source, numScreens: 1)
        }
    }

    private final class TestWindowManager: WindowManager {
        private(set) var postProcessCount = 0
        private(set) var lastIncrementCount: Bool?
        private(set) var lastResult: ResultParameters?
        var afterNextApply: (() -> Void)?
        private let animationDriver = AnimationDriver()
        var heldAnimation: HeldAnimation? {
            get { animationDriver.held }
            set { animationDriver.held = newValue }
        }

        var drainWrites: (([AccessibilityElement], @escaping () -> Void) -> Void)? {
            get { animationDriver.drainWrites }
            set { animationDriver.drainWrites = newValue }
        }

        private final class AnimationDriver {
            var held: HeldAnimation?
            var drainWrites: (([AccessibilityElement], @escaping () -> Void) -> Void)?
        }
        /// Replaces the built-in delegate when set.
        var delegate: ((WindowMoveRequest) -> WindowManagerDelegate?)?

        init(screenDetection: ScreenDetection, windows: [AccessibilityElement],
             beforeCooperative: [WindowManagerDelegateProvider] = [], writeFence: WindowWriteFence = .shared) {
            let cooperative = CooperativeResizeDelegateProvider(windowHistory: AppDelegate.windowHistory, windowElements: { windows })
            let driver = animationDriver
            var services = WindowPlacementServices(animator: .shared)
            let drain = services.drainWrites
            services.drainWrites = { windows, completion in
                if let override = driver.drainWrites {
                    override(windows, completion)
                } else {
                    drain(windows, completion)
                }
            }
            let animate = services.animate
            services.animate = { window, animation, cancellation, completion in
                guard let held = driver.held else {
                    return animate(window, animation, cancellation, completion)
                }
                XCTAssertNotNil(animation)
                held.cancellation = cancellation
                held.completion = completion
            }
            services.confirmsRollback = { window, id, frame in
                window.getWindowId() == id && WindowGeometry.near(window.frame, frame)
            }
            super.init(screenDetection: screenDetection, delegateProviders: beforeCooperative + [cooperative],
                       placementServices: services, writeFence: writeFence)
        }

        override func moveDelegate(for request: WindowMoveRequest) -> WindowManagerDelegate? {
            if let delegate { return delegate(request) }
            return super.moveDelegate(for: request)
        }

        override func apply(result: ResultParameters, whileOwned: (() -> Bool)? = nil) -> CGRect {
            let frame = super.apply(result: result, whileOwned: whileOwned)
            let afterApply = afterNextApply
            afterNextApply = nil
            afterApply?()
            return frame
        }

        override func windowMovedAcrossDisplays(windowElement: AccessibilityElement, windowId: CGWindowID?,
                                                resultingRect: CGRect, destination: NSScreen, preservesFocus: Bool) {}

        override func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
            postProcessCount += 1
            lastIncrementCount = incrementCount
            lastResult = result
            super.postProcess(result: result, resultingRect: resultingRect, incrementCount: incrementCount)
        }
    }
}
