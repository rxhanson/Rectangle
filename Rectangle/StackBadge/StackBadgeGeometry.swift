//
//  StackBadgeGeometry.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Foundation

/// Pure geometry for the stack badge: where on a screen a grid cell's
/// top-left corner can be, and whether the cursor is resting near one.
/// No AX, no window state - computable from screen frames alone.
enum StackBadgeGeometry {

    /// Every grid layout Rectangle can place windows into, as (columns, rows).
    /// Cell corners from these are where stacked windows can share an origin.
    static let gridDimensions: [(cols: Int, rows: Int)] = [
        (2, 1), (1, 2),         // halves
        (3, 1), (1, 3),         // thirds
        (2, 2),                 // quarters
        (4, 1), (1, 4),         // fourths
        (3, 2), (2, 3),         // sixths
        (4, 2),                 // eighths
        (3, 3),                 // ninths
        (4, 3), (3, 4),         // twelfths
        (4, 4)                  // sixteenths
    ]

    /// Top-left corners (AppKit coordinates, y up) of every grid cell across
    /// all supported grids, deduplicated. ~30 points for a typical screen.
    static func cornerPoints(in screenFrame: CGRect) -> [CGPoint] {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return [] }
        var points = [CGPoint]()
        for grid in gridDimensions {
            for col in 0..<grid.cols {
                for row in 0..<grid.rows {
                    let point = CGPoint(
                        x: screenFrame.minX + CGFloat(col) * screenFrame.width / CGFloat(grid.cols),
                        y: screenFrame.maxY - CGFloat(row) * screenFrame.height / CGFloat(grid.rows)
                    )
                    if !points.contains(where: { abs($0.x - point.x) < 1 && abs($0.y - point.y) < 1 }) {
                        points.append(point)
                    }
                }
            }
        }
        return points
    }

    /// The indices of the window origins (AX coordinates) that form a
    /// cascade stack. The overlap offset cascades diagonally: +x always, but
    /// y can run either way (the offset is applied in AppKit coordinates,
    /// where +y converts to an upward move in AX space), so the y window is
    /// symmetric. Every origin is tried as the stack's left anchor and the
    /// densest cluster wins, so neither unrelated neighbors in a gap-widened
    /// candidate box nor an unrelated leftmost outlier can distort the count.
    static func stackIndices(among origins: [CGPoint], cascadeRange: CGFloat, tolerance: CGFloat) -> [Int] {
        var best = [Int]()
        for anchor in origins {
            let cluster = origins.indices.filter { index in
                let dx = origins[index].x - anchor.x
                let dy = origins[index].y - anchor.y
                return dx >= -tolerance && dx <= cascadeRange
                    && dy >= -cascadeRange && dy <= cascadeRange
            }
            if cluster.count > best.count {
                best = cluster
            }
        }
        return best
    }

    /// The corner whose hover zone contains the point, or nil. The zone is a
    /// square extending right and down from the corner (down in AppKit means
    /// minus y), covering where gap-shifted windows and their title bars sit
    /// relative to the geometric corner.
    static func corner(near point: CGPoint, in corners: [CGPoint], zone: CGFloat) -> CGPoint? {
        var best: (corner: CGPoint, distance: CGFloat)?
        for corner in corners {
            let dx = point.x - corner.x
            let dy = corner.y - point.y
            guard dx >= -4, dx <= zone, dy >= -4, dy <= zone else { continue }
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance {
                best = (corner, distance)
            }
        }
        return best?.corner
    }
}
