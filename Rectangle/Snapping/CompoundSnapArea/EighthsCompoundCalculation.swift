//
//  EighthsCompoundCalculation.swift
//  Rectangle
//
//  Copyright © 2024 Ryan Hanson. All rights reserved.
//

import Foundation

struct TopEighthsCompoundCalculation: CompoundSnapAreaCalculation {

    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, directional: Directional, priorSnapArea: SnapArea?) -> SnapArea? {
        guard let priorAction = priorSnapArea?.action
        else { return SnapArea(screen: screen, directional: directional, action: .maximize) }

        let frame = screen.frame
        let quarterWidth = floor(frame.width / 4)
        if loc.x <= frame.minX + quarterWidth {
            if priorAction == .topLeft || priorAction == .topLeftEighth || priorAction == .topCenterLeftEighth {
                return SnapArea(screen: screen, directional: directional, action: .topLeftEighth)
            }
        }
        if loc.x >= frame.minX + quarterWidth, loc.x <= frame.midX {
            if priorAction == .topLeftEighth || priorAction == .topCenterLeftEighth || priorAction == .topCenterRightEighth {
                return SnapArea(screen: screen, directional: directional, action: .topCenterLeftEighth)
            }
        }
        if loc.x >= frame.midX, loc.x <= frame.maxX - quarterWidth {
            if priorAction == .topCenterLeftEighth || priorAction == .topCenterRightEighth || priorAction == .topRightEighth {
                return SnapArea(screen: screen, directional: directional, action: .topCenterRightEighth)
            }
        }
        if loc.x >= frame.maxX - quarterWidth {
            if priorAction == .topRight || priorAction == .topRightEighth || priorAction == .topCenterRightEighth {
                return SnapArea(screen: screen, directional: directional, action: .topRightEighth)
            }
        }
        if priorAction == .topLeftEighth || priorAction == .topCenterLeftEighth || priorAction == .topCenterRightEighth || priorAction == .topRightEighth {
            return SnapArea(screen: screen, directional: directional, action: .maximize)
        }
        return SnapArea(screen: screen, directional: directional, action: .maximize)
    }
}

struct BottomEighthsCompoundCalculation: CompoundSnapAreaCalculation {

    func snapArea(cursorLocation loc: NSPoint, screen: NSScreen, directional: Directional, priorSnapArea: SnapArea?) -> SnapArea? {
        guard let priorAction = priorSnapArea?.action else {
            return CompoundSnapArea.thirdsCompoundCalculation.snapArea(cursorLocation: loc, screen: screen, directional: directional, priorSnapArea: priorSnapArea)
        }

        let frame = screen.frame
        let quarterWidth = floor(frame.width / 4)
        if loc.x <= frame.minX + quarterWidth {
            if priorAction == .bottomLeft || priorAction == .bottomLeftEighth || priorAction == .bottomCenterLeftEighth {
                return SnapArea(screen: screen, directional: directional, action: .bottomLeftEighth)
            }
        }
        if loc.x >= frame.minX + quarterWidth, loc.x <= frame.midX {
            if priorAction == .bottomLeftEighth || priorAction == .bottomCenterLeftEighth || priorAction == .bottomCenterRightEighth {
                return SnapArea(screen: screen, directional: directional, action: .bottomCenterLeftEighth)
            }
        }
        if loc.x >= frame.midX, loc.x <= frame.maxX - quarterWidth {
            if priorAction == .bottomCenterLeftEighth || priorAction == .bottomCenterRightEighth || priorAction == .bottomRightEighth {
                return SnapArea(screen: screen, directional: directional, action: .bottomCenterRightEighth)
            }
        }
        if loc.x >= frame.maxX - quarterWidth {
            if priorAction == .bottomRight || priorAction == .bottomRightEighth || priorAction == .bottomCenterRightEighth {
                return SnapArea(screen: screen, directional: directional, action: .bottomRightEighth)
            }
        }
        return CompoundSnapArea.thirdsCompoundCalculation.snapArea(cursorLocation: loc, screen: screen, directional: directional, priorSnapArea: priorSnapArea)
    }
}
