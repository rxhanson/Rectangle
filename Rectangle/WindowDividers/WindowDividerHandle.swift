import Cocoa
import ScreenCaptureKit

final class WindowDividerHandle: NSView {
    private let material = BlurSurfaceView(cornerRadius: 6)
    private let glassGrip = GripView(frame: .zero)
    private var dragging = false
    private var hoverTracking: NSTrackingArea?
    private var ownsCursor = false
    private var panel: WindowDividerPanel? { window as? WindowDividerPanel }
    private var resizeCursor: NSCursor { panel?.axis == .vertical ? .resizeUpDown : .resizeLeftRight }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(material)
        material.content.addSubview(glassGrip)
        glassGrip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glassGrip.leadingAnchor.constraint(equalTo: material.content.leadingAnchor),
            glassGrip.trailingAnchor.constraint(equalTo: material.content.trailingAnchor),
            glassGrip.topAnchor.constraint(equalTo: material.content.topAnchor),
            glassGrip.bottomAnchor.constraint(equalTo: material.content.bottomAnchor)
        ])
        material.onStyleChange = { [weak self] in self?.updateStyle() }
        material.onAppearanceChange = { [weak self] in self?.updateStyle() }
        updateStyle()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Resize split")
        setAccessibilityHelp("Drag to resize both windows. Double-click to return to equal sizes.")
        toolTip = "Drag to resize both windows. Double-click for equal sizes."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshStyle() {
        material.refresh()
        updateStyle()
    }

    private func updateStyle() {
        appearance = Defaults.blurAppearance.value.appearance
        material.isHidden = !material.usesLiquidGlass
        glassGrip.needsDisplay = true
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        material.frame = bounds.insetBy(dx: 3, dy: 3)
        glassGrip.vertical = panel?.axis == .vertical
    }

    // The native material is decorative; the existing handle owns all input.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

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
        guard !material.usesLiquidGlass else { return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6)
        (dark ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
        shape.fill()
        NSColor(calibratedWhite: dark ? 0.58 : 0.7, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        Self.drawGrip(in: bounds, vertical: panel?.axis == .vertical)
    }

    private static func drawGrip(in bounds: CGRect, vertical: Bool) {
        NSColor.secondaryLabelColor.setFill()
        let grip = vertical
            ? CGRect(x: bounds.midX - 14, y: bounds.midY - 1, width: 28, height: 2)
            : CGRect(x: bounds.midX - 1, y: bounds.midY - 14, width: 2, height: 28)
        NSBezierPath(roundedRect: grip,
                     xRadius: 1, yRadius: 1).fill()
    }

    private final class GripView: NSView {
        var vertical = false { didSet { if oldValue != vertical { needsDisplay = true } } }
        override func draw(_ dirtyRect: NSRect) {
            WindowDividerHandle.drawGrip(in: bounds, vertical: vertical)
        }
    }
}
