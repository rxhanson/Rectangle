//
//  SixthsCompoundCalculation.swift
//  Rectangle
//
//  Created by Ryan Hanson on 8/23/22.
//  Copyright © 2022 Ryan Hanson. All rights reserved.
//

import Foundation

struct TopSixthsCompoundCalculation: CompoundSnapAreaCalculation {
    
    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, priorSnapArea: SnapArea?) -> SnapArea? {
        guard let priorAction = priorSnapArea?.action
        else { return SnapArea(screen: screen, action: .maximize) }
        
        let frame = screen.frame
        let thirdWidth = floor(frame.width / 3)
        if loc.x <= frame.minX + thirdWidth {
            if priorAction == .topLeft || priorAction == .topLeftSixth || priorAction == .topCenterSixth {
                return SnapArea(screen: screen, action: .topLeftSixth)
            }
        }
        if loc.x >= frame.maxX - thirdWidth {
            if priorAction == .topRight || priorAction == .topRightSixth || priorAction == .topCenterSixth {
                return SnapArea(screen: screen, action: .topRightSixth)
            }
        }
        if priorAction == .topLeftSixth || priorAction == .topRightSixth || priorAction == .topCenterSixth {
            return SnapArea(screen: screen, action: .topCenterSixth)
        } else {
            return SnapArea(screen: screen, action: .maximize)
        }
    }
}

struct BottomSixthsCompoundCalculation: CompoundSnapAreaCalculation {
    
    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, priorSnapArea: SnapArea?) -> SnapArea? {
        guard let priorAction = priorSnapArea?.action else {
            return CompoundSnapArea.thirdsCompoundCalculation.snapArea(cursorLocation: loc, screen: screen, priorSnapArea: priorSnapArea)
        }

        let frame = screen.frame
        let thirdWidth = floor(frame.width / 3)
        if loc.x <= frame.minX + thirdWidth {
            if priorAction == .bottomLeft || priorAction == .bottomLeftSixth || priorAction == .bottomCenterSixth {
                return SnapArea(screen: screen, action: .bottomLeftSixth)
            }
        }
        if loc.x >= frame.minX + thirdWidth, loc.x <= frame.maxX - thirdWidth {
            if priorAction == .bottomRightSixth || priorAction == .bottomLeftSixth || priorAction == .bottomCenterSixth {
                return SnapArea(screen: screen, action: .bottomCenterSixth)
            }
        }
        if loc.x >= frame.minX + thirdWidth {
            if priorAction == .bottomRight || priorAction == .bottomRightSixth || priorAction == .bottomCenterSixth {
                return SnapArea(screen: screen, action: .bottomRightSixth)
            }
        }
        return CompoundSnapArea.thirdsCompoundCalculation.snapArea(cursorLocation: loc, screen: screen, priorSnapArea: priorSnapArea)
    }
    
}
