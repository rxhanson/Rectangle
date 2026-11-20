/// FreeformDragTests.swift

import CoreGraphics
import XCTest
@testable import Rectangle

/// Screenshot-style selection geometry. Coordinates are AppKit screen coordinates, on a
/// display left of and above the main display, so they are negative and offset.
final class FreeformDragTests: XCTestCase {
    private let bounds = CGRect(x: -1200, y: 960, width: 1200, height: 800)
    private let start = CGPoint(x: -850, y: 1300)

    // MARK: - Dragging

    func testDragsInEveryDirectionFromTheStartingPoint() {
        for end in [CGPoint(x: -650, y: 1400), CGPoint(x: -1050, y: 1400),
                    CGPoint(x: -650, y: 1200), CGPoint(x: -1050, y: 1200)] {
            var drag = FreeformDrag(start: start, bounds: bounds)
            let expected = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: 200, height: 100)

            drag.update(to: end)
            XCTAssertEqual(drag.rect, expected, "to \(end)")
            XCTAssertEqual(drag.finish(at: end), expected, "to \(end)")
        }
    }

    func testFollowsThePointerBackAcrossTheStartingPoint() {
        var drag = FreeformDrag(start: start, bounds: bounds)

        drag.update(to: CGPoint(x: -650, y: 1400))
        drag.update(to: CGPoint(x: -900, y: 1250))

        XCTAssertEqual(drag.rect, CGRect(x: -900, y: 1250, width: 50, height: 50))
    }

    func testStaysInsideTheBoundsWhenThePointerLeavesThem() {
        var drag = FreeformDrag(start: start, bounds: bounds)

        drag.update(to: CGPoint(x: 300, y: 2000))
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 850, height: 460))

        drag.update(to: CGPoint(x: -5000, y: -5000))
        XCTAssertEqual(drag.rect, CGRect(x: -1200, y: 960, width: 350, height: 340))
    }

    func testStartingOutsideTheBoundsStartsAtTheirEdge() {
        // Pressing on the menu bar, above the usable area.
        var drag = FreeformDrag(start: CGPoint(x: -850, y: 1775), bounds: bounds)

        drag.update(to: CGPoint(x: -650, y: 1660))

        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1660, width: 200, height: 100))
    }

    func testCoversTheWholeBoundsCornerToCorner() {
        var drag = FreeformDrag(start: CGPoint(x: -1300, y: 900), bounds: bounds)

        XCTAssertEqual(drag.finish(at: CGPoint(x: 300, y: 2000)), bounds)
    }

    func testReachesTheDisplayEdgesThePointerStopsShortOf() {
        // The last pixel column and row are at x = maxX - 1 and y = 1 (y = 0.5 on Retina displays).
        let display = CGRect(x: 0, y: 0, width: 1512, height: 944)
        var drag = FreeformDrag(start: CGPoint(x: 756, y: 500), bounds: display)

        drag.update(to: CGPoint(x: 1511, y: 1))
        XCTAssertEqual(drag.rect, CGRect(x: 756, y: 0, width: 756, height: 500))
        drag.update(to: CGPoint(x: 1511.5, y: 0.5))
        XCTAssertEqual(drag.rect, CGRect(x: 756, y: 0, width: 756, height: 500))
        drag.update(to: CGPoint(x: 1510, y: 2))
        XCTAssertEqual(drag.rect, CGRect(x: 756, y: 2, width: 754, height: 498))
    }

    func testSnapsEdgesToWholePoints() {
        var drag = FreeformDrag(start: CGPoint(x: -850.4, y: 1300.6), bounds: bounds)

        drag.update(to: CGPoint(x: -649.4, y: 1400.2))

        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1301, width: 201, height: 99))
    }

    func testTreatsTinyDragsAsClicks() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        XCTAssertNil(drag.finish(at: start))
        XCTAssertNil(drag.finish(at: CGPoint(x: start.x + 7, y: start.y + 50)))
        XCTAssertNil(drag.finish(at: CGPoint(x: start.x + 50, y: start.y - 7)))

        let rect = drag.finish(at: CGPoint(x: start.x + 8, y: start.y - 8))
        XCTAssertEqual(rect, CGRect(x: start.x, y: start.y - 8, width: 8, height: 8))
    }

    func testFinishUsesTheReleasePosition() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -500, y: 1500))

        XCTAssertEqual(drag.finish(at: CGPoint(x: -750, y: 1350)), CGRect(x: -850, y: 1300, width: 100, height: 50))
    }

    // MARK: - Space moves the selection

    func testSpaceMovesTheSelectionWithoutResizingIt() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))

        drag.update(to: CGPoint(x: -600, y: 1350), modifiers: .move)
        XCTAssertEqual(drag.rect, CGRect(x: -800, y: 1250, width: 200, height: 100))

        // Releasing Space resizes from where the selection was moved to, without a jump.
        drag.update(to: CGPoint(x: -600, y: 1350))
        XCTAssertEqual(drag.rect, CGRect(x: -800, y: 1250, width: 200, height: 100))
        drag.update(to: CGPoint(x: -550, y: 1370))
        XCTAssertEqual(drag.rect, CGRect(x: -800, y: 1250, width: 250, height: 120))
    }

    func testMovingStopsAtTheBoundsAndKeepsTheSize() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))

        drag.update(to: CGPoint(x: 1000, y: 3000), modifiers: .move)
        XCTAssertEqual(drag.rect, CGRect(x: -200, y: 1660, width: 200, height: 100))

        // Moving back moves it as far as the pointer moves.
        drag.update(to: CGPoint(x: 900, y: 2900), modifiers: .move)
        XCTAssertEqual(drag.rect, CGRect(x: -300, y: 1560, width: 200, height: 100))
    }

    func testPointerOutsideTheBoundsMovesTheVisibleSelection() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: 400, y: 1400))
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 850, height: 100))

        drag.update(to: CGPoint(x: 300, y: 1380), modifiers: .move)

        XCTAssertEqual(drag.rect, CGRect(x: -950, y: 1280, width: 850, height: 100))
    }

    // MARK: - Option resizes around the starting point

    func testOptionResizesAroundTheStartingPoint() {
        var drag = FreeformDrag(start: start, bounds: bounds)

        drag.update(to: CGPoint(x: -750, y: 1250), modifiers: .fromCenter)
        XCTAssertEqual(drag.rect, CGRect(x: -950, y: 1250, width: 200, height: 100))

        // Releasing Option goes back to resizing from the starting point.
        drag.update(to: CGPoint(x: -750, y: 1250))
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1250, width: 100, height: 50))
    }

    func testOptionKeepsTheSelectionCenteredAtTheBounds() {
        // 150 points from the left edge and 460 from the top edge.
        var drag = FreeformDrag(start: CGPoint(x: -1050, y: 1300), bounds: bounds)

        drag.update(to: CGPoint(x: -700, y: 1000), modifiers: .fromCenter)

        XCTAssertEqual(drag.rect, CGRect(x: -1200, y: 1000, width: 300, height: 600))
    }

    func testSpaceMovesACenteredSelection() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -750, y: 1350), modifiers: .fromCenter)

        drag.update(to: CGPoint(x: -650, y: 1350), modifiers: [.fromCenter, .move])

        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1250, width: 200, height: 100))
    }

    // MARK: - Shift locks an axis

    func testShiftLocksTheHeightWhenThePointerMovesSideways() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))

        drag.update(to: CGPoint(x: -650, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -600, y: 1420), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -550, y: 1500), modifiers: .lockAxis)

        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 300, height: 100))
    }

    func testShiftLocksTheWidthWhenThePointerMovesVertically() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))

        drag.update(to: CGPoint(x: -650, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -640, y: 1450), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -500, y: 1500), modifiers: .lockAxis)

        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 200, height: 200))
    }

    func testShiftWaitsForAClearDirectionBeforeLocking() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))

        drag.update(to: CGPoint(x: -650, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -648, y: 1401), modifiers: .lockAxis)
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 202, height: 101))

        drag.update(to: CGPoint(x: -600, y: 1401), modifiers: .lockAxis)
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 250, height: 100))
    }

    func testReleasingShiftKeepsTheLockedSideWhereItWas() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))
        drag.update(to: CGPoint(x: -650, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -550, y: 1450), modifiers: .lockAxis)
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 300, height: 100))

        drag.update(to: CGPoint(x: -550, y: 1450))
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 300, height: 100))
        drag.update(to: CGPoint(x: -550, y: 1470))
        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 300, height: 120))
    }

    func testPressingShiftAgainLocksAfresh() {
        var drag = FreeformDrag(start: start, bounds: bounds)
        drag.update(to: CGPoint(x: -650, y: 1400))
        drag.update(to: CGPoint(x: -650, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -550, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -550, y: 1400))

        drag.update(to: CGPoint(x: -550, y: 1400), modifiers: .lockAxis)
        drag.update(to: CGPoint(x: -540, y: 1500), modifiers: .lockAxis)

        XCTAssertEqual(drag.rect, CGRect(x: -850, y: 1300, width: 300, height: 200))
    }
}
