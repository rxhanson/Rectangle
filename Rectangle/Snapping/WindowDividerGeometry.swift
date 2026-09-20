import Cocoa

/// Normalizes a left/right or top/bottom split to one primary coordinate.
/// Transposition is its own inverse; all inputs remain top-left AX points.
enum WindowSplitAxis {
    case horizontal, vertical
    init?(action: WindowAction) {
        switch action {
        case .leftHalf, .rightHalf: self = .horizontal
        case .topHalf, .bottomHalf: self = .vertical
        default: return nil
        }
    }
    func rect(_ r: CGRect) -> CGRect {
        self == .horizontal ? r : CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width)
    }
    func size(_ s: CGSize) -> CGSize { self == .horizontal ? s : CGSize(width: s.height, height: s.width) }
    func coordinate(_ p: CGPoint) -> CGFloat { self == .horizontal ? p.x : p.y }
    func point(_ primary: CGFloat, cross: CGFloat) -> CGPoint {
        self == .horizontal ? CGPoint(x: primary, y: cross) : CGPoint(x: cross, y: primary)
    }
}

/// All pair geometry uses top-left Accessibility coordinates.
struct WindowDividerGeometry {
    let outer: CGRect
    let gap: CGFloat
    let axis: WindowSplitAxis

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
        return LayoutHelperLayout.matches(actual.outer, outer) && abs(actual.gap - gap) <= 3
    }

    static func unobscured(left: CGWindowID, right: CGWindowID, in infos: [WindowInfo], near region: CGRect? = nil) -> Bool {
        guard let li = infos.firstIndex(where: { $0.id == left }),
              let ri = infos.firstIndex(where: { $0.id == right }) else { return false }
        // A floating window elsewhere on either member must not disable an
        // exposed divider. Still respect stacking order on both sides of it.
        let leftRegion = region.map { infos[li].frame.intersection($0) } ?? infos[li].frame.insetBy(dx: 2, dy: 2)
        let rightRegion = region.map { infos[ri].frame.intersection($0) } ?? infos[ri].frame.insetBy(dx: 2, dy: 2)
        for (index, info) in infos.enumerated() where info.id != left && info.id != right && info.level == 0 {
            if index < li && info.frame.intersects(leftRegion) { return false }
            if index < ri && info.frame.intersects(rightRegion) { return false }
        }
        return true
    }
}

/// Shrink before expanding, and learn unreported size limits from AX readback.
/// A refused or inconsistent resize rolls back to the last accepted pair.
final class WindowDividerResize {
    let geometry: WindowDividerGeometry
    private(set) var left: CGRect
    private(set) var right: CGRect
    private(set) var minimumLeft: CGFloat
    private(set) var minimumRight: CGFloat
    private(set) var pendingDivider: CGFloat?
    private var requestedDivider: CGFloat?
    private let writeFrame: (Bool, CGRect, Bool, Bool) -> Bool
    private let read: (Bool) -> CGRect
    private var lastWrittenLeft: CGRect
    private var lastWrittenRight: CGRect

    private var axis: WindowSplitAxis { geometry.axis }
    var divider: CGFloat { (axis.rect(left).maxX + axis.rect(right).minX) / 2 }

    /// Pointer tracking changes only the proposed split. Window I/O is deferred
    /// until release, so an app's resize speed cannot hold back the handle.
    @discardableResult func preview(to requested: CGFloat) -> CGFloat? {
        guard let frames = geometry.frames(at: requested, minimumLeft: minimumLeft, minimumRight: minimumRight) else { return nil }
        requestedDivider = requested
        pendingDivider = (axis.rect(frames.left).maxX + axis.rect(frames.right).minX) / 2
        return pendingDivider
    }

    func takePreview() -> CGFloat? {
        // The preview stays within the known limits, but placement must retain
        // the pointer's intent to distinguish a minimum from an ordinary split.
        let x = requestedDivider
        cancelPreview()
        return x
    }

    func cancelPreview() { pendingDivider = nil; requestedDivider = nil }

    func accept(left: CGRect, right: CGRect) {
        self.left = left; self.right = right
    }

    init?(left: CGRect, right: CGRect, axis: WindowSplitAxis = .horizontal, minimumLeft: CGFloat, minimumRight: CGFloat,
          write: @escaping (Bool, CGRect, Bool, Bool) -> Bool, read: @escaping (Bool) -> CGRect) {
        guard let geometry = WindowDividerGeometry(left: left, right: right, axis: axis) else { return nil }
        self.geometry = geometry
        self.left = left; self.right = right
        self.minimumLeft = max(1, minimumLeft); self.minimumRight = max(1, minimumRight)
        self.writeFrame = write; self.read = read
        lastWrittenLeft = left; lastWrittenRight = right
    }

    /// Send the destination once, then acknowledge placement separately.
    @discardableResult func applyTarget(to requested: CGFloat) -> Bool {
        guard let target = geometry.frames(at: requested, minimumLeft: minimumLeft, minimumRight: minimumRight) else { return false }
        let shrinkLeft = axis.rect(target.left).width < axis.rect(lastWrittenLeft).width
        func writeTarget(_ isLeft: Bool) -> Bool {
            let frame = isLeft ? target.left : target.right
            let previous = isLeft ? lastWrittenLeft : lastWrittenRight
            // Avoid asking either app to redraw an unchanged destination, and omit
            // position writes entirely when only the size changes.
            if frame == previous { return true }
            return writeFrame(isLeft, frame, axis.rect(frame).minX < axis.rect(previous).minX, frame.origin == previous.origin)
        }
        guard writeTarget(shrinkLeft), writeTarget(!shrinkLeft) else { return false }
        lastWrittenLeft = target.left; lastWrittenRight = target.right
        return true
    }

    @discardableResult func move(to requested: CGFloat) -> Bool {
        guard var target = geometry.frames(at: requested, minimumLeft: minimumLeft, minimumRight: minimumRight) else { return false }
        let currentLeft = read(true), currentRight = read(false)
        if LayoutHelperLayout.matches(currentLeft, target.left, tolerance: 0.5)
            && LayoutHelperLayout.matches(currentRight, target.right, tolerance: 0.5) {
            left = currentLeft; right = currentRight
            return true
        }
        let shrinkLeft = axis.rect(target.left).width < axis.rect(currentLeft).width
        let first = shrinkLeft ? target.left : target.right
        guard write(shrinkLeft, first) else { rollback(); return false }
        let achieved = read(shrinkLeft)
        if !LayoutHelperLayout.matches(achieved, first) {
            // Some apps do not report AX minimumSize. Only accept a clamp along the split axis
            // here; any cross-axis/outer-edge change means the pair is no longer safe.
            let achieved = axis.rect(achieved), first = axis.rect(first)
            let positionMatches = abs(achieved.minX - first.minX) <= 3
                || (!shrinkLeft && abs(achieved.maxX - axis.rect(right).maxX) <= 3)
            guard !achieved.isNull, positionMatches, abs(achieved.minY - first.minY) <= 3,
                  abs(achieved.height - first.height) <= 3, achieved.width > first.width else {
                rollback(); return false
            }
            if shrinkLeft { minimumLeft = max(minimumLeft, achieved.width) }
            else { minimumRight = max(minimumRight, achieved.width) }
            guard let adjusted = geometry.frames(at: requested, minimumLeft: minimumLeft, minimumRight: minimumRight) else {
                rollback(); return false
            }
            target = adjusted
            guard write(shrinkLeft, shrinkLeft ? target.left : target.right) else { rollback(); return false }
        }
        guard write(!shrinkLeft, shrinkLeft ? target.right : target.left),
              LayoutHelperLayout.matches(read(true), target.left),
              LayoutHelperLayout.matches(read(false), target.right) else { rollback(); return false }
        left = read(true); right = read(false)
        return true
    }

    private func write(_ isLeft: Bool, _ frame: CGRect) -> Bool {
        // Growing toward the left needs the position write first. Shrinking
        // toward the right needs the size write first. Use actual geometry
        // here so recovery after a partial/refused write follows the same rule.
        let current = read(isLeft)
        return writeFrame(isLeft, frame, !current.isNull && axis.rect(frame).minX < axis.rect(current).minX,
                          !current.isNull && frame.origin == current.origin)
    }

    private func rollback() {
        _ = write(true, left)
        _ = write(false, right)
    }
}

/// AX attributes can be accepted asynchronously. Acknowledge each attribute
/// before sending the next one so a delayed position write cannot discard an
/// earlier resize. Rollback uses the same acknowledgment path.
final class WindowDividerPlacement {
    enum State: Equatable { case waiting, completed, rolledBack, failed }
    enum Attribute { case size, position }
    private struct Pending {
        let index: Int
        let attribute: Attribute
        let before: CGRect
        let expected: CGRect
        let startedAt: TimeInterval
        var observed: CGRect
        var stableSince: TimeInterval
    }

    private let geometry: WindowDividerGeometry
    private let requested: CGFloat
    private let originals: [CGRect]
    private var targets: [CGRect]
    private var minima: [CGFloat]
    private let write: (Bool, CGRect, Attribute) -> Bool
    private let read: (Bool) -> CGRect
    private var order: [Int]
    private var cursor = 0
    private var pending: Pending?
    private var rollingBack = false
    private var rollbackIncomplete = false
    private var terminal: State?
    private var unreadableSince: TimeInterval?

    /// Only acknowledged placement can produce a size warning. Rounding the
    /// split by up to one point, a rollback, or a refused write cannot do so.
    var minimumSizeReached: Bool {
        guard terminal == .completed else { return false }
        let actual = (geometry.axis.rect(left).maxX + geometry.axis.rect(right).minX) / 2
        return abs(actual - requested) > 1
    }

    var left: CGRect { targets[0] }
    var right: CGRect { targets[1] }

    init?(left: CGRect, right: CGRect, axis: WindowSplitAxis, divider: CGFloat,
          minimumLeft: CGFloat, minimumRight: CGFloat,
          write: @escaping (Bool, CGRect, Attribute) -> Bool,
          read: @escaping (Bool) -> CGRect) {
        guard let geometry = WindowDividerGeometry(left: left, right: right, axis: axis),
              let target = geometry.frames(at: divider, minimumLeft: minimumLeft, minimumRight: minimumRight) else { return nil }
        self.geometry = geometry; requested = divider
        originals = [left, right]; targets = [target.left, target.right]
        minima = [minimumLeft, minimumRight]; self.write = write; self.read = read
        order = axis.rect(target.left).width < axis.rect(left).width ? [0, 1] : [1, 0]
    }

    func advance(at time: TimeInterval) -> State {
        if let terminal { return terminal }
        if var waiting = pending {
            let actual = read(waiting.index == 0)
            if !LayoutHelperLayout.matches(actual, waiting.observed, tolerance: 0.5) {
                waiting.observed = actual; waiting.stableSince = time
            }
            let stable = time - waiting.stableSince >= 0.05
            if LayoutHelperLayout.matches(actual, waiting.expected, tolerance: 1), stable {
                pending = nil
            } else if !rollingBack, waiting.attribute == .size, stable,
                      acceptClamp(actual, pending: waiting) {
                pending = nil
            } else if time - waiting.startedAt >= 0.6 {
                failCurrent()
            } else {
                pending = waiting
                return .waiting
            }
        }
        while cursor < order.count {
            let index = order[cursor], current = read(order[cursor] == 0), target = targets[index]
            guard !current.isNull, !current.isEmpty else {
                if let since = unreadableSince, time - since >= 0.6 { failCurrent() }
                else if unreadableSince == nil { unreadableSince = time }
                return .waiting
            }
            unreadableSince = nil
            if LayoutHelperLayout.matches(current, target, tolerance: 1) { cursor += 1; continue }
            let attribute: Attribute
            if geometry.axis.rect(target).minX < geometry.axis.rect(current).minX - 1 {
                attribute = .position
            } else if abs(current.width - target.width) > 1 || abs(current.height - target.height) > 1 {
                attribute = .size
            } else { attribute = .position }
            let expected = attribute == .size ? CGRect(origin: current.origin, size: target.size)
                : CGRect(origin: target.origin, size: current.size)
            // AX can report a timeout while the app still applies the request.
            // The bounded readback below decides whether placement succeeded.
            _ = write(index == 0, expected, attribute)
            pending = Pending(index: index, attribute: attribute, before: current,
                              expected: expected, startedAt: time, observed: current, stableSince: time)
            return .waiting
        }
        let actualLeft = read(true), actualRight = read(false)
        guard !actualLeft.isNull, !actualLeft.isEmpty, !actualRight.isNull, !actualRight.isEmpty else {
            if let since = unreadableSince, time - since >= 0.6 {
                if rollingBack { terminal = .failed; return .failed }
                failCurrent()
            } else if unreadableSince == nil { unreadableSince = time }
            return .waiting
        }
        unreadableSince = nil
        guard LayoutHelperLayout.matches(actualLeft, targets[0], tolerance: 1),
              LayoutHelperLayout.matches(actualRight, targets[1], tolerance: 1) else {
            if rollingBack { terminal = .failed; return .failed }
            failCurrent(); return .waiting
        }
        terminal = rollbackIncomplete ? .failed : rollingBack ? .rolledBack : .completed
        return terminal!
    }

    private func acceptClamp(_ actual: CGRect, pending: Pending) -> Bool {
        let axis = geometry.axis
        let actual = axis.rect(actual), expected = axis.rect(pending.expected), before = axis.rect(pending.before)
        // An unchanged/refused write is not evidence of an app's minimum.
        guard !actual.isNull, abs(actual.minX - expected.minX) <= 1,
              abs(actual.minY - expected.minY) <= 1, abs(actual.height - expected.height) <= 1,
              actual.width > expected.width + 1, actual.width < before.width - 1 else { return false }
        var updated = minima; updated[pending.index] = max(updated[pending.index], actual.width)
        guard let corrected = geometry.frames(at: requested, minimumLeft: updated[0], minimumRight: updated[1]) else { return false }
        minima = updated; targets = [corrected.left, corrected.right]
        return true
    }

    private func failCurrent() {
        pending = nil
        unreadableSince = nil
        if rollingBack {
            rollbackIncomplete = true; cursor += 1
        } else {
            rollingBack = true; targets = originals; cursor = 0
            // Release space before restoring the other member.
            order = geometry.axis.rect(read(true)).width > geometry.axis.rect(originals[0]).width ? [0, 1] : [1, 0]
        }
    }
}

/// Require both apps to acknowledge the final geometry continuously before
/// revealing them; a bounded deadline prevents a stalled app from trapping UI.
struct WindowDividerRevealGate {
    enum State: Equatable { case waiting, ready, timedOut }
    let left: CGRect
    let right: CGRect
    let startedAt: TimeInterval
    private var matchedSince: TimeInterval?

    init(left: CGRect, right: CGRect, startedAt: TimeInterval) {
        self.left = left; self.right = right; self.startedAt = startedAt
    }

    mutating func observe(left actualLeft: CGRect, right actualRight: CGRect, at time: TimeInterval) -> State {
        if LayoutHelperLayout.matches(actualLeft, left, tolerance: 1),
           LayoutHelperLayout.matches(actualRight, right, tolerance: 1) {
            if let matchedSince, time - matchedSince >= 0.05 { return .ready }
            if matchedSince == nil { matchedSince = time }
        } else { matchedSince = nil }
        return time - startedAt >= 0.6 ? .timedOut : .waiting
    }
}
