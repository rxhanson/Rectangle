import XCTest
import CoreGraphics
@testable import Rectangle

final class DisplayTransferTests: XCTestCase {
    /// A built-in display, and a larger external display placed to the right of it and lower down,
    /// so that a transfer that forgets to translate coordinates is caught.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 945)
    private let external = CGRect(x: 1512, y: -235, width: 2560, height: 1415)

    /// The tolerance is passed in so that the tests don't depend on the user's gap size.
    private func transfer(_ window: CGRect, from source: CGRect, to destination: CGRect,
                          edgeTolerance: CGFloat = 4) -> CGRect {
        DisplayTransfer.transferredRect(window: window, source: source, destination: destination,
                                        edgeTolerance: edgeTolerance)
    }

    private func assertRect(_ rect: CGRect, _ expected: CGRect, accuracy: CGFloat = 0.001,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, expected.minX, accuracy: accuracy, "minX", file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: accuracy, "minY", file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: accuracy, "width", file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: accuracy, "height", file: file, line: line)
    }

    // MARK: - Against both edges: the window follows both, so it spans the destination

    func testMaximizedWindowFillsTheLargerDestination() {
        assertRect(transfer(laptop, from: laptop, to: external), external)
    }

    func testMaximizedWindowFillsTheSmallerDestination() {
        assertRect(transfer(external, from: external, to: laptop), laptop)
    }

    func testTheDistanceFromTheEdgesIsCarriedOverSoGapsSurvive() {
        // What a maximize looks like with a 10pt gap: never flush, so the tolerance has to allow
        // for it, and the same gap has to come out the other side.
        let window = laptop.insetBy(dx: 10, dy: 10)
        assertRect(transfer(window, from: laptop, to: external, edgeTolerance: 14),
                   external.insetBy(dx: 10, dy: 10))
    }

    // MARK: - Against one edge: the window keeps its size and stays against that edge

    func testLeftHalfKeepsItsWidthAndStaysOnTheLeft() {
        let window = CGRect(x: 0, y: 0, width: 756, height: 945)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 1512, y: -235, width: 756, height: 1415))
    }

    func testRightHalfKeepsItsWidthAndStaysOnTheRight() {
        let window = CGRect(x: 756, y: 0, width: 756, height: 945)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 3316, y: -235, width: 756, height: 1415))
    }

    func testRightHalfOfTheLargerDisplayStaysOnTheRightOfTheSmallerOne() {
        let window = CGRect(x: 2792, y: -235, width: 1280, height: 1415)
        assertRect(transfer(window, from: external, to: laptop),
                   CGRect(x: 232, y: 0, width: 1280, height: 945))
    }

    func testQuarterArrivesInTheSameCorner() {
        let window = CGRect(x: 756, y: 472.5, width: 756, height: 472.5)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 3316, y: 707.5, width: 756, height: 472.5))
    }

    func testWindowHangingOffTheEdgeIsBroughtBackOn() {
        let window = CGRect(x: -200, y: 0, width: 500, height: 400)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 1512, y: -235, width: 500, height: 400))
    }

    // MARK: - Against neither edge: the window keeps its size and its relative spot

    func testCenteredWindowStaysCenteredAtTheSameSize() {
        let window = CGRect(x: 556, y: 300, width: 400, height: 345)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 2592, y: 300, width: 400, height: 345))
    }

    func testWindowInTheRightThirdArrivesInTheRightThird() {
        let window = CGRect(x: 1000, y: 300, width: 400, height: 345)
        let transferred = transfer(window, from: laptop, to: external)
        XCTAssertEqual((transferred.midX - external.minX) / external.width,
                       (window.midX - laptop.minX) / laptop.width, accuracy: 0.001)
        XCTAssertEqual(transferred.size, window.size)
    }

    func testTheTwoAxesAreIndependent() {
        // Against the left edge, floating vertically.
        let window = CGRect(x: 0, y: 300, width: 400, height: 345)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 1512, y: 300, width: 400, height: 345))
    }

    func testWindowTooLargeForTheDestinationIsCutDownToFit() {
        let window = CGRect(x: 1612, y: -135, width: 2360, height: 1215)
        assertRect(transfer(window, from: external, to: laptop), laptop)
    }

    // MARK: - Edge cases

    func testMovingBetweenIdenticalDisplaysLeavesTheWindowAlone() {
        for window in [laptop,
                       CGRect(x: 0, y: 0, width: 756, height: 945),
                       CGRect(x: 556, y: 300, width: 400, height: 345),
                       CGRect(x: 1000, y: 300, width: 400, height: 345)] {
            assertRect(transfer(window, from: laptop, to: laptop), window)
        }
    }

    func testEmptyFrameIsLeftAlone() {
        let window = CGRect(x: 556, y: 300, width: 400, height: 345)
        assertRect(transfer(window, from: .zero, to: external), window)
        assertRect(transfer(window, from: laptop, to: .zero), window)
    }

    func testTheResultAlwaysFitsOnTheDestination() {
        let windows = [laptop,
                       laptop.insetBy(dx: 10, dy: 10),
                       CGRect(x: 0, y: 0, width: 756, height: 945),
                       CGRect(x: 756, y: 472.5, width: 756, height: 472.5),
                       CGRect(x: -200, y: -100, width: 500, height: 400),
                       CGRect(x: 1400, y: 800, width: 400, height: 345),
                       CGRect(x: 556, y: 300, width: 400, height: 345)]
        for window in windows {
            for (source, destination) in [(laptop, external), (external, laptop)] {
                let transferred = transfer(window, from: source, to: destination)
                XCTAssertTrue(destination.insetBy(dx: -0.001, dy: -0.001).contains(transferred),
                              "\(transferred) does not fit on \(destination)")
            }
        }
    }
}
