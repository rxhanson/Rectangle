//
//  OverlapOffsetGeometry.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Foundation

/// Pure geometry for the overlap offset: where a window lands when it arrives
/// on a position other windows already occupy. Kept free of accessibility and
/// screen lookups so the cascade math can be tested directly - every bug this
/// feature has had lived here.
enum OverlapOffsetGeometry {

    /// Windows are matched by their top-left corner, so that a small window
    /// landing on a larger one at the same corner still counts as an overlap.
    static func topLeft(of rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX, y: rect.maxY)
    }

    /// Whether a frame is large enough to count as covering the screen.
    static func coversScreen(_ rect: CGRect, screenFrame: CGRect) -> Bool {
        rect.width > screenFrame.width * 0.9 && rect.height > screenFrame.height * 0.9
    }

    /// How far the window can shift on each axis without crossing the far
    /// edge of the visible frame. Zero on an axis that has no room: shifting
    /// there anyway would push the window flush against that edge, which both
    /// hides the window underneath again and eats any gap on that side.
    static func offsetStep(for rect: CGRect, in screenFrame: CGRect, by offset: CGFloat) -> CGVector {
        CGVector(dx: rect.maxX + offset <= screenFrame.maxX ? offset : 0,
                 dy: rect.maxY + offset <= screenFrame.maxY ? offset : 0)
    }

    /// Whether the window has room to shift at all. A window sized to the
    /// whole visible frame (a maximized window with no gaps) does not, so the
    /// caller can skip scanning for overlaps entirely.
    static func canOffset(_ rect: CGRect, in screenFrame: CGRect, by offset: CGFloat) -> Bool {
        let step = offsetStep(for: rect, in: screenFrame, by: offset)
        return step.dx != 0 || step.dy != 0
    }

    /// The rect to place, shifted clear of any window already at its top-left
    /// corner, up to `maxCascade` times. Returns the rect unchanged when it
    /// overlaps nothing or has nowhere left to go.
    static func cascadedRect(_ rect: CGRect,
                             occupiedTopLefts: [CGPoint],
                             screenFrame: CGRect,
                             offset: CGFloat,
                             maxCascade: Int,
                             tolerance: CGFloat = 4) -> CGRect {
        guard offset > 0 else { return rect }
        var candidate = rect
        for _ in 0..<max(0, maxCascade) {
            let corner = topLeft(of: candidate)
            let overlaps = occupiedTopLefts.contains { occupied in
                abs(occupied.x - corner.x) < tolerance && abs(occupied.y - corner.y) < tolerance
            }
            guard overlaps else { break }

            let step = offsetStep(for: candidate, in: screenFrame, by: offset)
            guard step.dx != 0 || step.dy != 0 else { break }
            candidate.origin.x += step.dx
            candidate.origin.y += step.dy
        }
        return candidate
    }
}
