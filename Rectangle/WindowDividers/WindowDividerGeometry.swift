import Cocoa

/// All pair geometry uses top-left Accessibility coordinates.
struct WindowDividerGeometry {
    let outer: CGRect
    let gap: CGFloat
    let axis: WindowSplitAxis

    static func minimumExtent(reported: CGSize?, remembered: CGSize?, acknowledged: CGSize? = nil, current: CGSize,
                              axis: WindowSplitAxis) -> CGFloat {
        let extent = axis.size(current).width
        let reported = reported.map { axis.size($0).width } ?? 0
        let baseline = reported.isFinite && reported > 0 ? reported : min(120, extent)
        return max(baseline, max(rememberedExtent(remembered, current: current, axis: axis) ?? 0,
                                rememberedExtent(acknowledged, current: current, axis: axis) ?? 0))
    }

    static func rememberedExtent(_ size: CGSize?, current: CGSize, axis: WindowSplitAxis) -> CGFloat? {
        let extent = axis.size(current).width
        guard let remembered = size.map({ axis.size($0).width }) else { return nil }
        // A live size below the remembered limit disproves it. Small rounding
        // differences may constrain shrinking, but must never force expansion.
        guard remembered.isFinite, remembered > 0, remembered <= extent + 2 else { return nil }
        return min(remembered, extent)
    }

    init?(left: CGRect, right: CGRect, axis: WindowSplitAxis = .horizontal) {
        self.axis = axis
        let left = axis.rect(left), right = axis.rect(right)
        let values = [left.minX, left.minY, left.width, left.height,
                      right.minX, right.minY, right.width, right.height]
        guard values.allSatisfy(\.isFinite), left.width > 0, right.width > 0,
              left.height > 0, abs(left.minY - right.minY) <= 2,
              abs(left.maxY - right.maxY) <= 2, right.minX >= left.maxX - 1 else { return nil }
        outer = axis.rect(left.union(right))
        gap = max(0, right.minX - left.maxX)
    }

    func frames(at divider: CGFloat, minimumLeft: CGFloat, minimumRight: CGFloat) -> (left: CGRect, right: CGRect)? {
        guard divider.isFinite, minimumLeft.isFinite, minimumRight.isFinite else { return nil }
        let outer = axis.rect(outer)
        let lower = outer.minX + max(1, minimumLeft) + gap / 2
        let upper = outer.maxX - max(1, minimumRight) - gap / 2
        guard lower <= upper else { return nil }
        // Round the window edge, not the gap center. An odd-point gutter has
        // a half-point center; rounding it produces fractional AX sizes that
        // apps round differently, allowing the outer edge to drift on release.
        let x = min(upper, max(lower, (divider - gap / 2).rounded() + gap / 2))
        return (axis.rect(CGRect(x: outer.minX, y: outer.minY, width: x - gap / 2 - outer.minX, height: outer.height)),
                axis.rect(CGRect(x: x + gap / 2, y: outer.minY, width: outer.maxX - x - gap / 2, height: outer.height)))
    }

    func containsPair(left: CGRect, right: CGRect) -> Bool {
        guard let actual = WindowDividerGeometry(left: left, right: right, axis: axis) else { return false }
        return WindowGeometry.matches(actual.outer, outer) && abs(actual.gap - gap) <= 3
    }

    func warningReference(at divider: CGFloat, rememberedMinimumLeft: CGFloat?, rememberedMinimumRight: CGFloat?) -> CGFloat {
        let target = frames(at: divider, minimumLeft: rememberedMinimumLeft ?? 1, minimumRight: rememberedMinimumRight ?? 1)
        let remembered = target.map { (axis.rect($0.left).maxX + axis.rect($0.right).minX) / 2 } ?? divider
        let limitedByMemory = (rememberedMinimumLeft != nil && remembered > divider)
            || (rememberedMinimumRight != nil && remembered < divider)
        return limitedByMemory ? remembered : divider
    }

    static func passiveCaptureOverlayIDs(in infos: [WindowInfo], at point: CGPoint,
                                         hitPID: pid_t?, ownedPIDs: Set<pid_t>, capturePIDs: Set<pid_t>) -> Set<CGWindowID> {
        // A Screenshot window can cover the display while passing input through.
        // Keep capture selection/toolbars blocking when they actually receive input.
        guard let hitPID, ownedPIDs.contains(hitPID) else { return [] }
        return Set(infos.filter {
            capturePIDs.contains($0.pid) && $0.isOnScreen && $0.alpha > 0 && $0.frame.contains(point)
        }.map(\.id))
    }

    static func unobscured(left: CGWindowID, right: CGWindowID, in infos: [WindowInfo], near region: CGRect? = nil, ignoring: Set<CGWindowID> = []) -> Bool {
        guard let li = infos.firstIndex(where: { $0.id == left }),
              let ri = infos.firstIndex(where: { $0.id == right }) else { return false }
        // A floating window elsewhere on either member must not disable an
        // exposed divider. Still respect stacking order on both sides of it.
        let leftRegion = region.map { infos[li].frame.intersection($0) } ?? infos[li].frame.insetBy(dx: 2, dy: 2)
        let rightRegion = region.map { infos[ri].frame.intersection($0) } ?? infos[ri].frame.insetBy(dx: 2, dy: 2)
        for (index, info) in infos.enumerated() where info.id != left && info.id != right
            && !ignoring.contains(info.id) && info.level >= 0 && info.isOnScreen && info.alpha > 0 {
            // WindowServer exposes the cursor and sharing indicators as windows.
            // These decorative surfaces never obscure an interactive divider.
            if info.processName == "Window Server", info.level == CGWindowLevelForKey(.cursorWindow) { continue }
            if index < li && info.frame.intersects(leftRegion) { return false }
            if index < ri && info.frame.intersects(rightRegion) { return false }
        }
        return true
    }
}
