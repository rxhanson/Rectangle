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
            (Defaults.cornerCycleExpansionAxis, CodableDefault(int: CornerCycleExpansionAxis.vertical.rawValue)),
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
    private func clampingWindow() -> FakeWindow {
        var attempts = 0
        var clamping = true
        let window = FakeWindow(id: focusedId, normalizedFrame: CGRect(x: 100, y: 100, width: 800, height: 500)) { requested in
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

    private func makeManager(windows: [AccessibilityElement]) -> TestWindowManager {
        TestWindowManager(screenDetection: TestScreenDetection(source: screen), windows: windows)
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

    private final class FakeWindow: AccessibilityElement {
        private let id: CGWindowID?
        private var currentFrame: CGRect
        private let accepted: (CGRect) -> CGRect
        private let onWrite: () -> Void
        private(set) var writeCount = 0
        private(set) var requestedFrames: [CGRect] = []
        var reportedMinimumSize: CGSize?
        var sheet = false
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
        override var minimumSize: CGSize? { reportedMinimumSize }
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
            var result = accepted(requested)
            result.origin.y = requested.maxY - result.height
            currentFrame = result.screenFlipped
        }
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
        private let windows: [AccessibilityElement]
        private(set) var postProcessCount = 0
        private(set) var lastIncrementCount: Bool?
        private(set) var lastResult: ResultParameters?

        init(screenDetection: ScreenDetection, windows: [AccessibilityElement]) {
            self.windows = windows
            super.init(screenDetection: screenDetection)
        }

        override var cooperativeResize: CooperativeResizeCoordinator? {
            CooperativeResizeCoordinator.ifEnabled(windowHistory: AppDelegate.windowHistory, windowElements: { [windows] in windows })
        }

        override func windowMovedAcrossDisplays(windowElement: AccessibilityElement, resultingRect: CGRect, preservesFocus: Bool) {}

        override func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
            postProcessCount += 1
            lastIncrementCount = incrementCount
            lastResult = result
            super.postProcess(result: result, resultingRect: resultingRect, incrementCount: incrementCount)
        }
    }
}
