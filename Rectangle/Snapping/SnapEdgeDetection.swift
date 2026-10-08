import Cocoa

/// Keeps corner targets and shared display boundaries unchanged when early snapping is enabled.
enum SnapEdgeDetection {
    static let earlyDistance: CGFloat = 20

    static func direction(at point: CGPoint, in frame: CGRect, screens: @autoclosure () -> [CGRect],
                          margins: NSEdgeInsets, cornerSize: CGFloat, early: Bool) -> Directional? {
        // CGRect.contains excludes the maximum edges, which are valid snap targets.
        guard point.x >= frame.minX, point.x <= frame.maxX,
              point.y >= frame.minY, point.y <= frame.maxY else { return nil }

        if point.x < frame.minX + margins.left + cornerSize {
            if point.y >= frame.maxY - margins.top - cornerSize { return .tl }
            if point.y <= frame.minY + margins.bottom + cornerSize { return .bl }
        }
        if point.x > frame.maxX - margins.right - cornerSize {
            if point.y >= frame.maxY - margins.top - cornerSize { return .tr }
            if point.y <= frame.minY + margins.bottom + cornerSize { return .br }
        }

        var left = margins.left, right = margins.right
        var top = margins.top, bottom = margins.bottom
        if early {
            // Most drag events are away from an edge. Resolve neighboring displays
            // only for an early-edge candidate, using the caller's screen snapshot.
            guard point.x < frame.minX + max(left, earlyDistance)
                    || point.x > frame.maxX - max(right, earlyDistance)
                    || point.y > frame.maxY - max(top, earlyDistance)
                    || point.y < frame.minY + max(bottom, earlyDistance) else { return nil }
            let neighbors = screens().filter { $0 != frame }
            // Check only the shared portion of an edge, including displays with different heights.
            let sharesLeft = neighbors.contains {
                abs($0.maxX - frame.minX) <= 1 && point.y >= $0.minY && point.y <= $0.maxY
            }
            let sharesRight = neighbors.contains {
                abs($0.minX - frame.maxX) <= 1 && point.y >= $0.minY && point.y <= $0.maxY
            }
            let sharesTop = neighbors.contains {
                abs($0.minY - frame.maxY) <= 1 && point.x >= $0.minX && point.x <= $0.maxX
            }
            let sharesBottom = neighbors.contains {
                abs($0.maxY - frame.minY) <= 1 && point.x >= $0.minX && point.x <= $0.maxX
            }
            if !sharesLeft { left = max(left, earlyDistance) }
            if !sharesRight { right = max(right, earlyDistance) }
            if !sharesTop { top = max(top, earlyDistance) }
            if !sharesBottom { bottom = max(bottom, earlyDistance) }
        }

        if point.x < frame.minX + left { return .l }
        if point.x > frame.maxX - right { return .r }
        if point.y > frame.maxY - top { return .t }
        if point.y < frame.minY + bottom { return .b }
        return nil
    }
}
