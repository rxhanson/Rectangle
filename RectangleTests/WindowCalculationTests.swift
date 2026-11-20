/// WindowCalculationTests.swift

import XCTest
@testable import Rectangle

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

final class CornerCycleExpansionModeTests: XCTestCase {
    func testExistingPreferenceRawValuesRemainCompatible() {
        XCTAssertEqual(CornerCycleExpansionMode.horizontal.rawValue, 0)
        XCTAssertEqual(CornerCycleExpansionMode.vertical.rawValue, 1)
        XCTAssertEqual(CornerCycleExpansionMode(rawValue: 0), .horizontal)
        XCTAssertEqual(CornerCycleExpansionMode(rawValue: 1), .vertical)
    }

    func testCooperativeCornerHelpersUseResolvedAxis() {
        let savedMode = Defaults.cornerCycleExpansionAxis.value
        defer { Defaults.cornerCycleExpansionAxis.value = savedMode }
        Defaults.cornerCycleExpansionAxis.value = .displayOrientation

        let landscapeFrame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let portraitFrame = CGRect(x: 0, y: 0, width: 900, height: 1200)
        XCTAssertEqual(CooperativeResizeCoordinator.axis(for: .topLeft, screenFrame: landscapeFrame), .horizontal)
        XCTAssertEqual(CooperativeResizeCoordinator.axis(for: .topLeft, screenFrame: portraitFrame), .vertical)

        if case .right? = CooperativeResizeCoordinator.movedEdge(for: .topLeft, axis: .horizontal) {
            // Expected: cycling width moves the right edge of a left corner.
        } else {
            XCTFail("Horizontal top-left cycling should move the right edge")
        }
        if case .bottom? = CooperativeResizeCoordinator.movedEdge(for: .topLeft, axis: .vertical) {
            // Expected: cycling height moves the bottom edge of a top corner.
        } else {
            XCTFail("Vertical top-left cycling should move the bottom edge")
        }
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

final class RepeatedMaximizeTestScreen: NSScreen {
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

final class CenterThirdsRectTests: XCTestCase {
    // A landscape frame whose width and height are both indivisible by 3, so the old
    // `/ 3.0` without a floor produced fractional window geometry.
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func rect(_ action: WindowAction) -> CGRect {
        WindowCalculationFactory.calculationsByAction[action]!.calculateRect(
            RectCalculationParameters(window: Window(id: 1, rect: screen),
                                      visibleFrameOfScreen: screen,
                                      action: action,
                                      lastAction: nil)
        ).rect
    }

    private func assertWholePixels(_ rect: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, rect.minX.rounded(), "minX \(rect.minX) is fractional", file: file, line: line)
        XCTAssertEqual(rect.minY, rect.minY.rounded(), "minY \(rect.minY) is fractional", file: file, line: line)
        XCTAssertEqual(rect.width, rect.width.rounded(), "width \(rect.width) is fractional", file: file, line: line)
        XCTAssertEqual(rect.height, rect.height.rounded(), "height \(rect.height) is fractional", file: file, line: line)
    }

    func testCenterThirdHasWholePixelGeometry() {
        assertWholePixels(rect(.centerThird))
    }

    func testCenterThirdTilesContiguouslyWithFirstAndLastThirds() {
        let first = rect(.firstThird)
        let center = rect(.centerThird)
        let last = rect(.lastThird)
        // The three horizontal thirds meet with no gap and no overlap.
        XCTAssertEqual(center.minX, first.maxX, accuracy: 0.0001)
        XCTAssertEqual(center.maxX, last.minX, accuracy: 0.0001)
    }

    func testCenterTwoThirdsHasWholePixelsAndIsCentered() {
        let r = rect(.centerTwoThirds)
        assertWholePixels(r)
        XCTAssertEqual(r.minX - screen.minX, screen.maxX - r.maxX, accuracy: 0.0001)
    }

    func testMiddleVerticalThirdHasWholePixelsAndIsCentered() {
        let r = rect(.middleVerticalThird)
        assertWholePixels(r)
        XCTAssertEqual(r.minY - screen.minY, screen.maxY - r.maxY, accuracy: 0.0001)
    }
}

final class SwitchSidesRepeatedCommandTests: XCTestCase {
    private let windowId: CGWindowID = 4242
    private let screen = RepeatedMaximizeTestScreen(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
    private let floating = CGRect(x: 100, y: 100, width: 400, height: 300)
    private var savedMode: SubsequentExecutionMode = .resize
    private var savedPreserveOtherAxis = false
    private var savedHorizontalSplitRatio: Float = 50
    private var savedVerticalSplitRatio: Float = 50
    private var savedGapSize: Float = 0

    override func setUp() {
        super.setUp()
        savedMode = Defaults.subsequentExecutionMode.value
        savedPreserveOtherAxis = Defaults.halvesPreserveOtherAxisSize.enabled
        savedHorizontalSplitRatio = Defaults.horizontalSplitRatio.value
        savedVerticalSplitRatio = Defaults.verticalSplitRatio.value
        savedGapSize = Defaults.gapSize.value
        Defaults.subsequentExecutionMode.value = .switchSides
        Defaults.halvesPreserveOtherAxisSize.enabled = false
        Defaults.horizontalSplitRatio.value = 50
        Defaults.verticalSplitRatio.value = 50
        Defaults.gapSize.value = 0
        ActiveSideSplitRatios.shared.resetAll()
    }

    override func tearDown() {
        Defaults.subsequentExecutionMode.value = savedMode
        Defaults.halvesPreserveOtherAxisSize.enabled = savedPreserveOtherAxis
        Defaults.horizontalSplitRatio.value = savedHorizontalSplitRatio
        Defaults.verticalSplitRatio.value = savedVerticalSplitRatio
        Defaults.gapSize.value = savedGapSize
        ActiveSideSplitRatios.shared.resetAll()
        super.tearDown()
    }

    // MARK: - Left and right halves

    func testRepeatedLeftHalfSwitchesToTheRightHalfAndBack() throws {
        let first = try XCTUnwrap(calculate(.leftHalf, window: floating, last: nil))
        XCTAssertEqual(first.resultingAction, .leftHalf)
        assertRect(first.rect, plainHalf(.leftHalf))

        let second = try XCTUnwrap(calculate(.leftHalf, window: first.rect, last: (first.resultingAction, first.rect)))
        XCTAssertEqual(second.resultingAction, .rightHalf)
        assertRect(second.rect, plainHalf(.rightHalf))

        let third = try XCTUnwrap(calculate(.leftHalf, window: second.rect, last: (second.resultingAction, second.rect)))
        XCTAssertEqual(third.resultingAction, .leftHalf)
        assertRect(third.rect, plainHalf(.leftHalf))
    }

    func testRepeatedRightHalfSwitchesToTheLeftHalf() throws {
        let first = try XCTUnwrap(calculate(.rightHalf, window: floating, last: nil))
        XCTAssertEqual(first.resultingAction, .rightHalf)

        let second = try XCTUnwrap(calculate(.rightHalf, window: first.rect, last: (first.resultingAction, first.rect)))
        XCTAssertEqual(second.resultingAction, .leftHalf)
        assertRect(second.rect, plainHalf(.leftHalf))
    }

    func testPressingTheOtherSideMovesThereWithoutSwitching() throws {
        // Left Half, then Right Half: the window simply goes right; switching only happens on a repeat.
        let left = try XCTUnwrap(calculate(.leftHalf, window: floating, last: nil))
        let right = try XCTUnwrap(calculate(.rightHalf, window: left.rect, last: (left.resultingAction, left.rect)))
        XCTAssertEqual(right.resultingAction, .rightHalf)
        assertRect(right.rect, plainHalf(.rightHalf))
    }

    func testAWindowThatMovedSinceTheLastActionGetsAPlainHalf() throws {
        let first = try XCTUnwrap(calculate(.leftHalf, window: floating, last: nil))
        let moved = first.rect.offsetBy(dx: 0, dy: 10)
        let result = try XCTUnwrap(calculate(.leftHalf, window: moved, last: (.leftHalf, first.rect)))
        XCTAssertEqual(result.resultingAction, .leftHalf)
        assertRect(result.rect, plainHalf(.leftHalf))
    }

    func testAnUnrelatedLastActionGetsAPlainHalf() throws {
        let maximized = screen.frame
        let result = try XCTUnwrap(calculate(.leftHalf, window: maximized, last: (.maximize, maximized)))
        XCTAssertEqual(result.resultingAction, .leftHalf)
        assertRect(result.rect, plainHalf(.leftHalf))
    }

    func testTheOppositeSideUsesTheComplementarySplitRatio() throws {
        Defaults.horizontalSplitRatio.value = 60
        Defaults.verticalSplitRatio.value = 60
        ActiveSideSplitRatios.shared.resetAll()
        let visible = screen.adjustedVisibleFrame()

        let left = try XCTUnwrap(calculate(.leftHalf, window: floating, last: nil))
        XCTAssertEqual(left.rect.width, floor(visible.width * 0.6), accuracy: 1)
        let right = try XCTUnwrap(calculate(.leftHalf, window: left.rect, last: (left.resultingAction, left.rect)))
        XCTAssertEqual(right.rect.width, floor(visible.width * 0.4), accuracy: 1)
        XCTAssertEqual(right.rect.maxX, visible.maxX, accuracy: 0.5)
        let back = try XCTUnwrap(calculate(.leftHalf, window: right.rect, last: (right.resultingAction, right.rect)))
        XCTAssertEqual(back.rect.width, floor(visible.width * 0.6), accuracy: 1)
        XCTAssertEqual(back.rect.minX, visible.minX, accuracy: 0.5)

        let top = try XCTUnwrap(calculate(.topHalf, window: floating, last: nil))
        XCTAssertEqual(top.rect.height, floor(visible.height * 0.6), accuracy: 1)
        let bottom = try XCTUnwrap(calculate(.topHalf, window: top.rect, last: (top.resultingAction, top.rect)))
        XCTAssertEqual(bottom.rect.height, floor(visible.height * 0.4), accuracy: 1)
        XCTAssertEqual(bottom.rect.minY, visible.minY, accuracy: 0.5)
    }

    // MARK: - Top and bottom halves

    func testRepeatedTopHalfSwitchesToTheBottomHalfAndBack() throws {
        let first = try XCTUnwrap(calculate(.topHalf, window: floating, last: nil))
        XCTAssertEqual(first.resultingAction, .topHalf)

        let second = try XCTUnwrap(calculate(.topHalf, window: first.rect, last: (first.resultingAction, first.rect)))
        XCTAssertEqual(second.resultingAction, .bottomHalf)
        assertRect(second.rect, plainHalf(.bottomHalf))

        let third = try XCTUnwrap(calculate(.topHalf, window: second.rect, last: (second.resultingAction, second.rect)))
        XCTAssertEqual(third.resultingAction, .topHalf)
        assertRect(third.rect, plainHalf(.topHalf))
    }

    func testRepeatedBottomHalfSwitchesToTheTopHalf() throws {
        let first = try XCTUnwrap(calculate(.bottomHalf, window: floating, last: nil))
        let second = try XCTUnwrap(calculate(.bottomHalf, window: first.rect, last: (first.resultingAction, first.rect)))
        XCTAssertEqual(second.resultingAction, .topHalf)
        assertRect(second.rect, plainHalf(.topHalf))
    }

    // MARK: - Interplay with other options

    func testPlainHalvesStillSwitchWhenHalvesPreserveTheOtherAxis() throws {
        Defaults.halvesPreserveOtherAxisSize.enabled = true

        let left = try XCTUnwrap(calculate(.leftHalf, window: floating, last: nil))
        let right = try XCTUnwrap(calculate(.leftHalf, window: left.rect, last: (left.resultingAction, left.rect)))
        XCTAssertEqual(right.resultingAction, .rightHalf)
        assertRect(right.rect, plainHalf(.rightHalf))

        let top = try XCTUnwrap(calculate(.topHalf, window: floating, last: nil))
        let bottom = try XCTUnwrap(calculate(.topHalf, window: top.rect, last: (top.resultingAction, top.rect)))
        XCTAssertEqual(bottom.resultingAction, .bottomHalf)
        assertRect(bottom.rect, plainHalf(.bottomHalf))
    }

    func testAQuarterKeepsItsPlaceWhenHalvesPreserveTheOtherAxis() throws {
        Defaults.halvesPreserveOtherAxisSize.enabled = true
        let visible = screen.adjustedVisibleFrame()
        let quarter = HalfSplitFrameCalculation.cornerRect(in: visible, horizontalSide: .leading, verticalSide: .leading,
                                                           horizontalFraction: 0.5, verticalFraction: 0.5)

        let result = try XCTUnwrap(calculate(.topHalf, window: quarter, last: (.topLeft, quarter)))
        XCTAssertEqual(result.resultingAction, .topLeft)
        assertRect(result.rect, quarter)
    }

    func testASideSwitchIsNotACooperativeResize() {
        let left = CGRect(x: 0, y: 0, width: 500, height: 600)
        let right = CGRect(x: 500, y: 0, width: 500, height: 600)
        let widerLeft = CGRect(x: 0, y: 0, width: 667, height: 600)
        XCTAssertTrue(CooperativeCornerResize.isSideSwitch(oldFocusedFrame: left, newFocusedFrame: right, axis: .horizontal, tolerance: 4))
        XCTAssertFalse(CooperativeCornerResize.isSideSwitch(oldFocusedFrame: left, newFocusedFrame: widerLeft, axis: .horizontal, tolerance: 4))
        XCTAssertFalse(CooperativeCornerResize.isSideSwitch(oldFocusedFrame: left, newFocusedFrame: left, axis: .horizontal, tolerance: 4))

        let top = CGRect(x: 0, y: 300, width: 1000, height: 300)
        let bottom = CGRect(x: 0, y: 0, width: 1000, height: 300)
        XCTAssertTrue(CooperativeCornerResize.isSideSwitch(oldFocusedFrame: top, newFocusedFrame: bottom, axis: .vertical, tolerance: 4))
        XCTAssertFalse(CooperativeCornerResize.isSideSwitch(oldFocusedFrame: top, newFocusedFrame: bottom, axis: .horizontal, tolerance: 4))
    }

    // MARK: - Scope of the mode

    func testOtherModesDoNotSwitchSides() throws {
        for mode in SubsequentExecutionMode.ordered where mode != .switchSides {
            Defaults.subsequentExecutionMode.value = mode
            for action in [WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf] {
                let first = try XCTUnwrap(calculate(action, window: floating, last: nil))
                let second = try XCTUnwrap(calculate(action, window: first.rect, last: (first.resultingAction, first.rect)))
                XCTAssertEqual(second.resultingAction, action, "\(mode) \(action)")
            }
        }
    }

    func testThirdsKeepTogglingInTheSwitchSidesMode() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let calculation = WindowCalculationFactory.calculationsByAction[.firstTwoThirds]!
        func params(window: CGRect, last: RectangleAction?) -> RectCalculationParameters {
            RectCalculationParameters(window: Window(id: windowId, rect: window),
                                      visibleFrameOfScreen: visibleFrame,
                                      action: .firstTwoThirds,
                                      lastAction: last)
        }
        let first = calculation.calculateRect(params(window: visibleFrame, last: nil))
        XCTAssertEqual(first.rect.minX, 0)
        XCTAssertEqual(first.rect.width, 600)

        let repeated = calculation.calculateRect(params(window: first.rect,
                                                        last: RectangleAction(action: .firstTwoThirds, subAction: first.subAction, rect: first.rect, count: 1)))
        XCTAssertEqual(repeated.rect.minX, 300)
        XCTAssertEqual(repeated.rect.width, 600)
        XCTAssertNotEqual(repeated.subAction, first.subAction)

        let back = calculation.calculateRect(params(window: repeated.rect,
                                                    last: RectangleAction(action: .firstTwoThirds, subAction: repeated.subAction, rect: repeated.rect, count: 2)))
        XCTAssertEqual(back.rect.minX, 0)
    }

    func testTheModeIsOfferedAndNeitherResizesNorTraverses() {
        XCTAssertTrue(SubsequentExecutionMode.ordered.contains(.switchSides))
        XCTAssertEqual(SubsequentExecutionMode(rawValue: 6), .switchSides)
        XCTAssertFalse(SubsequentExecutionMode.switchSides.resizes)
        XCTAssertFalse(Defaults.subsequentExecutionMode.resizes)
        XCTAssertFalse(Defaults.subsequentExecutionMode.traversesDisplays)
        XCTAssertFalse(Defaults.subsequentExecutionMode.cyclesQuadrantPositions)
    }

    // MARK: - Helpers

    /// Runs the action's calculation the way WindowManager does: the window in screen coordinates,
    /// and the recorded rect flipped as `recordAction` stores it, so a repeat is recognised when they match.
    private func calculate(_ action: WindowAction, window: CGRect, last: (WindowAction, CGRect)?) -> WindowCalculationResult? {
        let params = WindowCalculationParameters(window: Window(id: windowId, rect: window),
                                                 usableScreens: UsableScreens(currentScreen: screen, numScreens: 1),
                                                 action: action,
                                                 lastAction: last.map { RectangleAction(action: $0.0, subAction: nil, rect: $0.1.screenFlipped, count: 1) },
                                                 ignoreTodo: false)
        return WindowCalculationFactory.calculationsByAction[action]!.calculate(params)
    }

    /// What a first execution of the action produces on this screen.
    private func plainHalf(_ action: WindowAction) -> CGRect {
        calculate(action, window: floating, last: nil)?.rect ?? .null
    }

    private func assertRect(_ rect: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, expected.minX, accuracy: 0.5, "minX", file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: 0.5, "minY", file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 0.5, "width", file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 0.5, "height", file: file, line: line)
    }
}
