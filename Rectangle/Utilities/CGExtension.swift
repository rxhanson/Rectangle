/// CGExtension.swift

import Foundation

extension CGPoint {
    var screenFlipped: CGPoint {
        .init(x: x, y: NSScreen.screens[0].frame.maxY - y)
    }
}

extension CGRect {
    var screenFlipped: CGRect {
        guard !isNull else {
            return self
        }
        return screenFlipped(primaryScreenMaxY: NSScreen.screens[0].frame.maxY)
    }

    func screenFlipped(primaryScreenMaxY: CGFloat) -> CGRect {
        guard !isNull else {
            return self
        }
        return .init(origin: .init(x: origin.x, y: primaryScreenMaxY - maxY), size: size)
    }

    var isLandscape: Bool { width > height }
    
    var centerPoint: CGPoint {
        NSMakePoint(NSMidX(self), NSMidY(self))
    }
    
    func numSharedEdges(withRect rect: CGRect) -> Int {
        var sharedEdgeCount = 0
        if minX == rect.minX { sharedEdgeCount += 1 }
        if maxX == rect.maxX { sharedEdgeCount += 1 }
        if minY == rect.minY { sharedEdgeCount += 1 }
        if maxY == rect.maxY { sharedEdgeCount += 1 }
        return sharedEdgeCount
    }

    func sharedEdges(withRect rect: CGRect, tolerance: CGFloat = 0) -> Edge {
        var edges: Edge = .none
        if abs(minX - rect.minX) <= tolerance { edges.insert(.left) }
        if abs(maxX - rect.maxX) <= tolerance { edges.insert(.right) }
        if abs(maxY - rect.maxY) <= tolerance { edges.insert(.top) }
        if abs(minY - rect.minY) <= tolerance { edges.insert(.bottom) }
        return edges
    }
}

extension OptionSet where RawValue: FixedWidthInteger {
    var count: Int {
        rawValue.nonzeroBitCount
    }
}

extension CGRect {
    /// A frame a window could actually have: finite, with a positive size.
    var isValidWindowFrame: Bool {
        !isNull && !isInfinite && [minX, minY, width, height].allSatisfy { $0.isFinite } && width > 0 && height > 0
    }

    /// Whether both frames are valid and every edge of one is within `tolerance` of the other's.
    func isNear(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        isValidWindowFrame && other.isValidWindowFrame
            && abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
