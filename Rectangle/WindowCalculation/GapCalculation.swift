//
//  GapCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 1/14/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

class GapCalculation {
    
    static func applyGaps(_ rect: CGRect, sharedEdges: Edge = .none, gapSize: Float) -> CGRect {
        
        let cgGapSize = CGFloat(gapSize)
        var withGaps = rect.insetBy(dx: cgGapSize, dy: cgGapSize)
        
        if (sharedEdges.contains(.left)) {
            withGaps = CGRect(
                x: withGaps.origin.x - (cgGapSize / 2),
                y: withGaps.origin.y,
                width: withGaps.width + (cgGapSize / 2),
                height: withGaps.height
            )
        }
        
        if (sharedEdges.contains(.right)) {
            withGaps = CGRect(
                x: withGaps.origin.x,
                y: withGaps.origin.y,
                width: withGaps.width + (cgGapSize / 2),
                height: withGaps.height
            )
        }
        
        if (sharedEdges.contains(.bottom)) {
            withGaps = CGRect(
                x: withGaps.origin.x,
                y: withGaps.origin.y - (cgGapSize / 2),
                width: withGaps.width,
                height: withGaps.height + (cgGapSize / 2)
            )
        }
        
        if (sharedEdges.contains(.top)) {
            withGaps = CGRect(
                x: withGaps.origin.x,
                y: withGaps.origin.y,
                width: withGaps.width,
                height: withGaps.height + (cgGapSize / 2)
            )
        }
        
        return withGaps
    }
}

struct Edge: OptionSet {
    let rawValue: Int
    
    static let left = Edge(rawValue: 1 << 0)
    static let right = Edge(rawValue: 1 << 1)
    static let top = Edge(rawValue: 1 << 2)
    static let bottom = Edge(rawValue: 1 << 3)
    
    static let all: Edge = [.left, .right, .top, .bottom]
    static let none: Edge = []
}
