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
        XCTAssertTrue(keys.contains("cooperativeCornerResize"), "cooperativeCornerResize missing from Defaults.array")
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

    func testDisabledExperimentalPreferenceLeavesCornerCalculationUnchanged() {
        let savedValue = Defaults.cooperativeCornerResize.enabled
        let savedAxis = Defaults.cornerCycleExpansionAxis.value
        let savedHorizontalSplitRatio = Defaults.horizontalSplitRatio.value
        let savedVerticalSplitRatio = Defaults.verticalSplitRatio.value
        defer {
            Defaults.cooperativeCornerResize.enabled = savedValue
            Defaults.cornerCycleExpansionAxis.value = savedAxis
            Defaults.horizontalSplitRatio.value = savedHorizontalSplitRatio
            Defaults.verticalSplitRatio.value = savedVerticalSplitRatio
        }

        Defaults.cooperativeCornerResize.enabled = false
        Defaults.cornerCycleExpansionAxis.value = .vertical
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = 50

        let visibleFrame = CGRect(x: 10, y: 20, width: 1200, height: 900)
        let firstRect = WindowCalculationFactory.lowerLeftCalculation.calculateRect(RectCalculationParameters(window: Window(id: 1, rect: visibleFrame),
                                                                                                             visibleFrameOfScreen: visibleFrame,
                                                                                                             action: .bottomLeft,
                                                                                                             lastAction: nil)).rect
        let repeatedRect = WindowCalculationFactory.lowerLeftCalculation.calculateRect(RectCalculationParameters(window: Window(id: 1, rect: firstRect),
                                                                                                                visibleFrameOfScreen: visibleFrame,
                                                                                                                action: .bottomLeft,
                                                                                                                lastAction: RectangleAction(action: .bottomLeft,
                                                                                                                                            subAction: nil,
                                                                                                                                            rect: firstRect,
                                                                                                                                            count: 1))).rect

        assertRect(repeatedRect, equals: CGRect(x: 10, y: 20, width: 600, height: 600))
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

class HalfSplitCornerCalculationTests: XCTestCase {
    
    private var savedHorizontalSplitRatio: Float = 50
    private var savedVerticalSplitRatio: Float = 50
    private var savedSubsequentExecutionMode: SubsequentExecutionMode = .resize
    private var savedCornerCycleExpansionAxis: CornerCycleExpansionAxis = .horizontal
    private var savedCycleSizesIsChanged = false
    private var savedSelectedCycleSizes = Set<CycleSize>()
    private let visibleFrame = CGRect(x: 10, y: 20, width: 1200, height: 900)
    
    override func setUp() {
        super.setUp()
        savedHorizontalSplitRatio = Defaults.horizontalSplitRatio.value
        savedVerticalSplitRatio = Defaults.verticalSplitRatio.value
        savedSubsequentExecutionMode = Defaults.subsequentExecutionMode.value
        savedCornerCycleExpansionAxis = Defaults.cornerCycleExpansionAxis.value
        savedCycleSizesIsChanged = Defaults.cycleSizesIsChanged.enabled
        savedSelectedCycleSizes = Defaults.selectedCycleSizes.value
        Defaults.subsequentExecutionMode.value = .resize
        Defaults.cycleSizesIsChanged.enabled = false
    }
    
    override func tearDown() {
        Defaults.horizontalSplitRatio.value = savedHorizontalSplitRatio
        Defaults.verticalSplitRatio.value = savedVerticalSplitRatio
        Defaults.subsequentExecutionMode.value = savedSubsequentExecutionMode
        Defaults.cornerCycleExpansionAxis.value = savedCornerCycleExpansionAxis
        Defaults.cycleSizesIsChanged.enabled = savedCycleSizesIsChanged
        Defaults.selectedCycleSizes.value = savedSelectedCycleSizes
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
        setSplitRatio(CycleSize.twoThirds.percentValue)
        Defaults.cornerCycleExpansionAxis.value = .vertical

        let firstFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(params(for: .topRight)).rect
        let secondFrame = WindowCalculationFactory.upperRightCalculation.calculateRect(repeatedParams(for: .topRight, currentRect: firstFrame, count: 1)).rect

        XCTAssertFalse(firstFrame.equalTo(secondFrame))
        XCTAssertEqual(firstFrame.maxY, secondFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(firstFrame.origin.x, secondFrame.origin.x, accuracy: 0.001)
        XCTAssertEqual(firstFrame.width, secondFrame.width, accuracy: 0.001)
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
        setSplitRatio(CycleSize.twoThirds.percentValue)

        let leftFrame = WindowCalculationFactory.leftHalfCalculation.calculateRect(params(for: .leftHalf)).rect
        let repeatedLeftFrame = WindowCalculationFactory.leftHalfCalculation.calculateRepeatedRect(repeatedParams(for: .leftHalf, currentRect: leftFrame)).rect

        assertRect(leftFrame, equals: CGRect(x: 10, y: 20, width: 800, height: 900))
        assertRect(repeatedLeftFrame, equals: CGRect(x: 10, y: 20, width: 400, height: 900))
    }

    func testRepeatedTopShortcutAdvancesWhenCurrentFrameMatchesSplitRatioCycleSize() {
        setSplitRatio(CycleSize.twoThirds.percentValue)

        let topFrame = WindowCalculationFactory.topHalfCalculation.calculateRect(params(for: .topHalf)).rect
        let repeatedTopFrame = WindowCalculationFactory.topHalfCalculation.calculateRepeatedRect(repeatedParams(for: .topHalf, currentRect: topFrame)).rect

        assertRect(topFrame, equals: CGRect(x: 10, y: 320, width: 1200, height: 600))
        assertRect(repeatedTopFrame, equals: CGRect(x: 10, y: 620, width: 1200, height: 300))
    }

    func testHorizontalCornerShortcutCanCycleAfterCompatibleSideShortcut() {
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
