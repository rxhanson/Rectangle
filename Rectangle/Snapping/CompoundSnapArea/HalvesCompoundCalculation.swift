//
//  HalvesCompoundCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/23/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

struct LeftTopBottomHalfCalculation: CompoundSnapAreaCalculation {
    
    private let marginTop = Defaults.snapEdgeMarginTop.cgFloat
    private let marginBottom = Defaults.snapEdgeMarginBottom.cgFloat
    
    private let ignoredSnapAreas = SnapAreaOption(rawValue: Defaults.ignoredSnapAreas.value)
    
    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, directional: Directional, priorSnapArea: SnapArea?) -> SnapArea? {
        let frame = screen.frame
        let shortEdgeSize = CGFloat(Defaults.shortEdgeSnapAreaSize.value)

        if loc.y <= frame.minY + marginBottom + shortEdgeSize {
            if !ignoredSnapAreas.contains(.bottomLeftShort) {
                return SnapArea(screen: screen, directional: directional, action: .bottomHalf)
            }
        }
        if loc.y >= frame.maxY - marginTop - shortEdgeSize {
            if !ignoredSnapAreas.contains(.topLeftShort) {
                return SnapArea(screen: screen, directional: directional, action: .topHalf)
            }
        }
        return SnapArea(screen: screen, directional: directional, action: .leftHalf)
    }
    
}

struct RightTopBottomHalfCalculation: CompoundSnapAreaCalculation {
    
    private let marginTop = Defaults.snapEdgeMarginTop.cgFloat
    private let marginBottom = Defaults.snapEdgeMarginBottom.cgFloat
    
    private let ignoredSnapAreas = SnapAreaOption(rawValue: Defaults.ignoredSnapAreas.value)
    
    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, directional: Directional, priorSnapArea: SnapArea?) -> SnapArea? {
        let frame = screen.frame
        let shortEdgeSize = CGFloat(Defaults.shortEdgeSnapAreaSize.value)

        if loc.y <= frame.minY + marginBottom + shortEdgeSize {
            if !ignoredSnapAreas.contains(.bottomRightShort) {
                return SnapArea(screen: screen, directional: directional, action: .bottomHalf)
            }
        }
        if loc.y >= frame.maxY - marginTop - shortEdgeSize {
            if !ignoredSnapAreas.contains(.topRightShort) {
                return SnapArea(screen: screen, directional: directional, action: .topHalf)
            }
        }
        return SnapArea(screen: screen, directional: directional, action: .rightHalf)
    }
    
}

struct LeftRightHalvesCompoundCalculation: CompoundSnapAreaCalculation {
    
    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, directional: Directional, priorSnapArea: SnapArea?) -> SnapArea? {
        return loc.x < screen.frame.maxX - (screen.frame.width / 2)
            ? SnapArea(screen: screen, directional: directional, action: .leftHalf)
            : SnapArea(screen: screen, directional: directional, action: .rightHalf)
    }
    
}
