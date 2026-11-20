/// StackAndOverlapTests.swift

import Carbon.HIToolbox
import XCTest
@testable import Rectangle

class StackBadgeGeometryTests: XCTestCase {

    private let laptopFrame = CGRect(x: 0, y: 0, width: 2336, height: 1510)
    // Real rig geometry: external 4K TVs with negative origins.
    private let tvFrame = CGRect(x: -5212, y: 1510, width: 3840, height: 2160)

    func testCornerCountMatchesUnionOfGridFractions() {
        // Column fractions across all grids: 0, 1/4, 1/3, 1/2, 2/3, 3/4 (6 values).
        // Row fractions are the same set. 6 x 6 = 36 unique corners.
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        XCTAssertEqual(corners.count, 36)
    }

    func testCoincidentCornersAreDeduplicated() {
        // The half corner and the quarter corner at x = width/2 coincide;
        // they must appear once, not once per grid.
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        let midTop = corners.filter { abs($0.x - 1168) < 1 && abs($0.y - 1510) < 1 }
        XCTAssertEqual(midTop.count, 1)
    }

    func testScreenOriginIsACorner() {
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        XCTAssertTrue(corners.contains { abs($0.x - 0) < 1 && abs($0.y - 1510) < 1 },
                      "top-left of the screen must be a corner")
    }

    func testFarEdgesAreNotCorners() {
        // A cell's top-left can never sit on the right or bottom screen edge.
        let corners = StackBadgeGeometry.cornerPoints(in: laptopFrame)
        XCTAssertFalse(corners.contains { abs($0.x - laptopFrame.maxX) < 1 })
        XCTAssertFalse(corners.contains { abs($0.y - laptopFrame.minY) < 1 })
    }

    func testNegativeOriginScreenCorners() {
        let corners = StackBadgeGeometry.cornerPoints(in: tvFrame)
        XCTAssertEqual(corners.count, 36)
        XCTAssertTrue(corners.contains { abs($0.x - (-5212)) < 1 && abs($0.y - 3670) < 1 },
                      "top-left corner of a negative-origin screen")
        XCTAssertTrue(corners.contains { abs($0.x - (-5212 + 3840.0 / 3)) < 1 && abs($0.y - (3670 - 2160.0 / 3)) < 1 },
                      "interior ninth corner on a negative-origin screen")
    }

    func testEmptyFrameYieldsNoCorners() {
        XCTAssertTrue(StackBadgeGeometry.cornerPoints(in: .zero).isEmpty)
        XCTAssertTrue(StackBadgeGeometry.cornerPoints(in: .null).isEmpty)
    }

    func testHoverZoneHitInsideZone() {
        let corners = [CGPoint(x: 100, y: 500)]
        // 20pt right, 20pt below (AppKit y down = minus y) - inside a 30pt zone.
        let hit = StackBadgeGeometry.corner(near: CGPoint(x: 120, y: 480), in: corners, zone: 30)
        XCTAssertEqual(hit, corners[0])
    }

    func testHoverZoneMissOutsideZone() {
        let corners = [CGPoint(x: 100, y: 500)]
        XCTAssertNil(StackBadgeGeometry.corner(near: CGPoint(x: 140, y: 480), in: corners, zone: 30))
        // Above the corner is the neighboring cell - must not trigger.
        XCTAssertNil(StackBadgeGeometry.corner(near: CGPoint(x: 110, y: 520), in: corners, zone: 30))
        // Left of the corner is the neighboring cell - must not trigger.
        XCTAssertNil(StackBadgeGeometry.corner(near: CGPoint(x: 80, y: 490), in: corners, zone: 30))
    }

    func testHoverZonePicksNearestOfTwoCandidates() {
        let near = CGPoint(x: 100, y: 500)
        let far = CGPoint(x: 90, y: 510)
        let hit = StackBadgeGeometry.corner(near: CGPoint(x: 105, y: 495), in: [far, near], zone: 30)
        XCTAssertEqual(hit, near)
    }

    // Regression: the cascade offset runs +x but UP in AX y (it's applied in
    // AppKit coordinates and the y-axis flips), so clustering must accept
    // origins above the anchor. Real-world origins from a two-window stack
    // that the first implementation failed to count.
    func testStackClusterAcceptsUpwardCascade() {
        let origins = [CGPoint(x: 903, y: -2121), CGPoint(x: 892, y: -2110)]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.count, 2)
    }

    // Regression: with maxCascade capped at 1, the second and third windows
    // share an origin. All three belong to the stack.
    func testStackClusterCountsCascadeCapSharedOrigins() {
        let origins = [
            CGPoint(x: 903, y: -2121),
            CGPoint(x: 903, y: -2121),
            CGPoint(x: 892, y: -2110)
        ]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.count, 3)
    }

    func testStackClusterExcludesUnrelatedNeighbor() {
        // A window 30pt away from the anchor is a neighbor, not a stack member,
        // even though a gap-widened candidate box may have caught it.
        let origins = [CGPoint(x: 100, y: 100), CGPoint(x: 111, y: 89), CGPoint(x: 130, y: 130)]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.sorted(), [0, 1])
    }

    func testStackClusterAcceptsDownwardCascade() {
        // Edge clamping can flip the cascade direction locally; both must count.
        let origins = [CGPoint(x: 100, y: 100), CGPoint(x: 111, y: 111)]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.count, 2)
    }

    func testStackClusterEmptyInput() {
        XCTAssertTrue(StackBadgeGeometry.stackIndices(among: [], cascadeRange: 15, tolerance: 4).isEmpty)
    }





    // Regression (review finding): an unrelated window that happens to be the
    // leftmost candidate in the gap-widened box must not mask the real stack.
    func testStackClusterLeftOutlierDoesNotMaskStack() {
        let origins = [
            CGPoint(x: 100, y: 105),   // unrelated leftmost outlier
            CGPoint(x: 120, y: 100),   // buried
            CGPoint(x: 131, y: 89)     // front (cascade +11, -11)
        ]
        let indices = StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
        XCTAssertEqual(indices.sorted(), [1, 2])
    }

    func testTodoSidebarWidthUnitInExportArray() {
        let keys = Defaults.array.map { $0.key }
        XCTAssertTrue(keys.contains("todoSidebarWidthUnit"), "todoSidebarWidthUnit missing from Defaults.array")
    }
}

class StackCycleTests: XCTestCase {

    // AX coordinates (top-left origin), a left half on a 1440x900 screen.
    private let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
    private let cascadeRange: CGFloat = 15
    private let sizeTolerance = StackBadgeGeometry.sizeTolerance

    private func indices(_ frames: [CGRect], anchor: CGRect? = nil) -> [Int] {
        StackBadgeGeometry.stackMembers(anchor: anchor ?? leftHalf, among: frames,
                                       cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: sizeTolerance)
    }

    func testIdenticalFramesStack() {
        XCTAssertEqual(indices([leftHalf, leftHalf, leftHalf]), [0, 1, 2])
    }

    func testCascadedFramesStackInBothYDirections() {
        let up = leftHalf.offsetBy(dx: 11, dy: -11)
        let down = leftHalf.offsetBy(dx: 11, dy: 11)
        XCTAssertEqual(indices([leftHalf, up, down]), [0, 1, 2])
    }

    func testFrameOutsideCascadeRangeIsExcluded() {
        XCTAssertEqual(indices([leftHalf, leftHalf.offsetBy(dx: 30, dy: 0)]), [0])
    }

    // A maximized window shares the left half's corner, but it is not in the
    // same area, so it is not cycled with the half.
    func testMaximizedWindowAtSameCornerIsExcluded() {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(indices([leftHalf, maximized]), [0])
    }

    func testQuarterAtSameCornerIsExcluded() {
        let topLeftQuarter = CGRect(x: 0, y: 25, width: 720, height: 437)
        XCTAssertEqual(indices([leftHalf, topLeftQuarter]), [0])
    }

    // Terminals snap to whole character cells, so they land a little short.
    func testTerminalSizedWindowIsIncluded() {
        let terminal = CGRect(x: 0, y: 25, width: 714, height: 862)
        XCTAssertEqual(indices([leftHalf, terminal]), [0, 1])
    }

    func testRightHalfIsExcluded() {
        XCTAssertEqual(indices([leftHalf, leftHalf.offsetBy(dx: 720, dy: 0)]), [0])
    }

    func testEmptyInput() {
        XCTAssertTrue(indices([]).isEmpty)
    }

    // With stacks not limited to one size, every window at the corner counts,
    // as it does for the hover list.
    func testAnySizeIncludesEveryWindowAtTheCorner() {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let topLeftQuarter = CGRect(x: 0, y: 25, width: 720, height: 437)
        let rightHalf = leftHalf.offsetBy(dx: 720, dy: 0)
        let frames = [leftHalf, maximized, topLeftQuarter.offsetBy(dx: 11, dy: -11), rightHalf]
        XCTAssertEqual(StackBadgeGeometry.stackMembers(anchor: leftHalf, among: frames,
                                                      cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: nil),
                       [0, 1, 2])
    }

    // Regression (review finding): with gaps on halves but not on maximize,
    // a maximized window's origin sits just up and left of a half's. Cycling
    // must pick the same stack the hover list shows, whichever is in front.
    func testAnySizeStackMatchesHoverList() throws {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let half = CGRect(x: 8, y: 33, width: 712, height: 859)
        let offsetHalf = half.offsetBy(dx: 11, dy: 0)

        func cycleStack(_ frames: [CGRect]) throws -> [Int] {
            let origins = frames.map { $0.origin }
            let anchor = try XCTUnwrap(StackBadgeGeometry.clusterAnchor(containing: 0, among: origins,
                                                                        cascadeRange: cascadeRange, tolerance: 4))
            return StackBadgeGeometry.stackMembers(anchor: CGRect(origin: origins[anchor], size: frames[0].size),
                                                  among: frames, cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: nil)
        }
        func hoverStack(_ frames: [CGRect]) -> [Int] {
            StackBadgeGeometry.stackIndices(among: frames.map { $0.origin }, cascadeRange: cascadeRange, tolerance: 4)
        }

        let halfInFront = [half, offsetHalf, maximized]
        XCTAssertEqual(try cycleStack(halfInFront), [0, 1])
        XCTAssertEqual(try cycleStack(halfInFront), hoverStack(halfInFront))

        let maximizedInFront = [maximized, half, offsetHalf]
        XCTAssertEqual(try cycleStack(maximizedInFront), [0, 1])
        XCTAssertEqual(try cycleStack(maximizedInFront), hoverStack(maximizedInFront))
    }

    // Regression (review finding): limited to one size, a denser group of
    // maximized windows at the corner must not claim the focused half and
    // leave it with nothing to cycle to.
    func testSameSizeStackIgnoresDenserGroupOfOtherSizes() throws {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let half = CGRect(x: 8, y: 33, width: 712, height: 859)
        let frames = [half, half.offsetBy(dx: 11, dy: 0), maximized, maximized]
        let anchor = try XCTUnwrap(StackBadgeGeometry.stackAnchor(for: 0, among: frames, cascadeRange: cascadeRange,
                                                                 tolerance: 4, sizeTolerance: sizeTolerance))
        XCTAssertEqual(StackBadgeGeometry.stackMembers(anchor: anchor, among: frames,
                                                      cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: sizeTolerance),
                       [0, 1])
    }

    // A window cascaded right of the stack's anchor still finds the anchor's
    // stack, as the hover list would.
    func testFocusedWindowRightOfAnchorFindsItsStack() throws {
        let behind = CGRect(x: 0, y: 25, width: 720, height: 875)
        let frames = [behind.offsetBy(dx: 11, dy: -11), behind]
        let anchor = try XCTUnwrap(StackBadgeGeometry.stackAnchor(for: 0, among: frames, cascadeRange: cascadeRange,
                                                                 tolerance: 4, sizeTolerance: sizeTolerance))
        XCTAssertEqual(anchor.origin, behind.origin)
        XCTAssertEqual(StackBadgeGeometry.stackMembers(anchor: anchor, among: frames,
                                                      cascadeRange: cascadeRange, tolerance: 4, sizeTolerance: sizeTolerance),
                       [0, 1])
    }

    func testClusterAnchorPrefersDensestClusterThenEarliest() {
        let origins = [CGPoint(x: 8, y: 33), CGPoint(x: 19, y: 33), CGPoint(x: 0, y: 25), CGPoint(x: 30, y: 33)]
        // 0 is in {0, 1} (anchored at 0) and {2, 0} (anchored at 2): a tie,
        // so the earlier anchor wins.
        XCTAssertEqual(StackBadgeGeometry.clusterAnchor(containing: 0, among: origins, cascadeRange: 15, tolerance: 4), 0)
        // 3 is only reachable from 1's cluster {1, 3}, or on its own.
        XCTAssertEqual(StackBadgeGeometry.clusterAnchor(containing: 3, among: origins, cascadeRange: 15, tolerance: 4), 1)
        XCTAssertNil(StackBadgeGeometry.clusterAnchor(containing: 0, among: [], cascadeRange: 15, tolerance: 4))
    }

    // Regression (review finding): limited to one size, an unrelated window
    // near the corner must not become the list's size reference and hide
    // the stack the pointer is on.
    func testSameSizeListIgnoresNeighborNearTheCorner() {
        let neighbor = CGRect(x: 100, y: 105, width: 300, height: 200)
        let stacked = CGRect(x: 120, y: 100, width: 720, height: 875)
        let frames = [neighbor, stacked, stacked.offsetBy(dx: 11, dy: -11)]
        XCTAssertEqual(StackBadgeGeometry.sameSizeStackIndices(among: frames, cascadeRange: cascadeRange, tolerance: 4,
                                                               sizeTolerance: sizeTolerance),
                       [1, 2])
    }

    // Limited to one size, the list shows the stack of the window in front,
    // not a denser group of other sizes behind it.
    func testSameSizeListShowsTheFrontWindowsStack() {
        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let half = CGRect(x: 8, y: 33, width: 712, height: 859)
        let halfInFront = [half, half.offsetBy(dx: 11, dy: 0), maximized, maximized]
        XCTAssertEqual(StackBadgeGeometry.sameSizeStackIndices(among: halfInFront, cascadeRange: cascadeRange, tolerance: 4,
                                                               sizeTolerance: sizeTolerance),
                       [0, 1])
        let maximizedInFront = [maximized, maximized, half, half.offsetBy(dx: 11, dy: 0)]
        XCTAssertEqual(StackBadgeGeometry.sameSizeStackIndices(among: maximizedInFront, cascadeRange: cascadeRange, tolerance: 4,
                                                               sizeTolerance: sizeTolerance),
                       [0, 1])
        XCTAssertTrue(StackBadgeGeometry.sameSizeStackIndices(among: [], cascadeRange: cascadeRange, tolerance: 4,
                                                              sizeTolerance: sizeTolerance).isEmpty)
    }

    func testCascadeRangeMatchesBadgeFormula() {
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 1, tolerance: 4), 15)
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 3, tolerance: 4), 37)
        // Clamped to 1...5 cascade steps, and at least 1pt per step.
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 9, tolerance: 4), 59)
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 11, maxCascade: 0, tolerance: 4), 15)
        XCTAssertEqual(StackBadgeGeometry.cascadeRange(offsetSize: 0, maxCascade: 1, tolerance: 4), 5)
    }

    // MARK: - Ring order

    func testSingleWindowHasNoTarget() {
        XCTAssertNil(StackCycleManager.target(stack: [1], from: 1, previousRing: [], forward: true))
        XCTAssertNil(StackCycleManager.target(stack: [], from: 1, previousRing: [], forward: true))
    }

    func testForwardFirstRaisesBackWindow() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [1, 2, 3], from: 1, previousRing: [], forward: true))
        XCTAssertEqual(result.target, 3)
        XCTAssertEqual(result.ring, [1, 2, 3])
    }

    func testBackwardFirstRaisesWindowBehindFront() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [1, 2, 3], from: 1, previousRing: [], forward: false))
        XCTAssertEqual(result.target, 2)
    }

    /// Simulates presses: each raise moves the target to the front of the
    /// z-order, which is what the next press sees.
    private func walkRing(start: [CGWindowID], presses: Int, forward: Bool) -> [CGWindowID] {
        var zOrder = start
        var ring = [CGWindowID]()
        var raised = [CGWindowID]()
        for _ in 0..<presses {
            guard let result = StackCycleManager.target(stack: zOrder, from: zOrder[0], previousRing: ring, forward: forward) else { break }
            ring = result.ring
            raised.append(result.target)
            zOrder.removeAll { $0 == result.target }
            zOrder.insert(result.target, at: 0)
        }
        return raised
    }

    func testForwardVisitsEveryWindowAndWraps() {
        XCTAssertEqual(walkRing(start: [1, 2, 3], presses: 6, forward: true), [3, 2, 1, 3, 2, 1])
    }

    func testBackwardVisitsEveryWindowAndWraps() {
        // Without the remembered ring this would flip between 1 and 2.
        XCTAssertEqual(walkRing(start: [1, 2, 3], presses: 6, forward: false), [2, 3, 1, 2, 3, 1])
    }

    func testTwoWindowStackToggles() {
        XCTAssertEqual(walkRing(start: [1, 2], presses: 3, forward: true), [2, 1, 2])
        XCTAssertEqual(walkRing(start: [1, 2], presses: 3, forward: false), [2, 1, 2])
    }

    func testChangingDirectionMidCycleStepsBack() throws {
        // Forward from [1, 2, 3] raised 3, so the z-order is [3, 1, 2].
        let next = try XCTUnwrap(StackCycleManager.target(stack: [3, 1, 2], from: 3, previousRing: [1, 2, 3], forward: false))
        XCTAssertEqual(next.target, 1)
    }

    func testRingIsRebuiltWhenStackMembershipChanges() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [4, 2, 1], from: 4, previousRing: [1, 2, 3], forward: true))
        XCTAssertEqual(result.ring, [4, 2, 1])
        XCTAssertEqual(result.target, 1)
    }

    func testRingIsKeptWhenStackMembershipIsUnchanged() throws {
        let result = try XCTUnwrap(StackCycleManager.target(stack: [2, 3, 1], from: 2, previousRing: [1, 2, 3], forward: true))
        XCTAssertEqual(result.ring, [1, 2, 3])
        XCTAssertEqual(result.target, 1)
    }

    func testFrontMissingFromStackHasNoTarget() {
        XCTAssertNil(StackCycleManager.target(stack: [1, 2], from: 9, previousRing: [], forward: true))
    }

    // MARK: - Sessions

    /// A fake window server: frames by id, front to back, plus the stack
    /// rule the manager uses.
    private struct Desk {
        var windows: [(id: CGWindowID, frame: CGRect)]
        var sizeTolerance: CGFloat? = StackBadgeGeometry.sizeTolerance

        func frame(_ id: CGWindowID) -> CGRect { windows.first { $0.id == id }!.frame }

        func stack(at anchor: CGRect) -> [CGWindowID] {
            StackBadgeGeometry.stackMembers(anchor: anchor, among: windows.map { $0.frame },
                                           cascadeRange: 15, tolerance: 4, sizeTolerance: sizeTolerance)
                .map { windows[$0].id }
        }

        mutating func raise(_ id: CGWindowID) {
            let window = windows.first { $0.id == id }!
            windows.removeAll { $0.id == id }
            windows.insert(window, at: 0)
        }

        var front: CGWindowID { windows[0].id }
    }

    private func press(_ desk: Desk, _ session: StackCycleManager.Session?, forward: Bool,
                       raiseInFlight: Bool = false) -> StackCycleManager.Session? {
        guard let anchor = StackBadgeGeometry.stackAnchor(for: 0, among: desk.windows.map { $0.frame },
                                                         cascadeRange: 15, tolerance: 4, sizeTolerance: desk.sizeTolerance)
        else { return nil }
        return StackCycleManager.nextSession(focused: desk.front, freshAnchor: anchor,
                                             previous: session, forward: forward,
                                             raiseInFlight: raiseInFlight, stackFor: desk.stack(at:))
    }

    /// Presses that each land before the next one.
    private func walk(_ desk: Desk, presses: Int, forward: Bool) -> [CGWindowID] {
        var desk = desk
        var session: StackCycleManager.Session?
        var raised = [CGWindowID]()
        for _ in 0..<presses {
            guard let next = press(desk, session, forward: forward) else { break }
            session = next
            raised.append(next.cursor)
            desk.raise(next.cursor)
        }
        return raised
    }

    private func window(_ id: CGWindowID, width: CGFloat) -> (id: CGWindowID, frame: CGRect) {
        (id, CGRect(x: 0, y: 25, width: width, height: 875))
    }

    // Regression (review finding): B is within tolerance of both A and C,
    // but A and C are not of each other. Measuring the stack from each newly
    // raised window dropped C and toggled between A and B forever.
    func testStackAnchorIsFixedForTheSession() {
        let desk = Desk(windows: [window(2, width: 720), window(1, width: 700), window(3, width: 740)])
        XCTAssertEqual(Set(walk(desk, presses: 6, forward: false)), [1, 2, 3])
        XCTAssertEqual(Set(walk(desk, presses: 6, forward: true)), [1, 2, 3])
    }

    func testSessionWalkMatchesRingOrder() {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        XCTAssertEqual(walk(desk, presses: 6, forward: true), [3, 2, 1, 3, 2, 1])
        XCTAssertEqual(walk(desk, presses: 6, forward: false), [2, 3, 1, 2, 3, 1])
    }

    // Regression (review finding): with the pointer over the exposed part of
    // a larger window, that window stays under the pointer as the walk raises
    // a smaller one over it. Counting it as focused skipped it every time.
    func testWalkFromTheWindowUnderThePointerCountsTheStacksFrontWindowAsFocused() throws {
        var desk = Desk(windows: [window(1, width: 900), window(2, width: 720)], sizeTolerance: nil)
        let windowUnderPointer: CGWindowID = 1
        let anchor = try XCTUnwrap(StackBadgeGeometry.stackAnchor(for: 0, among: desk.windows.map { $0.frame },
                                                                 cascadeRange: 15, tolerance: 4, sizeTolerance: nil))
        var session: StackCycleManager.Session?
        var raised = [CGWindowID]()
        for _ in 0..<4 {
            let focus = try XCTUnwrap(StackCycleManager.sessionFocus(window: windowUnderPointer, isFocused: false,
                                                                     stack: desk.stack(at: anchor)))
            let next = try XCTUnwrap(StackCycleManager.nextSession(focused: focus, freshAnchor: anchor, previous: session,
                                                                   forward: true, stackFor: desk.stack(at:)))
            session = next
            raised.append(next.cursor)
            desk.raise(next.cursor)
        }

        XCTAssertEqual(raised, [2, 1, 2, 1])
        XCTAssertEqual(StackCycleManager.sessionFocus(window: windowUnderPointer, isFocused: true, stack: [2, 1]), windowUnderPointer)
    }

    // Regression (review finding): a second press made before the first
    // raise lands still sees the old front window, and must advance past the
    // first target instead of choosing it again.
    func testPressBeforeRaiseLandsStillAdvances() throws {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let first = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(first.cursor, 3)
        let second = try XCTUnwrap(press(desk, first, forward: true, raiseInFlight: true))
        XCTAssertEqual(second.cursor, 2)
    }

    // Two quick presses on a two-window stack come back to the start: while
    // the first raise is in flight, the stale front window is not skipped.
    func testDoublePressOnTwoWindowStackReturnsToStart() throws {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720)])
        let first = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(first.cursor, 2)
        let second = try XCTUnwrap(press(desk, first, forward: true, raiseInFlight: true))
        XCTAssertEqual(second.cursor, 1)
    }

    // A window that never comes forward is stepped past, not retried forever.
    func testRefusedRaiseIsSteppedPast() throws {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        var session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        // Window 2 refused to come forward; 1 is still in front.
        session = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(session.cursor, 3)
    }

    // Regression (review finding): with four windows, the first of two
    // queued raises landing put an intermediate window in front, which read
    // as the user focusing it and restarted the walk on the same target.
    func testPartialRaiseCompletionStillAdvances() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720), window(4, width: 720)])
        let first = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(first.cursor, 4)
        let second = try XCTUnwrap(press(desk, first, forward: true, raiseInFlight: true))
        XCTAssertEqual(second.cursor, 3)
        desk.raise(4)                               // only the first raise has landed
        let third = try XCTUnwrap(press(desk, second, forward: true, raiseInFlight: true))
        XCTAssertEqual(third.cursor, 2)
    }

    // Focus moving between the stack's own windows, by a raise landing or by
    // hand, keeps the walk going from where the presses left it.
    func testFocusWithinStackKeepsWalking() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        desk.raise(2)
        desk.raise(1)                               // user clicks 1
        let next = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(next.cursor, 3)
        XCTAssertEqual(next.ring, [1, 2, 3])
    }

    // Regression (review finding): when the walk reaches the window the user
    // already brought forward by hand, it steps past it rather than
    // re-raising it, which would look like the press did nothing.
    func testWalkSkipsWindowAlreadyInFront() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        desk.raise(2)
        desk.raise(3)                               // user clicks 3, next in the walk
        let next = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(next.cursor, 1)
    }

    // Focusing a window outside the stack ends the session, so the next
    // press starts from that window's own stack.
    func testFocusingAnotherStackStartsNewSession() throws {
        let rightHalf = { (id: CGWindowID) in (id: id, frame: CGRect(x: 720, y: 25, width: 720, height: 875)) }
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), rightHalf(3), rightHalf(4)])
        let left = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(left.cursor, 2)
        desk.raise(4)                               // user clicks the right half
        let right = try XCTUnwrap(press(desk, left, forward: true))
        XCTAssertEqual(right.ring, [4, 3])
        XCTAssertEqual(right.cursor, 3)
    }

    func testClosedTargetCarriesOnFromFocusedWindow() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 720)])
        let session = try XCTUnwrap(press(desk, nil, forward: false))
        XCTAssertEqual(session.cursor, 2)
        desk.windows.removeAll { $0.id == 2 }       // closed before it came forward
        let next = try XCTUnwrap(press(desk, session, forward: false))
        XCTAssertEqual(next.cursor, 3)
    }

    func testAnySizeCyclesMaximizedWindowWithHalf() {
        let desk = Desk(windows: [window(1, width: 1440), window(2, width: 720)], sizeTolerance: nil)
        XCTAssertEqual(walk(desk, presses: 4, forward: true), [2, 1, 2, 1])
    }

    func testNoSessionWithoutAStack() {
        let desk = Desk(windows: [window(1, width: 720), window(2, width: 1440)])
        XCTAssertNil(press(desk, nil, forward: true))
    }

    func testMovedFocusedWindowStartsNewSession() throws {
        var desk = Desk(windows: [window(1, width: 720), window(2, width: 720), window(3, width: 1440), window(4, width: 1440)])
        let session = try XCTUnwrap(press(desk, nil, forward: true))
        XCTAssertEqual(session.cursor, 2)
        desk.raise(2)
        // Window 2 is maximized: it now belongs to the maximized stack.
        desk.windows[0] = window(2, width: 1440)
        let next = try XCTUnwrap(press(desk, session, forward: true))
        XCTAssertEqual(Set(next.ring), [2, 3, 4])
    }

    // MARK: - Action wiring

    func testActionsAreActiveAndReachableByUrlName() {
        XCTAssertTrue(WindowAction.active.contains(.cycleStackedWindows))
        XCTAssertTrue(WindowAction.active.contains(.cycleStackedWindowsBackward))
        XCTAssertEqual(WindowAction.cycleStackedWindows.name, "cycleStackedWindows")
        XCTAssertEqual(WindowAction.cycleStackedWindowsBackward.name, "cycleStackedWindowsBackward")
    }

    func testActionsHaveSettingsTitlesButStayOutOfMenu() {
        for action in [WindowAction.cycleStackedWindows, .cycleStackedWindowsBackward] {
            XCTAssertNotNil(action.displayName)
            XCTAssertTrue(action.excludedFromMenu)
            XCTAssertFalse(action.positionCycles)
            XCTAssertFalse(action.overlapOffsetApplies)
            XCTAssertFalse(action.isDragSnappable)
        }
    }
}

/// The cascade math itself. Asserting the resulting rect matters: an earlier
/// version of this feature was certified by a test that only checked an
/// eligibility flag, while the offset it enabled was a no-op for anyone
/// running the default of no gaps.
class OverlapOffsetGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let offset: CGFloat = 11

    private func cascade(_ rect: CGRect, occupied: [CGPoint], maxCascade: Int = 1) -> CGRect {
        OverlapOffsetGeometry.cascadedRect(rect,
                                           occupiedTopLefts: occupied,
                                           screenFrame: screen,
                                           offset: offset,
                                           maxCascade: maxCascade)
    }

    /// A maximized window with no gaps fills the visible frame, so there is
    /// nowhere to shift it - and the caller skips the window scan entirely.
    func testMaximizedWithoutGapsCannotOffset() {
        let maximized = screen
        XCTAssertFalse(OverlapOffsetGeometry.canOffset(maximized, in: screen, by: offset))
        XCTAssertEqual(cascade(maximized, occupied: [OverlapOffsetGeometry.topLeft(of: maximized)]),
                       maximized)
    }

    /// Gaps larger than the offset leave room, so maximized windows cascade.
    func testMaximizedWithGapsOffsets() {
        let maximized = CGRect(x: 22, y: 22, width: 956, height: 756)
        XCTAssertTrue(OverlapOffsetGeometry.canOffset(maximized, in: screen, by: offset))
        XCTAssertEqual(cascade(maximized, occupied: [OverlapOffsetGeometry.topLeft(of: maximized)]),
                       CGRect(x: 33, y: 33, width: 956, height: 756))
    }

    /// Gaps smaller than the offset must not shift the window part way: it
    /// would end up flush against the far edges, deleting the gaps there.
    func testGapsSmallerThanOffsetDoNotOffset() {
        let maximized = CGRect(x: 5, y: 5, width: 990, height: 790)
        XCTAssertFalse(OverlapOffsetGeometry.canOffset(maximized, in: screen, by: offset))
        XCTAssertEqual(cascade(maximized, occupied: [OverlapOffsetGeometry.topLeft(of: maximized)]),
                       maximized)
    }

    /// A half with no gaps has room across but not up, and still offsets on
    /// the axis that fits - the behavior shipped in v0.96.
    func testHalfOffsetsOnTheAxisWithRoom() {
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800)
        XCTAssertEqual(cascade(leftHalf, occupied: [OverlapOffsetGeometry.topLeft(of: leftHalf)]),
                       CGRect(x: 11, y: 0, width: 500, height: 800))
    }

    func testNoOverlapLeavesTheRectAlone() {
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 800)
        XCTAssertEqual(cascade(leftHalf, occupied: [CGPoint(x: 500, y: 800)]), leftHalf)
    }

    func testCascadeStopsAtMaxCascade() {
        let quarter = CGRect(x: 0, y: 0, width: 400, height: 400)
        let occupied = [CGPoint(x: 0, y: 400), CGPoint(x: 11, y: 411), CGPoint(x: 22, y: 422)]
        XCTAssertEqual(cascade(quarter, occupied: occupied, maxCascade: 1).origin,
                       CGPoint(x: 11, y: 11))
        XCTAssertEqual(cascade(quarter, occupied: occupied, maxCascade: 3).origin,
                       CGPoint(x: 33, y: 33))
    }

    /// Matching is by top-left corner, so a smaller window landing on a larger
    /// one at the same corner counts as an overlap - an eighth arriving on a
    /// quarter. Both sit against the top of the screen here, so the window
    /// offsets across but not up.
    func testMatchesMixedSizesAtTheSameCorner() {
        let eighth = CGRect(x: 0, y: 600, width: 250, height: 200)
        let quarterTopLeft = OverlapOffsetGeometry.topLeft(of: CGRect(x: 0, y: 400, width: 500, height: 400))
        XCTAssertEqual(quarterTopLeft, OverlapOffsetGeometry.topLeft(of: eighth))
        XCTAssertEqual(cascade(eighth, occupied: [quarterTopLeft]),
                       CGRect(x: 11, y: 600, width: 250, height: 200))
    }

    func testCoversScreen() {
        XCTAssertTrue(OverlapOffsetGeometry.coversScreen(screen, screenFrame: screen))
        XCTAssertTrue(OverlapOffsetGeometry.coversScreen(CGRect(x: 22, y: 22, width: 956, height: 756),
                                                         screenFrame: screen))
        XCTAssertFalse(OverlapOffsetGeometry.coversScreen(CGRect(x: 0, y: 0, width: 500, height: 800),
                                                          screenFrame: screen))
    }
}

/// Which actions are eligible for the overlap offset. `positionCycles` alone
/// excluded maximize, so two maximized windows landed exactly on top of each
/// other. Eligibility is only half of it - whether an eligible window actually
/// moves is covered by OverlapOffsetGeometryTests.
class OverlapOffsetEligibilityTests: XCTestCase {

    func testMaximizeGetsTheOffset() {
        XCTAssertTrue(WindowAction.maximize.overlapOffsetApplies)
    }

    func testGridPositionsGetTheOffset() {
        for action in [WindowAction.leftHalf, .topLeft, .topLeftSixth,
                       .topLeftNinth, .topLeftEighth, .topLeftTwelfth, .topLeftSixteenth] {
            XCTAssertTrue(action.overlapOffsetApplies, "\(action) should get the overlap offset")
        }
    }

    /// Actions that move or resize in place have no "landed on top of
    /// something" notion, so offsetting them would just displace the window.
    func testMovesAndResizesDoNotGetTheOffset() {
        for action in [WindowAction.center, .restore, .moveLeft, .moveRight, .moveUp, .moveDown,
                       .larger, .smaller, .nextDisplay, .previousDisplay,
                       .almostMaximize, .maximizeHeight, .tileAll, .cascadeAll] {
            XCTAssertFalse(action.overlapOffsetApplies, "\(action) should not get the overlap offset")
        }
    }
}

/// The stacked-window list is driven by an event tap, so it decides which
/// keystrokes to take from the app underneath. Taking the wrong ones would
/// break typing system-wide while the list is open.
class StackBadgeKeyHandlingTests: XCTestCase {

    /// The flags macOS actually puts on an arrow keystroke. Every arrow event
    /// carries them, so a test that passes an empty modifier set is asserting
    /// against an event the system never delivers - which is exactly how a
    /// guard that rejected .function shipped with the suite green.
    private static let arrowFlags: NSEvent.ModifierFlags = [.function, .numericPad]

    private func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> StackBadgeManager.NavigationKey? {
        StackBadgeManager.navigationKey(forKeyCode: code, modifiers: modifiers)
    }

    func testNavigationKeysAreClaimed() {
        XCTAssertEqual(key(UInt16(kVK_UpArrow), Self.arrowFlags), .up)
        XCTAssertEqual(key(UInt16(kVK_DownArrow), Self.arrowFlags), .down)
        XCTAssertEqual(key(UInt16(kVK_Return)), .commit)
        XCTAssertEqual(key(UInt16(kVK_ANSI_KeypadEnter), .numericPad), .commit)
        XCTAssertEqual(key(UInt16(kVK_Escape)), .escape)
    }

    /// Caps lock is not something the user is holding for this keystroke, and
    /// a window list that stops navigating because caps lock is on would be
    /// its own bug report.
    func testCapsLockStillNavigates() {
        XCTAssertEqual(key(UInt16(kVK_UpArrow), Self.arrowFlags.union(.capsLock)), .up)
    }

    func testOrdinaryKeysArePassedThrough() {
        for code in [kVK_ANSI_A, kVK_ANSI_Q, kVK_Tab, kVK_Space, kVK_Delete, kVK_PageUp, kVK_Home] {
            XCTAssertNil(key(UInt16(code)), "keyCode \(code) must reach the app underneath")
        }
        for code in [kVK_LeftArrow, kVK_RightArrow] {
            XCTAssertNil(key(UInt16(code), Self.arrowFlags),
                         "keyCode \(code) must reach the app underneath")
        }
    }

    /// A held modifier means the keystroke belongs to the frontmost app. Shift
    /// is included deliberately: shift-return inserts a newline in chat apps
    /// and shift-arrow extends a selection, so claiming those would break
    /// ordinary typing whenever the list happened to be open. The arrow cases
    /// carry the flags macOS sends, so the modifier under test is the only
    /// difference from a keystroke that must be claimed.
    func testModifiedKeysArePassedThrough() {
        for modifier in [NSEvent.ModifierFlags.command, .option, .control, .shift] {
            for code in [kVK_UpArrow, kVK_DownArrow] {
                XCTAssertNil(key(UInt16(code), Self.arrowFlags.union(modifier)),
                             "arrow \(code) with \(modifier) must reach the app underneath")
            }
            for code in [kVK_Return, kVK_Escape] {
                XCTAssertNil(key(UInt16(code), modifier),
                             "keyCode \(code) with \(modifier) must reach the app underneath")
            }
        }
        XCTAssertNil(key(UInt16(kVK_UpArrow), Self.arrowFlags.union([.command, .option])))
        XCTAssertNil(key(UInt16(kVK_Return), [.shift]))
    }

    func testSelectionClampsAtBothEnds() {
        XCTAssertEqual(StackBadgeManager.selection(from: 0, movedBy: -1, count: 4), 0)
        XCTAssertEqual(StackBadgeManager.selection(from: 3, movedBy: 1, count: 4), 3)
        XCTAssertEqual(StackBadgeManager.selection(from: 1, movedBy: 1, count: 4), 2)
        XCTAssertEqual(StackBadgeManager.selection(from: 1, movedBy: -1, count: 4), 0)
    }

    func testSelectionWithNoRowsIsNil() {
        XCTAssertNil(StackBadgeManager.selection(from: 0, movedBy: 1, count: 0))
    }

    /// Rows that would be clipped are never built, so the arrow keys can't
    /// select - and Return can't raise - a window with no visible row.
    func testRowsThatFitIsBoundedByTheScreenBottom() {
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 500, above: 0), 22)
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 60, above: 0), 2)
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 10, above: 0), 0)
        XCTAssertEqual(StackBadgeManager.rowsThatFit(below: 0, above: 100), 0)
    }
}

/// Which windows at a shared corner count as one stack. A window covering the
/// screen shares its corner with every half and corner placement, so it can
/// only join a stack, never create one - otherwise an everyday layout (one
/// maximized window, one tiled to the left half) reads as a stack of two.
/// Size plays no part in stack membership. A window pegged to the corner is in
/// the stack whether it is maximized or a sixteenth - and a maximized window
/// sitting on a smaller one is the case where the smaller window cannot be
/// seen any other way, which is what the list exists to reveal.
///
/// The list briefly excluded screen-covering windows, borrowed from the
/// overlap offset where the exclusion is necessary (a maximized window shares
/// its origin with every placement and would otherwise shift them all, #1766).
/// The list moves nothing, so it never needed it, and the exclusion made a
/// maximized window over a half-screen window show no list at all.
class StackBadgeSizeAgnosticTests: XCTestCase {

    private let corner = CGPoint(x: 0, y: 0)
    private let cascaded = CGPoint(x: 11, y: -11)

    private func stack(_ origins: [CGPoint]) -> [Int] {
        StackBadgeGeometry.stackIndices(among: origins, cascadeRange: 15, tolerance: 4)
    }

    /// The reported case: one maximized window over one half-screen window,
    /// both pegged to the same corner, showed nothing at all.
    func testMaximizedOverTiledIsAStack() {
        XCTAssertEqual(stack([corner, corner]).sorted(), [0, 1])
    }

    /// The maximized windows carry the overlap offset, so they sit a cascade
    /// step forward of the tiled window they hide.
    func testOffsetMaximizedWindowsStillIncludeTheTiledOneBeneath() {
        XCTAssertEqual(stack([cascaded, cascaded, corner]).sorted(), [0, 1, 2])
    }

    func testSeveralMaximizedWindowsAreAStack() {
        XCTAssertEqual(stack([corner, cascaded]).count, 2)
    }

    func testTiledStackIsUnaffected() {
        XCTAssertEqual(stack([corner, cascaded]).count, 2)
    }

    /// This returns the densest cluster, which for a single window is that
    /// window; the caller is what requires two before showing anything.
    func testLoneWindowIsItsOwnClusterAndTheCallerRejectsIt() {
        XCTAssertEqual(stack([corner]), [0])
    }

    func testWindowAtAnotherCornerIsNotInTheCluster() {
        XCTAssertEqual(stack([corner, CGPoint(x: 900, y: 0)]).count, 1)
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

final class StackBadgeListSelectionTests: XCTestCase {
    private let windows = [StackBadgeStackedWindow(windowId: 11, pid: 1, title: "backchannel"),
                           StackBadgeStackedWindow(windowId: 22, pid: 1, title: "dead"),
                           StackBadgeStackedWindow(windowId: 33, pid: 1, title: "Rectangle")]

    private func panel(selecting id: CGWindowID?) -> StackBadgeListPanel {
        StackBadgeListPanel(windows: windows, selectedWindowId: id,
                            listTop: CGPoint(x: 100, y: 800),
                            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                            onSelect: { _ in }, onDismiss: {}, onLostKey: {})
    }

    // The front window of the stack sorts to the last row here; the list
    // still opens with it highlighted.
    func testOpensOnTheFrontWindowWhereverItSorts() {
        XCTAssertEqual(panel(selecting: 33).selectedWindow?.windowId, 33)
    }

    func testFallsBackToTheFirstRowWhenTheFrontWindowIsNotListed() {
        XCTAssertEqual(panel(selecting: 99).selectedWindow?.windowId, 11)
        XCTAssertEqual(panel(selecting: nil).selectedWindow?.windowId, 11)
    }

    func testArrowKeysMoveFromTheFrontWindow() {
        let list = panel(selecting: 22)
        list.moveSelection(by: 1)
        XCTAssertEqual(list.selectedWindow?.windowId, 33)
    }
}
