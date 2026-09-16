import Foundation
import CoreGraphics

/// Backing-pixel layouts and on-demand cycling. Window discovery and AX writes
/// remain with MultiWindowManager; the frame callback returns what the app accepted.
/// Callers supply a nonempty, spatially ordered window set and positive bounds.
enum GridTiling {
    enum Direction: Hashable {
        case rows, columns

        var cross: Direction { self == .rows ? .columns : .rows }
    }

    enum Constraint: Equatable {
        case fixed(Int)
        case resizable(minimum: Int, maximum: Int)

        var lowerBound: Int {
            switch self {
            case .fixed(let size): return max(0, size)
            case .resizable(let minimum, _): return max(0, minimum)
            }
        }

        var upperBound: Int {
            switch self {
            case .fixed(let size): return max(0, size)
            case .resizable(_, let maximum): return max(0, maximum)
            }
        }

        func observing(achieved: Int, requested: Int) -> Constraint {
            switch self {
            case .fixed:
                return self
            case .resizable(let minimum, let maximum):
                let lower = achieved > requested ? max(minimum, achieved) : minimum
                let upper = achieved < requested ? min(maximum, achieved) : maximum
                return lower <= upper ? .resizable(minimum: lower, maximum: upper) : self
            }
        }
    }

    struct WindowConstraints: Equatable {
        var width: Constraint
        var height: Constraint

        subscript(_ direction: Direction) -> Constraint {
            get { direction == .rows ? height : width }
            set {
                if direction == .rows { height = newValue } else { width = newValue }
            }
        }
    }

    struct Bounds: Equatable {
        let left: Int
        let right: Int
        let bottom: Int
        let top: Int

        init(_ frame: CGRect) {
            left = Int(frame.minX.rounded())
            right = Int(frame.maxX.rounded())
            bottom = Int(frame.minY.rounded())
            top = Int(frame.maxY.rounded())
        }

        func extent(_ direction: Direction) -> Int {
            direction == .rows ? top - bottom : right - left
        }

        var rect: CGRect { CGRect(x: left, y: bottom, width: right - left, height: top - bottom) }
    }

    struct Layout {
        let frames: [CGRect]
        let feasible: Bool
    }

    /// One display's last action, held only in memory. Keeping window identities
    /// with achieved frames distinguishes a repeat from a moved or replaced window.
    struct State<Window: Hashable> {
        let direction: Direction
        let subdivision: Int
        let bounds: Bounds
        let frames: [Window: CGRect]
    }

    /// Enumerate distinct group counts; neighboring limits can describe the same grid.
    static func subdivisions(windowCount: Int, limit: Int) -> [Int] {
        var result = [Int]()
        var previousGroupCount = 0
        for subdivision in 1...min(windowCount, max(1, limit)) {
            let groupCount = 1 + (windowCount - 1) / subdivision
            if groupCount != previousGroupCount {
                result.append(subdivision)
                previousGroupCount = groupCount
            }
        }
        return result
    }

    /// Partition the work area across balanced groups and then within each group.
    /// When size restrictions cannot all fit, return equal targets marked infeasible.
    static func layout(bounds: Bounds, direction: Direction, subdivision: Int,
                       constraints: [WindowConstraints]) -> Layout {
        let count = constraints.count
        let groupCount = 1 + (count - 1) / subdivision
        var offset = 0
        let groups = (0..<groupCount).map { index -> Range<Int> in
            let population = count / groupCount + (index < count % groupCount ? 1 : 0)
            let range = offset..<(offset + population)
            offset += population
            return range
        }
        // Every member shares its group's breadth, so their permitted ranges
        // intersect. Population never determines the breadth of a group.
        let groupConstraints = groups.map { group -> Constraint in
            let limits = group.map { constraints[$0][direction] }
            return .resizable(minimum: limits.map(\.lowerBound).max()!,
                              maximum: limits.map(\.upperBound).min()!)
        }
        let breadths = balancedBandLengths(totalPixels: bounds.extent(direction), constraints: groupConstraints)
        let groupFrames = backingBandRects(bounds: bounds, lengths: breadths.lengths, direction: direction)
        var frames = [CGRect]()
        var feasible = breadths.feasible
        for (group, frame) in zip(groups, groupFrames) {
            let lengths = balancedBandLengths(totalPixels: bounds.extent(direction.cross),
                                              constraints: group.map { constraints[$0][direction.cross] })
            frames.append(contentsOf: backingBandRects(bounds: Bounds(frame), lengths: lengths.lengths,
                                                       direction: direction.cross))
            feasible = feasible && lengths.feasible
        }
        return Layout(frames: frames, feasible: feasible)
    }

    /// Choose and apply a stage in one invocation. A would-be no-op advances now;
    /// edited windows, settings, or membership otherwise reapply the active stage.
    static func perform<Window: Hashable>(windows: [Window], observedFrames: [CGRect], bounds: Bounds,
                                         direction: Direction, limit: Int,
                                         constraints: [WindowConstraints], previous: State<Window>?,
                                         setFrame: (Int, CGRect) -> CGRect) -> State<Window> {
        let stages = subdivisions(windowCount: windows.count, limit: limit)
        let maximum = min(windows.count, max(1, limit))
        let active: Int
        var advance = false
        if let previous = previous, previous.direction == direction {
            active = min(previous.subdivision, maximum)
            let sameResult = previous.bounds == bounds && previous.subdivision <= maximum
                && previous.frames.count == windows.count
                && zip(windows, observedFrames).allSatisfy { previous.frames[$0.0] == $0.1 }
            let intended = layout(bounds: bounds, direction: direction, subdivision: active, constraints: constraints)
            advance = sameResult || intended.frames == observedFrames
        } else {
            let matches = stages.filter { stage in
                let candidate = layout(bounds: bounds, direction: direction, subdivision: stage, constraints: constraints)
                return candidate.feasible && candidate.frames == observedFrames
            }
            active = matches.count == 1 ? matches[0] : 1
            advance = matches.count == 1
        }

        let groupCount = 1 + (windows.count - 1) / active
        let index = stages.firstIndex { 1 + (windows.count - 1) / $0 == groupCount }!
        // Preserve the actual subdivision across a changed set, even when it
        // currently has the same grouping as an earlier candidate.
        let candidates = (0..<stages.count).map { step in
            step == 0 && !advance ? active : stages[(index + step + (advance ? 1 : 0)) % stages.count]
        }
        var achieved = observedFrames
        var chosen = active
        for stage in candidates {
            achieved = apply(observedFrames: achieved, bounds: bounds, direction: direction,
                             subdivision: stage, constraints: constraints, setFrame: setFrame)
            chosen = stage
            if achieved != observedFrames { break }
        }
        return State(direction: direction, subdivision: chosen, bounds: bounds,
                     frames: Dictionary(uniqueKeysWithValues: zip(windows, achieved)))
    }

    /// Apply one grid and redistribute space after feasible app-reported clamps.
    /// A missing frame is returned as null and is never treated as a size restriction.
    static func apply(observedFrames: [CGRect], bounds: Bounds, direction: Direction, subdivision: Int,
                      constraints initialConstraints: [WindowConstraints],
                      setFrame: (Int, CGRect) -> CGRect) -> [CGRect] {
        var constraints = initialConstraints
        var achievedFrames = observedFrames
        var lastRequestedFrames = [CGRect?](repeating: nil, count: constraints.count)

        // As with band tiling, learn clamps from actual results and redistribute
        // flexible space. Both dimensions can constrain a grid. Bound retries
        // for apps whose size rules change with their position.
        for _ in 0..<(4 * constraints.count + 1) {
            var allocation = layout(bounds: bounds, direction: direction, subdivision: subdivision,
                                    constraints: constraints)
            var learnedConstraint = false
            var infeasibleConstraint = false
            for index in constraints.indices {
                let target = allocation.frames[index]
                if lastRequestedFrames[index] != target && achievedFrames[index] != target {
                    let achieved = setFrame(index, target)
                    lastRequestedFrames[index] = target
                    achievedFrames[index] = achieved
                    if allocation.feasible && !infeasibleConstraint && !achieved.isNull {
                        var revised = constraints[index]
                        revised.width = revised.width.observing(achieved: max(0, Int(achieved.width.rounded())),
                                                               requested: Int(target.width))
                        revised.height = revised.height.observing(achieved: max(0, Int(achieved.height.rounded())),
                                                                 requested: Int(target.height))
                        if revised != constraints[index] {
                            var candidateConstraints = constraints
                            candidateConstraints[index] = revised
                            let candidate = layout(bounds: bounds, direction: direction, subdivision: subdivision,
                                                   constraints: candidateConstraints)
                            if candidate.feasible {
                                constraints = candidateConstraints
                                allocation = candidate
                                learnedConstraint = true
                            } else {
                                infeasibleConstraint = true
                            }
                        }
                    }
                }
            }
            if !allocation.feasible || !learnedConstraint { break }
        }
        return achievedFrames
    }

    static func backingBandRects(bounds: Bounds, lengths: [Int], direction: Direction) -> [CGRect] {
        var next = direction == .rows ? bounds.top : bounds.left
        return lengths.map { length in
            if direction == .rows {
                next -= length
                return CGRect(x: bounds.left, y: next, width: bounds.right - bounds.left, height: length)
            } else {
                let rect = CGRect(x: next, y: bounds.bottom, width: length, height: bounds.top - bounds.bottom)
                next += length
                return rect
            }
        }
    }

    /// Equalize flexible bands within observed limits, retaining exact fixed
    /// extents when feasible. Infeasible restrictions use equal targets for every window.
    static func balancedBandLengths(totalPixels: Int, constraints: [Constraint]) -> (lengths: [Int], feasible: Bool) {
        guard !constraints.isEmpty, totalPixels > 0 else { return ([], false) }
        let count = constraints.count
        let equal = (0..<count).map { totalPixels / count + ($0 < totalPixels % count ? 1 : 0) }
        let lower = constraints.map(\.lowerBound)
        let upper = constraints.map(\.upperBound)
        guard zip(lower, upper).allSatisfy({ pair in pair.0 <= pair.1 }),
              lower.reduce(0, +) <= totalPixels,
              upper.reduce(0, +) >= totalPixels
        else { return (equal, false) }

        var low = 0
        var high = totalPixels
        while low < high {
            let middle = low + (high - low + 1) / 2
            let required = zip(lower, upper).reduce(0) { $0 + min($1.1, max($1.0, middle)) }
            if required <= totalPixels { low = middle } else { high = middle - 1 }
        }
        var lengths = zip(lower, upper).map { min($0.1, max($0.0, low)) }
        var remainder = totalPixels - lengths.reduce(0, +)
        for index in lengths.indices where lengths[index] == low && lengths[index] < upper[index] && remainder > 0 {
            lengths[index] += 1
            remainder -= 1
        }
        return (lengths, true)
    }
}
