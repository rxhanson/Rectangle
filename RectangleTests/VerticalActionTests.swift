/// VerticalActionTests.swift

import MASShortcut
import XCTest
@testable import Rectangle

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

class VerticalSixthActionTests: XCTestCase {

    private let actions: [WindowAction] = [
        .firstVerticalSixth, .secondVerticalSixth, .thirdVerticalSixth,
        .fourthVerticalSixth, .fifthVerticalSixth, .lastVerticalSixth
    ]

    func testVerticalSixthActionsUseAvailableStableIdentifiers() {
        XCTAssertEqual(WindowAction.lastVerticalEighth.rawValue, 140)
        XCTAssertEqual(actions.map(\.rawValue), [141, 142, 143, 144, 145, 146])
        XCTAssertEqual(actions.map(\.name), [
            "firstVerticalSixth", "secondVerticalSixth", "thirdVerticalSixth",
            "fourthVerticalSixth", "fifthVerticalSixth", "lastVerticalSixth"
        ])
    }

    func testVerticalSixthActionsTileVisibleFrameIntoSixFullHeightColumns() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 3840, height: 1000)
        let expected = (0..<6).map { CGRect(x: CGFloat($0 * 640), y: 40, width: 640, height: 1000) }
        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalSixthActionsUseBoundaryRoundingAcrossNonDivisibleLandscapeWidth() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 1003, height: 800)
        let expected = [
            CGRect(x: 20, y: 40, width: 167, height: 800),
            CGRect(x: 187, y: 40, width: 167, height: 800),
            CGRect(x: 354, y: 40, width: 167, height: 800),
            CGRect(x: 521, y: 40, width: 167, height: 800),
            CGRect(x: 688, y: 40, width: 167, height: 800),
            CGRect(x: 855, y: 40, width: 168, height: 800)
        ]

        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalSixthActionsRotateIntoTopToBottomRowsOnPortraitDisplays() {
        let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 1003)
        let expected = [
            CGRect(x: 20, y: 876, width: 800, height: 167),
            CGRect(x: 20, y: 709, width: 800, height: 167),
            CGRect(x: 20, y: 542, width: 800, height: 167),
            CGRect(x: 20, y: 375, width: 800, height: 167),
            CGRect(x: 20, y: 208, width: 800, height: 167),
            CGRect(x: 20, y: 40, width: 800, height: 168)
        ]

        XCTAssertEqual(actions.map { calculate($0, visibleFrame: visibleFrame).rect }, expected)
    }

    func testVerticalSixthRepeatsCycleThroughWholeTopAndBottomHalfOfTheColumn() {
        withVerticalSixthsCyclingTwelfths(true) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 600, height: 400)
            let results = repeatedResults(for: .thirdVerticalSixth, count: 4, visibleFrame: visibleFrame)

            XCTAssertEqual(results.map(\.rect), [
                CGRect(x: 220, y: 40, width: 100, height: 400),
                CGRect(x: 220, y: 240, width: 100, height: 200),
                CGRect(x: 220, y: 40, width: 100, height: 200),
                CGRect(x: 220, y: 40, width: 100, height: 400)
            ])
        }
    }

    func testEveryVerticalSixthActionCyclesWithinItsOwnColumn() {
        withVerticalSixthsCyclingTwelfths(true) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 1003, height: 800)
            let columnMinXs: [CGFloat] = [20, 187, 354, 521, 688, 855]

            for (index, action) in actions.enumerated() {
                let results = repeatedResults(for: action, count: 3, visibleFrame: visibleFrame)
                XCTAssertEqual(results.map { $0.rect.minX }, Array(repeating: columnMinXs[index], count: 3),
                               "\(action) drifted out of its column")
                XCTAssertEqual(results.map { $0.rect.height }, [800, 400, 400],
                               "\(action) did not cycle whole, top half, bottom half")
            }
        }
    }

    func testVerticalSixthRepeatsSplitPortraitRowsLeftAndRight() {
        withVerticalSixthsCyclingTwelfths(true) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 800, height: 1003)
            let results = repeatedResults(for: .secondVerticalSixth, count: 4, visibleFrame: visibleFrame)

            XCTAssertEqual(results.map(\.rect), [
                CGRect(x: 20, y: 709, width: 800, height: 167),
                CGRect(x: 20, y: 709, width: 400, height: 167),
                CGRect(x: 420, y: 709, width: 400, height: 167),
                CGRect(x: 20, y: 709, width: 800, height: 167)
            ])
        }
    }

    func testOddSizedSixthsGiveTheTrailingHalfTheExtraPixel() {
        withVerticalSixthsCyclingTwelfths(true) {
            let visibleFrame = CGRect(x: 0, y: 0, width: 1001, height: 401)
            let results = repeatedResults(for: .firstVerticalSixth, count: 3, visibleFrame: visibleFrame)

            XCTAssertEqual(results.map(\.rect), [
                CGRect(x: 0, y: 0, width: 166, height: 401),
                CGRect(x: 0, y: 201, width: 166, height: 200),
                CGRect(x: 0, y: 0, width: 166, height: 201)
            ])
        }
    }

    func testOddWidthPortraitRowsGiveTheRightHalfTheExtraPixel() {
        withVerticalSixthsCyclingTwelfths(true) {
            let visibleFrame = CGRect(x: 0, y: 0, width: 401, height: 1001)
            let results = repeatedResults(for: .firstVerticalSixth, count: 3, visibleFrame: visibleFrame)

            XCTAssertEqual(results.map(\.rect), [
                CGRect(x: 0, y: 835, width: 401, height: 166),
                CGRect(x: 0, y: 835, width: 200, height: 166),
                CGRect(x: 200, y: 835, width: 201, height: 166)
            ])
        }
    }

    func testHalfPlacementsReportOnlyTheEdgesTheyShareWithNeighbours() {
        let landscape = CGRect(x: 20, y: 40, width: 600, height: 400)
        let portrait = CGRect(x: 20, y: 40, width: 600, height: 803)
        let columnEdges: [Edge] = [.right, [.left, .right], .left]
        let rowEdges: [Edge] = [.bottom, [.top, .bottom], .top]

        withVerticalSixthsCyclingTwelfths(true) {
            for (index, action) in actions.enumerated() {
                let edges = columnEdges[boundaryIndex(of: index)]
                let results = repeatedResults(for: action, count: 3, visibleFrame: landscape)
                XCTAssertEqual(results.map(\.subAction?.gapSharedEdge),
                               [edges, edges.union(.bottom), edges.union(.top)],
                               "\(action) column halves reported the wrong gap edges")

                let edgesAcross = rowEdges[boundaryIndex(of: index)]
                let portraitResults = repeatedResults(for: action, count: 3, visibleFrame: portrait)
                XCTAssertEqual(portraitResults.map(\.subAction?.gapSharedEdge),
                               [edgesAcross, edgesAcross.union(.right), edgesAcross.union(.left)],
                               "\(action) row halves reported the wrong gap edges")
            }
        }
    }

    /// The first, middle and last positions of a run share different edges with the screen frame.
    private func boundaryIndex(of ordinal: Int) -> Int {
        ordinal == 0 ? 0 : (ordinal == 5 ? 2 : 1)
    }

    func testAnotherVerticalSixthChordRestartsAtTheWholeSixth() {
        withVerticalSixthsCyclingTwelfths(true) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 600, height: 400)
            let firstColumnTopHalf = calculate(.firstVerticalSixth, visibleFrame: visibleFrame, lastAction: nil)
            let lastAction = RectangleAction(action: .firstVerticalSixth,
                                             subAction: firstColumnTopHalf.subAction,
                                             rect: firstColumnTopHalf.rect)

            XCTAssertEqual(calculate(.fifthVerticalSixth, visibleFrame: visibleFrame, lastAction: lastAction).rect,
                           CGRect(x: 420, y: 40, width: 100, height: 400))
        }
    }

    func testFirstVerticalSixthWalksAcrossTheScreenByDefault() {
        withVerticalSixthsCyclingTwelfths(nil) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 600, height: 400)
            let results = repeatedResults(for: .firstVerticalSixth, count: 7, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map { $0.rect.minX }, [20, 120, 220, 320, 420, 520, 20])
        }
    }

    func testLastVerticalSixthWalksBackwardByDefault() {
        withVerticalSixthsCyclingTwelfths(nil) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 600, height: 400)
            let results = repeatedResults(for: .lastVerticalSixth, count: 7, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map { $0.rect.minX }, [520, 420, 320, 220, 120, 20, 520])
        }
    }

    func testMiddleVerticalSixthsStayWholeOnRepeatByDefault() {
        withVerticalSixthsCyclingTwelfths(nil) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 600, height: 400)
            let results = repeatedResults(for: .thirdVerticalSixth, count: 3, visibleFrame: visibleFrame)
            XCTAssertEqual(results.map(\.rect),
                           Array(repeating: CGRect(x: 220, y: 40, width: 100, height: 400), count: 3))
        }
    }

    func testEndpointCyclingIsDisabledWhenSubsequentExecutionModeIsNone() {
        withSubsequentExecutionMode(.none) {
            let visibleFrame = CGRect(x: 20, y: 40, width: 600, height: 400)
            XCTAssertEqual(repeatedResults(for: .firstVerticalSixth, count: 3, visibleFrame: visibleFrame).map { $0.rect.minX },
                           [20, 20, 20])
            XCTAssertEqual(repeatedResults(for: .lastVerticalSixth, count: 3, visibleFrame: visibleFrame).map { $0.rect.minX },
                           [520, 520, 520])
        }
    }

    func testVerticalSixthResultingSubActionsProvideGapEdges() {
        let landscape = CGRect(x: 20, y: 40, width: 1003, height: 800)
        let portrait = CGRect(x: 20, y: 40, width: 800, height: 1003)
        let landscapeEdges: [Edge] = [.right, [.left, .right], [.left, .right], [.left, .right], [.left, .right], .left]
        let portraitEdges: [Edge] = [.bottom, [.top, .bottom], [.top, .bottom], [.top, .bottom], [.top, .bottom], .top]

        for (index, action) in actions.enumerated() {
            XCTAssertEqual(calculate(action, visibleFrame: landscape).subAction?.gapSharedEdge, landscapeEdges[index])
            XCTAssertEqual(calculate(action, visibleFrame: portrait).subAction?.gapSharedEdge, portraitEdges[index])
        }
    }

    func testVerticalSixthActionsAreHiddenFromMenuAndDragSnapping() {
        XCTAssertTrue(actions.allSatisfy { WindowAction.active.contains($0) })
        XCTAssertTrue(actions.allSatisfy(\.excludedFromMenu))
        XCTAssertTrue(actions.allSatisfy { !$0.isDragSnappable })
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

    private func withVerticalSixthsCyclingTwelfths(_ enabled: Bool?, _ body: () -> Void) {
        let saved = Defaults.verticalSixthsCycleTwelfths.enabled
        defer { Defaults.verticalSixthsCycleTwelfths.enabled = saved }
        Defaults.verticalSixthsCycleTwelfths.enabled = enabled
        withSubsequentExecutionMode(.resize, body)
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
