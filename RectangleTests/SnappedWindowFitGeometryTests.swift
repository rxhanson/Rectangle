import XCTest
@testable import Rectangle

final class SnappedWindowFitSessionTests: XCTestCase {
    func testReferenceRemainsAvailableUntilTaken() {
        let session = SnappedWindowFitSession(observeWorkspace: false)
        let reference = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            bounds: CGRect(x: 0, y: 0, width: 1000, height: 600))
        session.record(reference)
        XCTAssertEqual(session.current, reference)
        XCTAssertEqual(session.take(), reference)
        XCTAssertNil(session.current)
    }

    func testInvalidatingAnOlderFrameKeepsTheNewerReference() {
        let session = SnappedWindowFitSession(observeWorkspace: false)
        let old = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 400, height: 600), bounds: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let current = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 600, height: 600), bounds: old.bounds)
        session.record(current)
        session.invalidate(old)
        XCTAssertEqual(session.current, current)
    }

    func testNewReferenceReplacesThePreviousOneAndInvalidationIsWindowSpecific() {
        let session = SnappedWindowFitSession(observeWorkspace: false)
        func reference(_ id: CGWindowID) -> SnappedWindowFitOpportunity {
            SnappedWindowFitOpportunity(id: id, pid: 123, launch: 1, action: .leftHalf,
                frame: CGRect(x: 0, y: 0, width: 400, height: 600),
                bounds: CGRect(x: 0, y: 0, width: 1000, height: 600))
        }
        session.record(reference(1))
        session.record(reference(2))
        session.invalidate(windowID: 1)
        XCTAssertEqual(session.current?.id, 2)
        session.invalidate(windowID: 2)
        XCTAssertNil(session.current)
    }
}

final class SnappedWindowFitOcclusionTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 29, width: 840, height: 878)

    private func window(_ id: CGWindowID, _ frame: CGRect, alpha: CGFloat = 1, onScreen: Bool = true) -> WindowInfo {
        WindowInfo(id: id, level: 0, frame: frame, pid: 123, processName: "Fixture", alpha: alpha, isOnScreen: onScreen)
    }

    private func exposed(_ front: [WindowInfo], anchor: WindowInfo? = nil) -> Bool {
        SnappedWindowFit.isExposed(anchor ?? window(1, frame), inFront: front[...], ignoring: 2, ignoredPID: 999)
    }

    func testSmallOverlaysPartialCoverAndIncomingWindowAllowFit() {
        XCTAssertTrue(exposed([window(3, CGRect(x: 6, y: 35, width: 66, height: 20))]))
        XCTAssertTrue(exposed([window(3, CGRect(x: 0, y: 29, width: 420, height: 878))]))
        XCTAssertTrue(exposed([window(2, frame)]))
    }

    func testUnionOfOccludersAndPerimeterExposureBlockFit() {
        XCTAssertFalse(exposed([window(3, frame)]))
        XCTAssertFalse(exposed([window(3, CGRect(x: 0, y: 29, width: 420, height: 878)),
                                window(4, CGRect(x: 420, y: 29, width: 420, height: 878))]))
        XCTAssertFalse(exposed([window(3, frame.insetBy(dx: 1, dy: 1))]))
    }

    func testHiddenAndOffscreenWindowsDoNotOccludeOrBecomeAnchors() {
        for invisible in [window(1, frame, alpha: 0), window(1, frame, onScreen: false)] {
            XCTAssertFalse(exposed([], anchor: invisible))
            XCTAssertTrue(exposed([invisible]))
        }
    }
}

final class SnappedWindowFitGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)

    private func resolve(_ action: WindowAction, anchorFrame: CGRect, gap: CGFloat = 0,
                         target: CGRect? = nil) -> SnappedWindowFit.Resolution {
        let axis = WindowSplitAxis(action: action)!
        let frame = axis.rect(bounds)
        let anchor = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1,
            action: axis == .horizontal ? .leftHalf : .topHalf, frame: axis.rect(anchorFrame), bounds: frame)
        return SnappedWindowFit.resolve(action: action, movingWindowID: 2, target: axis.rect(target
            ?? CGRect(x: 600, y: 0, width: 600, height: 800)), bounds: frame, gap: gap, anchor: anchor)
    }

    func testBothAxesUseTheAchievedEdgeAndAllowPositiveSpaceBelowAppMinimum() {
        for action: WindowAction in [.rightHalf, .bottomHalf] {
            let axis = WindowSplitAxis(action: action)!
            for width: CGFloat in [720, 1_080] {
                let anchor = CGRect(x: 0, y: 0, width: width, height: 800)
                guard case .fit(let fit) = resolve(action, anchorFrame: anchor) else {
                    return XCTFail("A positive remainder must be requested")
                }
                XCTAssertEqual(fit.target, axis.rect(CGRect(x: width, y: 0, width: 1_200 - width, height: 800)))
                XCTAssertEqual(fit.neighbor.frame, axis.rect(anchor))
            }
        }
    }

    func testZeroAndNegativeRemaindersRejectOnBothAxes() {
        for action: WindowAction in [.rightHalf, .bottomHalf] {
            for width: CGFloat in [1_190, 1_195] {
                XCTAssertEqual(resolve(action, anchorFrame: CGRect(x: 0, y: 0, width: width, height: 800), gap: 10), .noRoom)
            }
        }
    }

    func testOffsetOutsideEdgeTolerancePassesThrough() {
        let anchor = CGRect(x: 0, y: 0, width: 720, height: 800)
        XCTAssertEqual(resolve(.rightHalf, anchorFrame: anchor,
                               target: CGRect(x: 595, y: -5, width: 600, height: 800)), .unchanged)
    }

    func testContinuousPreviewMeasuresAccessibilityOncePerTarget() {
        let screen = RepeatedMaximizeTestScreen(frame: bounds)
        let area = SnapArea(screen: screen, directional: .r, action: .rightHalf)
        let preview = SnappedWindowFitPreview(area: area, windowID: 2, screenFrame: bounds)
        var tile = WindowCalculationResult(rect: CGRect(x: 600, y: 0, width: 600, height: 800),
                                           screen: screen, resultingAction: .rightHalf)
        let previousOffset = Defaults.cyclingOverlapOffset.enabled
        let previousSize = Defaults.cyclingOverlapOffsetSize.value
        defer {
            Defaults.cyclingOverlapOffset.enabled = previousOffset
            Defaults.cyclingOverlapOffsetSize.value = previousSize
        }
        Defaults.cyclingOverlapOffset.enabled = true
        Defaults.cyclingOverlapOffsetSize.value = 2
        var measurements = 0
        func measure() -> CGRect? {
            measurements += 1
            return tile.rect.offsetBy(dx: CGFloat(Defaults.cyclingOverlapOffsetSize.value), dy: 0)
        }

        let first = preview.adjustedRect(for: tile, measure: measure)
        for _ in 0..<10 {
            XCTAssertEqual(preview.adjustedRect(for: tile, measure: measure), first)
        }
        XCTAssertEqual(measurements, 1)

        tile.rect = tile.rect.insetBy(dx: 4, dy: 8)
        XCTAssertNotEqual(preview.adjustedRect(for: tile, measure: measure), first)
        Defaults.cyclingOverlapOffsetSize.value = 3
        XCTAssertEqual(preview.adjustedRect(for: tile, measure: measure), tile.rect.offsetBy(dx: 3, dy: 0))
        XCTAssertEqual(measurements, 3)
        XCTAssertTrue(preview.matches(area: area, windowID: 2))
        XCTAssertFalse(preview.matches(area: area, windowID: 3))
        XCTAssertFalse(preview.matches(area: SnapArea(screen: screen, directional: .l, action: .leftHalf), windowID: 2))
    }

    func testSmallOverlapOffsetDoesNotChangeTheUnpaddedFitTile() {
        let oldGap = Defaults.gapSize.value
        let oldSkip = Defaults.skipGapTopEdge.enabled
        defer {
            Defaults.gapSize.value = oldGap
            Defaults.skipGapTopEdge.enabled = oldSkip
        }
        let screen = RepeatedMaximizeTestScreen(frame: bounds)
        let anchor = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 720, height: 800), bounds: bounds)
        let original = CGRect(x: 600, y: 0, width: 600, height: 800)
        let fitted = CGRect(x: 720, y: 0, width: 480, height: 800)
        for gap: Float in [0, 8] {
            for skipTopGap in [false, true] {
                Defaults.gapSize.value = gap
                Defaults.skipGapTopEdge.enabled = skipTopGap
                var result = WindowCalculationResult(rect: original, screen: screen, resultingAction: .rightHalf)
                GapTargetAdjuster().adjust(&result, action: .rightHalf, windowId: 2)
                result.rect = result.rect.offsetBy(dx: 2, dy: 1)
                let achieved = GapCalculation.applyGaps(fitted, sharedEdges: .left, gapSize: gap, skipTopGap: skipTopGap)
                let fit = SnappedWindowFit(target: achieved.screenFlipped, neighbor: anchor)
                XCTAssertEqual(fit.unpaddedTarget(for: result), fitted)
            }
        }
    }

    func testBoundsAndComplementaryActionAreRequired() {
        let anchor = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 720, height: 800), bounds: bounds)
        XCTAssertTrue(anchor.accepts(action: .rightHalf, movingWindowID: 2, bounds: bounds))
        XCTAssertFalse(anchor.accepts(action: .rightHalf, movingWindowID: 1, bounds: bounds))
        XCTAssertFalse(anchor.accepts(action: .rightHalf, movingWindowID: 2, bounds: bounds.offsetBy(dx: 10, dy: 0)))
        XCTAssertFalse(anchor.accepts(action: .leftHalf, movingWindowID: 2, bounds: bounds))
    }

    func testMissingReferenceUsesOrdinaryTarget() {
        let fitEnabled = Defaults.fitBesideSnappedWindows.enabled
        let oldGap = Defaults.gapSize.value
        defer {
            Defaults.fitBesideSnappedWindows.enabled = fitEnabled
            Defaults.gapSize.value = oldGap
        }
        Defaults.fitBesideSnappedWindows.enabled = true
        Defaults.gapSize.value = 0
        let screenFrame = bounds.screenFlipped
        let window = Window(id: 2, rect: CGRect(x: 50, y: 50, width: 360, height: 480))
        let calculation = WindowCalculationFactory.calculationsByAction[.rightHalf]!
        let target = calculation.calculateRect(RectCalculationParameters(window: window, visibleFrameOfScreen: screenFrame,
                                                                          action: .rightHalf, lastAction: nil)).rect
        let anchor = SnappedWindowFitOpportunity(id: 1, pid: 123, launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 720, height: 800), bounds: bounds)
        var sampleCount = 0
        var windows = [WindowInfo]()
        func sample(_ initial: CGRect) -> SnappedWindowFit.Resolution? {
            SnappedWindowFit.resolve(action: .rightHalf, window: window, initialTarget: initial, target: target,
                                            screenFrame: screenFrame, opportunity: anchor,
                                            windowList: { sampleCount += 1; return windows },
                                            processLaunchTime: { _ in 1 })
        }
        XCTAssertEqual(sample(target.insetBy(dx: 20, dy: 0)), .unchanged)
        XCTAssertEqual(sampleCount, 0)
        XCTAssertEqual(sample(target), .unchanged)
        windows.append(WindowInfo(id: 1, level: 0, frame: anchor.frame, pid: anchor.pid, processName: "Fixture"))
        guard case .fit(let fit) = sample(target) else { return XCTFail("A recovered WindowServer sample must be eligible") }
        XCTAssertEqual(fit.target, CGRect(x: 720, y: 0, width: 480, height: 800))
        XCTAssertEqual(sampleCount, 2)
    }
}
