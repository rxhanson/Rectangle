/// GapCalculation.swift

import Foundation

class GapCalculation {
    
    static func applyGaps(_ rect: CGRect, dimension: Dimension = .both, sharedEdges: Edge = .none, gapSize: Float, skipTopGap: Bool = false) -> CGRect {
        let cgGapSize = CGFloat(gapSize)
        let halfGapSize = cgGapSize / 2
        
        var withGaps = rect.insetBy(
            dx: dimension.contains(.horizontal) ? cgGapSize : 0,
            dy: dimension.contains(.vertical) ? cgGapSize : 0
        )
        
        if dimension.contains(.horizontal) {
            if sharedEdges.contains(.left) {
                withGaps.origin.x -= halfGapSize
                withGaps.size.width += halfGapSize
            }
            
            if sharedEdges.contains(.right) {
                withGaps.size.width += halfGapSize
            }
        }
        
        
        if dimension.contains(.vertical) {
            if sharedEdges.contains(.bottom) {
                withGaps.origin.y -= halfGapSize
                withGaps.size.height += halfGapSize
            }
            
            if sharedEdges.contains(.top) {
                withGaps.size.height += halfGapSize
            }
            if skipTopGap && !sharedEdges.contains(.top) {
                withGaps.size.height += cgGapSize
            }
        }
        
        return withGaps
    }
}

struct Dimension: OptionSet {
    let rawValue: Int
    
    static let horizontal = Dimension(rawValue: 1 << 0)
    static let vertical = Dimension(rawValue: 1 << 1)
    
    static let both: Dimension = [.horizontal, .vertical]
    static let none: Dimension = []
}

struct Edge: OptionSet {
    let rawValue: Int
    
    static let left = Edge(rawValue: 1 << 0)
    static let right = Edge(rawValue: 1 << 1)
    static let top = Edge(rawValue: 1 << 2)
    static let bottom = Edge(rawValue: 1 << 3)
    
    static let all: Edge = [.left, .right, .top, .bottom]
    static let none: Edge = []

    var isCorner: Bool {
        let horizontalCount = (contains(.left) ? 1 : 0) + (contains(.right) ? 1 : 0)
        let verticalCount = (contains(.top) ? 1 : 0) + (contains(.bottom) ? 1 : 0)
        return horizontalCount == 1 && verticalCount == 1
    }

    var isSingleEdge: Bool {
        return rawValue.nonzeroBitCount == 1
    }
}
