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

    /// How far a window's size can differ from another's and still count as
    /// the same size, when stacks are limited to one size. Terminals resize
    /// in character-cell steps, so two of them snapped to the same area can
    /// come out a cell apart.
    static let sizeTolerance: CGFloat = 24

    static func isSameSize(_ frame: CGRect, as reference: CGRect, tolerance: CGFloat = sizeTolerance) -> Bool {
        abs(frame.width - reference.width) <= tolerance
            && abs(frame.height - reference.height) <= tolerance
    }

    /// Where the stack holding `member` is measured from, as the cycle
    /// shortcuts measure it: the left anchor of the densest cascade cluster
    /// holding it, and its size. When `sizeTolerance` is given, only frames of
    /// the member's size are clustered, so a denser group of other sizes at
    /// the same corner can't claim it.
    static func stackAnchor(for member: Int, among frames: [CGRect], cascadeRange: CGFloat,
                            tolerance: CGFloat, sizeTolerance: CGFloat?) -> CGRect? {
        guard frames.indices.contains(member) else { return nil }
        let reference = frames[member]
        let pool = frames.indices.filter { index in
            guard let sizeTolerance else { return true }
            return isSameSize(frames[index], as: reference, tolerance: sizeTolerance)
        }
        let origins = pool.map { frames[$0].origin }
        guard let poolMember = pool.firstIndex(of: member),
              let anchor = clusterAnchor(containing: poolMember, among: origins,
                                         cascadeRange: cascadeRange, tolerance: tolerance)
        else { return nil }
        return CGRect(origin: origins[anchor], size: reference.size)
    }

    /// The indices of the frames stacked at `anchor`: in the cascade cluster
    /// whose left anchor is the anchor's origin and, when `sizeTolerance` is
    /// given, within it of the anchor's size. Without it, any size counts, so
    /// a maximized window sharing a half's corner is stacked with the half.
    static func stackMembers(anchor: CGRect, among frames: [CGRect], cascadeRange: CGFloat,
                             tolerance: CGFloat, sizeTolerance: CGFloat?) -> [Int] {
        clusterIndices(anchoredAt: anchor.origin, among: frames.map { $0.origin },
                       cascadeRange: cascadeRange, tolerance: tolerance)
            .filter { index in
                guard let sizeTolerance else { return true }
                return isSameSize(frames[index], as: anchor, tolerance: sizeTolerance)
            }
    }

    /// With stacks limited to one size, the stack the list shows among the
    /// frames near a corner: the one the cycle shortcuts would cycle from the
    /// front window of the cascade there, the window the user can see.
    static func sameSizeStackIndices(among frames: [CGRect], cascadeRange: CGFloat,
                                     tolerance: CGFloat, sizeTolerance: CGFloat) -> [Int] {
        let hovered = stackIndices(among: frames.map { $0.origin }, cascadeRange: cascadeRange, tolerance: tolerance)
        guard let front = hovered.first,
              let anchor = stackAnchor(for: front, among: frames, cascadeRange: cascadeRange,
                                       tolerance: tolerance, sizeTolerance: sizeTolerance)
        else { return [] }
        return stackMembers(anchor: anchor, among: frames, cascadeRange: cascadeRange,
                            tolerance: tolerance, sizeTolerance: sizeTolerance)
    }

    /// How far from a stack's corner a window's origin can sit and still be in
    /// the stack: every cascade step the overlap offset can take, plus
    /// `tolerance` for rounding.
    static func cascadeRange(offsetSize: CGFloat, maxCascade: Int, tolerance: CGFloat) -> CGFloat {
        max(offsetSize, 1) * CGFloat(min(5, max(1, maxCascade))) + tolerance
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
            let cluster = clusterIndices(anchoredAt: anchor, among: origins,
                                         cascadeRange: cascadeRange, tolerance: tolerance)
            if cluster.count > best.count {
                best = cluster
            }
        }
        return best
    }

    /// The indices of the origins in the cascade stack whose left anchor is
    /// `anchor`.
    static func clusterIndices(anchoredAt anchor: CGPoint, among origins: [CGPoint],
                               cascadeRange: CGFloat, tolerance: CGFloat) -> [Int] {
        origins.indices.filter { index in
            let dx = origins[index].x - anchor.x
            let dy = origins[index].y - anchor.y
            return dx >= -tolerance && dx <= cascadeRange
                && dy >= -cascadeRange && dy <= cascadeRange
        }
    }

    /// The index of the anchor of the stack `member` belongs to, chosen as
    /// `stackIndices` chooses: the densest cluster that includes it, the
    /// earliest anchor winning a tie.
    static func clusterAnchor(containing member: Int, among origins: [CGPoint],
                              cascadeRange: CGFloat, tolerance: CGFloat) -> Int? {
        var best: (anchor: Int, count: Int)?
        for anchor in origins.indices {
            let cluster = clusterIndices(anchoredAt: origins[anchor], among: origins,
                                         cascadeRange: cascadeRange, tolerance: tolerance)
            guard cluster.contains(member) else { continue }
            if cluster.count > best?.count ?? 0 {
                best = (anchor, cluster.count)
            }
        }
        return best?.anchor
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
