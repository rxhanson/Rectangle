import Cocoa
import ScreenCaptureKit

final class WindowDividerHandle: NSView {
    private var dragging = false
    private var hoverTracking: NSTrackingArea?
    private var ownsCursor = false
    private var panel: WindowDividerPanel? { window as? WindowDividerPanel }
    private var resizeCursor: NSCursor { panel?.axis == .vertical ? .resizeUpDown : .resizeLeftRight }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Resize split")
        setAccessibilityHelp("Drag to resize both windows. Double-click to return to equal sizes.")
        toolTip = "Drag to resize both windows. Double-click for equal sizes."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: resizeCursor) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        // Cursor-update tracking does not support activeAlways. This panel
        // deliberately stays inactive, so set the cursor from mouse tracking.
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }
    func updateHoverCursor() {
        guard let panel, panel.acceptsPointer,
              dragging || bounds.contains(convert(panel.mouseLocationOutsideOfEventStream, from: nil)) else {
            releaseHoverCursor(); return
        }
        if !ownsCursor { resizeCursor.push(); ownsCursor = true }
        else { resizeCursor.set() }
    }
    func releaseHoverCursor() {
        if ownsCursor { NSCursor.pop(); ownsCursor = false }
    }
    override func mouseEntered(with event: NSEvent) { updateHoverCursor() }
    override func mouseMoved(with event: NSEvent) { updateHoverCursor() }
    override func mouseExited(with event: NSEvent) { if !dragging { releaseHoverCursor() } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { panel?.onReset?(); return }
        guard let panel else { return }
        // The global pointer may have advanced while AX validation runs.
        // Preserve the actual mouse-down point instead of dropping that motion.
        let downX = panel.axis.coordinate(panel.convertPoint(toScreen: event.locationInWindow).screenFlipped)
        dragging = panel.onBegin?(downX) == true
        updateHoverCursor()
    }
    override func mouseDragged(with event: NSEvent) {
        if dragging, let panel { panel.onDrag?(panel.axis.coordinate(NSEvent.mouseLocation.screenFlipped)) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { dragging = false; panel?.onEnd?() }
        updateHoverCursor()
    }
    override func accessibilityPerformPress() -> Bool { panel?.onReset?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6)
        (dark ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
        shape.fill()

        NSColor(calibratedWhite: dark ? 0.58 : 0.7, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        NSColor.secondaryLabelColor.setFill()
        let grip = panel?.axis == .vertical
            ? CGRect(x: bounds.midX - 14, y: bounds.midY - 1, width: 28, height: 2)
            : CGRect(x: bounds.midX - 1, y: bounds.midY - 14, width: 2, height: 28)
        NSBezierPath(roundedRect: grip,
                     xRadius: 1, yRadius: 1).fill()
    }
}
