//
//  CGExtension.swift
//  Rectangle
//
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

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
        return .init(origin: .init(x: origin.x, y: NSScreen.screens[0].frame.maxY - maxY), size: size)
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
}
