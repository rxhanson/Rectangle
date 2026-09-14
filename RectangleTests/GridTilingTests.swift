import XCTest
import CoreGraphics
@testable import Rectangle

final class GridTilingTests: XCTestCase {
    private typealias State = GridTiling.State<Int>
    private let bounds = GridTiling.Bounds(CGRect(x: -800, y: 34, width: 701, height: 503))

    private func unrestricted(_ count: Int, bounds: GridTiling.Bounds) -> [GridTiling.WindowConstraints] {
        Array(repeating: GridTiling.WindowConstraints(
            width: .resizable(minimum: 0, maximum: bounds.extent(.columns)),
            height: .resizable(minimum: 0, maximum: bounds.extent(.rows))), count: count)
    }

    private func press(_ frames: [CGRect], direction: GridTiling.Direction, limit: Int = 3,
                       previous: State? = nil, in bounds: GridTiling.Bounds? = nil,
                       windows: [Int]? = nil) -> State {
        let bounds = bounds ?? self.bounds
        return GridTiling.perform(windows: windows ?? Array(frames.indices), observedFrames: frames,
                                  bounds: bounds, direction: direction, limit: limit,
                                  constraints: unrestricted(frames.count, bounds: bounds), previous: previous,
                                  setFrame: { _, frame in frame })
    }

    private func frames(_ state: State) -> [CGRect] {
        state.frames.keys.sorted().map { state.frames[$0]! }
    }

    private func assertGrid(_ frames: [CGRect], populations: [Int], direction: GridTiling.Direction,
                            in bounds: GridTiling.Bounds? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = bounds ?? self.bounds
        let groups = Dictionary(grouping: frames, by: { direction == .columns ? $0.minX : -$0.maxY })
        let ordered = groups.keys.sorted().map { groups[$0]! }
        XCTAssertEqual(ordered.map(\.count), populations, file: file, line: line)
        XCTAssertEqual(frames.reduce(CGRect.null) { $0.union($1) }, bounds.rect, file: file, line: line)
        XCTAssertEqual(frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height },
                       bounds.rect.width * bounds.rect.height, file: file, line: line)
        let breadths = ordered.map { direction == .columns ? $0[0].width : $0[0].height }
        XCTAssertLessThanOrEqual(breadths.max()! - breadths.min()!, 1, file: file, line: line)
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertTrue(frames[i].intersection(frames[j]).isEmpty, file: file, line: line)
            }
        }
    }

    // Verifies: Each distinct stage fills the area with balanced populations.
    // Catches: Duplicate stages, unplaced remainders, and rounding gaps.
    func testDistinctCyclesUseEveryPixelAndBalanceRemaindersInBothOrientations() {
        let cases = [(3, [[1, 1, 1], [2, 1], [3], [1, 1, 1]]),
                     (4, [[1, 1, 1, 1], [2, 2], [1, 1, 1, 1]]),
                     (5, [[1, 1, 1, 1, 1], [2, 2, 1], [3, 2], [1, 1, 1, 1, 1]]),
                     (6, [[1, 1, 1, 1, 1, 1], [2, 2, 2], [3, 3], [1, 1, 1, 1, 1, 1]]),
                     (7, [[1, 1, 1, 1, 1, 1, 1], [2, 2, 2, 1], [3, 2, 2], [1, 1, 1, 1, 1, 1, 1]])]
        for direction in [GridTiling.Direction.rows, .columns] {
            for (count, sequence) in cases {
                var observed = Array(repeating: CGRect(x: 19, y: 23, width: 81, height: 67), count: count)
                var state: State?
                for populations in sequence {
                    state = press(observed, direction: direction, previous: state)
                    observed = frames(state!)
                    assertGrid(observed, populations: populations, direction: direction)
                }
            }
        }
    }

    // Verifies: A manual move reapplies the active stage in current spatial order.
    // Catches: Stale window order and accidental advancement after a move.
    func testManualMoveReappliesStageUsingTheNewWindowOrder() {
        for direction in [GridTiling.Direction.rows, .columns] {
            let initial = press(Array(repeating: .zero, count: 5), direction: direction)
            let second = press(frames(initial), direction: direction, previous: initial)
            var moved = second.frames
            moved[0] = second.frames[4]!.offsetBy(dx: 7, dy: 11)
            moved[4] = second.frames[0]
            let order = [4, 1, 2, 3, 0]
            let reapplied = press(order.map { moved[$0]! }, direction: direction, previous: second, windows: order)
            XCTAssertEqual(reapplied.subdivision, 2)
            XCTAssertEqual(reapplied.frames[4], second.frames[0])
            let advanced = press(order.map { reapplied.frames[$0]! }, direction: direction,
                                 previous: reapplied, windows: order)
            XCTAssertEqual(advanced.subdivision, 3)
            assertGrid(Array(advanced.frames.values), populations: [3, 2], direction: direction)
        }
    }

    // Verifies: Membership changes retain the active subdivision.
    // Catches: Resetting or advancing when a window opens or closes.
    func testAddedAndClosedWindowsReapplyTheActiveSubdivision() {
        for direction in [GridTiling.Direction.rows, .columns] {
            let first = press(Array(repeating: .zero, count: 5), direction: direction)
            let second = press(frames(first), direction: direction, previous: first)
            let added = press(frames(second) + [.zero], direction: direction, previous: second)
            XCTAssertEqual(added.subdivision, 2)
            assertGrid(frames(added), populations: [2, 2, 2], direction: direction)
            let third = press(frames(added), direction: direction, previous: added)
            XCTAssertEqual(third.subdivision, 3)
            let closed = press(Array(frames(third).prefix(5)), direction: direction, previous: third)
            XCTAssertEqual(closed.subdivision, 3)
            assertGrid(frames(closed), populations: [3, 2], direction: direction)
        }
    }

    // Verifies: New gaps and lower limits govern the next placement.
    // Catches: Reusing stale bounds or an out-of-range stage.
    func testChangedBoundsAndLimitsReapplyBeforeAdvancing() {
        for direction in [GridTiling.Direction.rows, .columns] {
            let first = press(Array(repeating: .zero, count: 6), direction: direction)
            let second = press(frames(first), direction: direction, previous: first)
            let inset = GridTiling.Bounds(bounds.rect.insetBy(dx: 17, dy: 13))
            let adjusted = press(frames(second), direction: direction, previous: second, in: inset)
            XCTAssertEqual(adjusted.subdivision, 2)
            assertGrid(frames(adjusted), populations: [2, 2, 2], direction: direction, in: inset)
            let third = press(frames(adjusted), direction: direction, previous: adjusted, in: inset)
            XCTAssertEqual(third.subdivision, 3)
            let limited = press(frames(third), direction: direction, limit: 2, previous: third, in: inset)
            XCTAssertEqual(limited.subdivision, 2)
            XCTAssertEqual(press(frames(limited), direction: direction, limit: 2,
                                 previous: limited, in: inset).subdivision, 1)
        }
    }

    // Verifies: Intact geometry can advance without remembered state.
    // Catches: Guessing a stage from arbitrary or differently oriented frames.
    func testRecognitionWithoutHistoryAdvancesOnlyAnIntactGrid() {
        for direction in [GridTiling.Direction.rows, .columns] {
            let first = press(Array(repeating: .zero, count: 3), direction: direction)
            let second = press(frames(first), direction: direction, previous: first)
            XCTAssertEqual(press(frames(second), direction: direction).subdivision, 3)
            var edited = frames(second)
            edited[0] = edited[0].offsetBy(dx: 11, dy: 7)
            XCTAssertEqual(press(edited, direction: direction).subdivision, 1)
            let switched = press(frames(second), direction: direction.cross, previous: second)
            XCTAssertEqual(switched.subdivision, 1)
        }
    }

    // Verifies: One disables cycling and excess subdivisions add no stages.
    // Catches: Phantom stages and incorrect cycles when the configured limit is two.
    func testLimitsOfOneTwoAndMoreThanWindowCount() {
        for direction in [GridTiling.Direction.rows, .columns] {
            let first = press(Array(repeating: .zero, count: 3), direction: direction, limit: 2)
            let second = press(frames(first), direction: direction, limit: 2, previous: first)
            assertGrid(frames(second), populations: [2, 1], direction: direction)
            let wrapped = press(frames(second), direction: direction, limit: 2, previous: second)
            XCTAssertEqual(wrapped.subdivision, 1)
            XCTAssertEqual(press(frames(first), direction: direction, limit: 1).frames, first.frames)
            XCTAssertEqual(GridTiling.subdivisions(windowCount: 3, limit: Int.max), [1, 2, 3])
            let only = press([.zero], direction: direction, limit: Int.max)
            XCTAssertEqual(press(frames(only), direction: direction, previous: only).frames, only.frames)
        }
    }

    // Verifies: Minimum breadths preserve a feasible full-area allocation.
    // Catches: Insisting on equal groups when a 600/400 split is required.
    func testMinimumBreadthOverridesEqualityAndFillsRemainingSpace() {
        let bounds = GridTiling.Bounds(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        for direction in [GridTiling.Direction.rows, .columns] {
            var limits = unrestricted(5, bounds: bounds)
            limits[0][direction] = .resizable(minimum: 600, maximum: 1000)
            limits[3][direction] = .resizable(minimum: 200, maximum: 1000)
            let grid = GridTiling.layout(bounds: bounds, direction: direction, subdivision: 3, constraints: limits)
            XCTAssertTrue(grid.feasible)
            let breadths = grid.frames.map { direction == .columns ? $0.width : $0.height }
            XCTAssertEqual(breadths, [600, 600, 600, 400, 400])
            XCTAssertEqual(grid.frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height }, 1_000_000)
        }
    }

    // Verifies: Achieved sizes constrain both group breadth and interior spacing.
    // Catches: Adjusting only one grid axis after an app clamps its frame.
    func testObservedClampsRedistributeBothGroupBreadthAndInteriorSpace() {
        let bounds = GridTiling.Bounds(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let result = GridTiling.apply(observedFrames: Array(repeating: .zero, count: 4), bounds: bounds,
                                      direction: .columns, subdivision: 2,
                                      constraints: unrestricted(4, bounds: bounds)) { index, requested in
            var frame = requested
            if index == 0 {
                frame.size.width = max(600, frame.width)
                frame.size.height = max(700, frame.height)
            }
            return frame
        }
        XCTAssertEqual(result, [CGRect(x: 0, y: 300, width: 600, height: 700),
                                CGRect(x: 0, y: 0, width: 600, height: 300),
                                CGRect(x: 600, y: 500, width: 400, height: 500),
                                CGRect(x: 600, y: 0, width: 400, height: 500)])
    }

    // Verifies: Refused layouts advance within one bounded invocation.
    // Catches: Wasted presses and unbounded attempts when all layouts are refused.
    func testAStageThatAppsLeaveUnchangedIsSkippedInTheSameInvocation() {
        let bounds = GridTiling.Bounds(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let observed = Array(repeating: CGRect(x: 20, y: 20, width: 600, height: 1000), count: 2)
        let state = GridTiling.perform(windows: [0, 1], observedFrames: observed, bounds: bounds,
                                       direction: .columns, limit: 2,
                                       constraints: unrestricted(2, bounds: bounds), previous: nil) { index, frame in
            frame.height == 1000 ? observed[index] : frame
        }
        XCTAssertEqual(state.subdivision, 2)
        XCTAssertEqual(frames(state).map(\.height), [500, 500])

        var requests = 0
        let refused = GridTiling.perform(windows: [0, 1], observedFrames: observed, bounds: bounds,
                                         direction: .columns, limit: 2,
                                         constraints: unrestricted(2, bounds: bounds), previous: nil) { index, _ in
            requests += 1
            return observed[index]
        }
        XCTAssertEqual(frames(refused), observed)
        XCTAssertLessThanOrEqual(requests, 8)
    }
}
