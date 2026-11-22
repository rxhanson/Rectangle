import Cocoa

/// Tracks the proposed split without touching either application during a drag.
final class WindowDividerResize {
    let geometry: WindowDividerGeometry
    private(set) var left: CGRect
    private(set) var right: CGRect
    let minimumLeft: CGFloat
    let minimumRight: CGFloat
    private(set) var pendingDivider: CGFloat?
    private var requestedDivider: CGFloat?

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
        let requested = requestedDivider
        cancelPreview()
        // A stationary first click must leave the handle available for a double-click.
        guard let requested, abs(requested - divider) > 0.5 else { return nil }
        return requested
    }

    func cancelPreview() { pendingDivider = nil; requestedDivider = nil }

    func accept(left: CGRect, right: CGRect) {
        self.left = left; self.right = right
    }

    init?(left: CGRect, right: CGRect, axis: WindowSplitAxis = .horizontal, minimumLeft: CGFloat, minimumRight: CGFloat) {
        guard let geometry = WindowDividerGeometry(left: left, right: right, axis: axis) else { return nil }
        self.geometry = geometry
        self.left = left; self.right = right
        self.minimumLeft = max(1, minimumLeft); self.minimumRight = max(1, minimumRight)
    }

}
