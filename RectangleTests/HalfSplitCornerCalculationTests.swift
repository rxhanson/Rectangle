/// HalfSplitCornerCalculationTests.swift

import XCTest
@testable import Rectangle

class HalfSplitCornerCalculationTests: XCTestCase {
    
    private var savedHorizontalSplitRatio: Float = 50
    private var savedVerticalSplitRatio: Float = 50
    private var savedSubsequentExecutionMode: SubsequentExecutionMode = .resize
    private var savedCornerCycleExpansionMode: CornerCycleExpansionMode = .horizontal
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
        savedCornerCycleExpansionMode = Defaults.cornerCycleExpansionAxis.value
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
        Defaults.cornerCycleExpansionAxis.value = savedCornerCycleExpansionMode
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

    func testRepeatedCornersUseDisplayOrientationForExpansionAxis() {
        setSplitRatio(60)
        Defaults.cornerCycleExpansionAxis.value = .displayOrientation

        let landscapeBase = WindowCalculationFactory.upperLeftCalculation.calculateRect(params(for: .topLeft)).rect
        let landscapeRepeated = WindowCalculationFactory.upperLeftCalculation.calculateRect(
            repeatedParams(for: .topLeft, currentRect: landscapeBase)
        ).rect
        assertRect(landscapeRepeated, equals: CGRect(x: 10, y: 380, width: 800, height: 540))

        let portraitFrame = CGRect(x: 10, y: 20, width: 900, height: 1200)
        let portraitBase = WindowCalculationFactory.upperLeftCalculation.calculateRect(
            params(for: .topLeft, screenFrame: portraitFrame)
        ).rect
        let portraitRepeated = WindowCalculationFactory.upperLeftCalculation.calculateRect(
            repeatedParams(for: .topLeft, currentRect: portraitBase, screenFrame: portraitFrame)
        ).rect
        assertRect(portraitRepeated, equals: CGRect(x: 10, y: 420, width: 540, height: 800))
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
        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .bottomLeft,
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
        let sourceFrame = CooperativeResizeCoordinator(windowHistory: WindowHistory()).observedCooperativeSourceFrame(action: .leftHalf,
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
        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .leftHalf,
                                                                             observedFrame: expandedLeft,
                                                                             screenFrame: visibleFrame,
                                                                             axis: .horizontal,
                                                                             movedEdge: .right,
                                                                             tolerance: 8,
                                                                             includeCycleTargets: false)

        assertRect(cleanupTarget ?? .null, equals: CGRect(x: 10, y: 20, width: 600, height: 900))
    }

    func testCooperativeHistoryActionMapsAdjacentSideAndCornerActions() {
        let manager = CooperativeResizeCoordinator(windowHistory: WindowHistory())

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
        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .topLeft,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .topRight,
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

        let manager = CooperativeResizeCoordinator(windowHistory: WindowHistory())
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

        let manager = CooperativeResizeCoordinator(windowHistory: WindowHistory())
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

        let sourceFrame = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupSourceFrame(action: .topRight,
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

        let manager = CooperativeResizeCoordinator(windowHistory: WindowHistory())
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .bottomRight,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .bottomLeft,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .bottomLeft,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .topRight,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .bottomLeft,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .bottomRight,
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

        let lookAheadTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cycleLookAheadTargetForMinimumRestrictedAdjacent(action: .bottomLeft,
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

        let lookAheadTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cycleLookAheadTargetForMinimumRestrictedAdjacent(action: .bottomLeft,
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

        let lookAheadTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cycleLookAheadTargetForMinimumRestrictedAdjacent(action: .bottomLeft,
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

        let cleanupTarget = CooperativeResizeCoordinator(windowHistory: WindowHistory()).cleanupTargetFrame(action: .topLeft,
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
        let manager = CooperativeResizeCoordinator(windowHistory: WindowHistory())
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

    func testHorizontalCornerShortcutDoesNotCycleAfterSideShortcut() {
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

        assertRect(topLeftFrame, equals: CGRect(x: 10, y: 470, width: 600, height: 450))
    }

    func testVerticalCornerShortcutDoesNotCycleAfterSideShortcut() {
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

        assertRect(topLeftFrame, equals: CGRect(x: 10, y: 470, width: 600, height: 450))
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
    
    private func params(for action: WindowAction, screenFrame: CGRect? = nil) -> RectCalculationParameters {
        let screenFrame = screenFrame ?? visibleFrame
        return RectCalculationParameters(window: Window(id: 1, rect: screenFrame),
                                  visibleFrameOfScreen: screenFrame,
                                  action: action,
                                  lastAction: nil)
    }

    private func repeatedParams(for action: WindowAction, currentRect: CGRect? = nil,
                                count: Int = 1, screenFrame: CGRect? = nil) -> RectCalculationParameters {
        let screenFrame = screenFrame ?? visibleFrame
        return RectCalculationParameters(window: Window(id: 1, rect: currentRect ?? screenFrame),
                                  visibleFrameOfScreen: screenFrame,
                                  action: action,
                                  lastAction: RectangleAction(action: action,
                                                              subAction: nil,
                                                              rect: currentRect ?? screenFrame,
                                                              count: count))
    }
    
    private func assertRect(_ rect: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}
