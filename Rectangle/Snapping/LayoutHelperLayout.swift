import Foundation

/// Geometry uses Accessibility coordinates: origin at the top left, y increasing downwards.
/// Cells are always stored in reading order, irrespective of the initiating corner.
struct LayoutHelperLayout {
    let screen: CGRect
    let cells: [CGRect]
    let anchorIndex: Int
    let gap: CGFloat
    let skipTopGap: Bool

    static func make(action: WindowAction, screen: CGRect, anchor: CGRect,
                     gap: CGFloat = 0, skipTopGap: Bool = false,
                     includeDenseGrids: Bool = false) -> LayoutHelperLayout? {
        guard screen.width > 0, screen.height > 0, anchor.width > 0, anchor.height > 0,
              screen.insetBy(dx: -2, dy: -2).contains(anchor) else { return nil }
        let portrait = screen.height > screen.width
        var columns = 1
        var rows = 1
        var complement = false
        switch action {
        case .leftHalf, .rightHalf: columns = 2
        case .topHalf, .bottomHalf: rows = 2
        case .topLeft, .topRight, .bottomLeft, .bottomRight: columns = 2; rows = 2
        case .firstThird, .centerThird, .lastThird:
            columns = portrait ? 1 : 3; rows = portrait ? 3 : 1
        case .topVerticalThird, .middleVerticalThird, .bottomVerticalThird: rows = 3
        case .firstTwoThirds, .lastTwoThirds, .firstThreeFourths, .lastThreeFourths:
            columns = portrait ? 1 : 2; rows = portrait ? 2 : 1; complement = true
        case .topVerticalTwoThirds, .bottomVerticalTwoThirds: rows = 2; complement = true
        case .centerHalf, .centerTwoThirds:
            columns = portrait ? 1 : 3; rows = portrait ? 3 : 1; complement = true
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth:
            columns = portrait ? 1 : 4; rows = portrait ? 4 : 1
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
             .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth:
            columns = portrait ? 2 : 3; rows = portrait ? 3 : 2
        case .topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth,
             .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth:
            guard includeDenseGrids else { return nil }
            columns = portrait ? 2 : 4; rows = portrait ? 4 : 2
        case .topLeftNinth, .topCenterNinth, .topRightNinth,
             .middleLeftNinth, .middleCenterNinth, .middleRightNinth,
             .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth:
            guard includeDenseGrids else { return nil }
            columns = 3; rows = 3
        case .topLeftTwelfth, .topCenterLeftTwelfth, .topCenterRightTwelfth, .topRightTwelfth,
             .middleLeftTwelfth, .middleCenterLeftTwelfth, .middleCenterRightTwelfth, .middleRightTwelfth,
             .bottomLeftTwelfth, .bottomCenterLeftTwelfth, .bottomCenterRightTwelfth, .bottomRightTwelfth:
            guard includeDenseGrids else { return nil }
            columns = portrait ? 3 : 4; rows = portrait ? 4 : 3
        case .topLeftSixteenth, .topCenterLeftSixteenth, .topCenterRightSixteenth, .topRightSixteenth,
             .upperMiddleLeftSixteenth, .upperMiddleCenterLeftSixteenth,
             .upperMiddleCenterRightSixteenth, .upperMiddleRightSixteenth,
             .lowerMiddleLeftSixteenth, .lowerMiddleCenterLeftSixteenth,
             .lowerMiddleCenterRightSixteenth, .lowerMiddleRightSixteenth,
             .bottomLeftSixteenth, .bottomCenterLeftSixteenth, .bottomCenterRightSixteenth, .bottomRightSixteenth:
            guard includeDenseGrids else { return nil }
            columns = 4; rows = 4
        default: return nil
        }

        func cuts(min: CGFloat, max: CGFloat, start: CGFloat, end: CGFloat, count: Int) -> [CGFloat]? {
            if count == 1 {
                guard abs(start - min) <= 2, abs(end - max) <= 2 else { return nil }
                return [min, max]
            }
            if complement {
                return ([min] + (start > min + 2 ? [start] : [])
                        + (end < max - 2 ? [end] : []) + [max])
            }
            let index = Swift.min(count - 1, Swift.max(0, Int(((start + end) / 2 - min) / (max - min) * CGFloat(count))))
            guard (index != 0 || abs(start - min) <= 2),
                  (index != count - 1 || abs(end - max) <= 2) else { return nil }
            var result: [CGFloat] = []
            for i in 0...count {
                if i <= index {
                    result.append(index == 0 ? min : min + (start - min) * CGFloat(i) / CGFloat(index))
                } else {
                    let remaining = count - index - 1
                    result.append(remaining == 0 ? max : end + (max - end) * CGFloat(i - index - 1) / CGFloat(remaining))
                }
            }
            return result
        }
        guard let xs = cuts(min: screen.minX, max: screen.maxX, start: anchor.minX, end: anchor.maxX, count: columns),
              let ys = cuts(min: screen.minY, max: screen.maxY, start: anchor.minY, end: anchor.maxY, count: rows)
        else { return nil }
        var cells: [CGRect] = []
        for row in 0..<ys.count - 1 {
            for column in 0..<xs.count - 1 {
                let cell = CGRect(x: xs[column].rounded(), y: ys[row].rounded(),
                                  width: xs[column + 1].rounded() - xs[column].rounded(),
                                  height: ys[row + 1].rounded() - ys[row].rounded())
                guard cell.width > gap * 2 + 1, cell.height > gap * 2 + 1 else { return nil }
                cells.append(cell)
            }
        }
        guard let anchorIndex = cells.firstIndex(where: { matches($0, anchor, tolerance: 2) }), cells.count > 1 else { return nil }
        return LayoutHelperLayout(screen: screen, cells: cells, anchorIndex: anchorIndex,
                                gap: max(0, gap), skipTopGap: skipTopGap)
    }

    func target(for cell: CGRect) -> CGRect {
        let left = abs(cell.minX - screen.minX) < 2 ? gap : gap / 2
        let right = abs(cell.maxX - screen.maxX) < 2 ? gap : gap / 2
        let top = abs(cell.minY - screen.minY) < 2 ? (skipTopGap ? 0 : gap) : gap / 2
        let bottom = abs(cell.maxY - screen.maxY) < 2 ? gap : gap / 2
        return CGRect(x: cell.minX + left, y: cell.minY + top,
                      width: cell.width - left - right, height: cell.height - top - bottom)
    }

    /// A retained window may occupy a rectangular union of cells, e.g. the right half
    /// beside two left quarters. Mere overlap never counts as occupying a slot.
    func occupiedCells(by frame: CGRect) -> Set<Int> {
        let indices = cells.indices.filter { target(for: cells[$0]).intersects(frame) }
        guard !indices.isEmpty else { return [] }
        let union = indices.reduce(CGRect.null) { $0.union(cells[$1]) }
        let area = indices.reduce(CGFloat(0)) { $0 + cells[$1].width * cells[$1].height }
        guard abs(area - union.width * union.height) < 2,
              Self.matches(target(for: union), frame) else { return [] }
        return Set(indices)
    }

    func remaining(excluding occupied: Set<Int>) -> [Int] {
        cells.indices.filter { $0 != anchorIndex && !occupied.contains($0) }
    }

    /// A two-window split offers the other side again, even when occupied.
    /// Larger grids continue to preserve compatible windows already in place.
    func prefilledCells(by frame: CGRect) -> Set<Int> {
        cells.count == 2 ? [] : occupiedCells(by: frame)
    }

    static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        !lhs.isNull && !rhs.isNull && abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}
