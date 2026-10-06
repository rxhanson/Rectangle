import Cocoa

/// A normal window occupies its entire matching rectangular union while any
/// content remains exposed. Floating overlap is only an occluder, never a tile.
struct LayoutHelperOccupancy {
    /// Metadata matters only for matching neighbors and possible front occluders.
    static func relevantWindowIDs(in layout: LayoutHelperLayout, windows: [WindowInfo],
                                  ignoring: Set<CGWindowID>, excludingOccupants: Set<CGWindowID> = []) -> Set<CGWindowID> {
        let eligible = windows.enumerated().filter {
            !ignoring.contains($0.element.id) && $0.element.level == 0 && $0.element.isOnScreen
                && $0.element.alpha > 0 && WindowAnimationGeometry.valid($0.element.frame)
        }
        let matching = eligible.filter {
            let cells = layout.occupiedCells(by: $0.element.frame)
            return !excludingOccupants.contains($0.element.id) && !cells.isEmpty && !cells.contains(layout.anchorIndex)
        }
        return Set(eligible.filter { entry in
            matching.contains { candidate in
                entry.offset <= candidate.offset && entry.element.frame.intersects(candidate.element.frame)
            }
        }.map { $0.element.id })
    }

    static func occupants(in layout: LayoutHelperLayout, windows: [WindowInfo],
                          normalWindowIDs: Set<CGWindowID>, ignoring: Set<CGWindowID>,
                          excludingOccupants: Set<CGWindowID> = []) -> [WindowInfo] {
        var covering: [CGRect] = []
        var result: [WindowInfo] = []
        for window in windows where normalWindowIDs.contains(window.id) && !ignoring.contains(window.id)
            && window.level == 0 && window.isOnScreen && window.alpha > 0
            && WindowAnimationGeometry.valid(window.frame) {
            let cells = layout.occupiedCells(by: window.frame)
            // Ignore rounding at the perimeter when deciding whether content is exposed.
            let content = window.frame.insetBy(dx: min(3, window.frame.width / 4),
                                                dy: min(3, window.frame.height / 4))
            if !excludingOccupants.contains(window.id), !cells.isEmpty, !cells.contains(layout.anchorIndex), isExposed(content, behind: covering) {
                result.append(window)
            }
            covering.append(window.frame)
        }
        return result
    }

    /// Subtract the union of front windows, rather than relying on one window,
    /// a global z-order cutoff, or an arbitrary visible-area percentage.
    static func isExposed(_ rect: CGRect, behind covering: [CGRect]) -> Bool {
        var exposed = [rect]
        for frame in covering {
            exposed = exposed.flatMap { piece -> [CGRect] in
                let cut = piece.intersection(frame)
                guard !cut.isNull, !cut.isEmpty else { return [piece] }
                return [CGRect(x: piece.minX, y: piece.minY, width: piece.width, height: cut.minY - piece.minY),
                        CGRect(x: piece.minX, y: cut.maxY, width: piece.width, height: piece.maxY - cut.maxY),
                        CGRect(x: piece.minX, y: cut.minY, width: cut.minX - piece.minX, height: cut.height),
                        CGRect(x: cut.maxX, y: cut.minY, width: piece.maxX - cut.maxX, height: cut.height)]
                    .filter { $0.width > 0 && $0.height > 0 }
            }
            if exposed.isEmpty { return false }
        }
        return !exposed.isEmpty
    }
}
