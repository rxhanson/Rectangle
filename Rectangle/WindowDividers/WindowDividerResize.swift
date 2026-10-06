import Cocoa

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
