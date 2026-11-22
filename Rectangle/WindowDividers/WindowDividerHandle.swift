import Cocoa

final class WindowDividerHandle: NSView {
    private let material = BlurSurfaceView(material: .popover, cornerRadius: 6, solidColor: .controlBackgroundColor)
    private let grip = GripView(frame: .zero)
    private var dragging = false
    private var hoverTracking: NSTrackingArea?
    private var ownsCursor = false
    private var panel: WindowDividerPanel? { window as? WindowDividerPanel }
    private var resizeCursor: NSCursor { panel?.axis == .vertical ? .resizeUpDown : .resizeLeftRight }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(material)
        material.content.addSubview(grip)
        grip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: material.content.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: material.content.trailingAnchor),
            grip.topAnchor.constraint(equalTo: material.content.topAnchor),
            grip.bottomAnchor.constraint(equalTo: material.content.bottomAnchor)
        ])
        material.onStyleChange = { [weak self] in self?.updateStyle() }
        material.onAppearanceChange = { [weak self] in self?.updateStyle() }
        updateStyle()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Resize split"))
        setAccessibilityHelp(String(localized: "Drag to resize both windows. Double-click to return to equal sizes."))
        toolTip = String(localized: "Drag to resize both windows. Double-click for equal sizes.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshStyle() {
        material.refresh()
        updateStyle()
    }

    private func updateStyle() {
        appearance = Defaults.effectiveOverlayAppearance
        grip.drawsBorder = material.effectiveMaterial == .noBlur
        grip.needsDisplay = true
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        material.frame = bounds.insetBy(dx: 3, dy: 3)
        grip.vertical = panel?.axis == .vertical
    }

    // The handle owns pointer input; its material supplies decoration.
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
        // Start from the event's mouse-down point to preserve that motion.
        let downX = dividerCoordinate(for: event, in: panel)
        dragging = panel.onBegin?(downX) == true
        updateHoverCursor()
    }
    private func dividerCoordinate(for event: NSEvent, in panel: WindowDividerPanel) -> CGFloat {
        let location = event.cgEvent?.location ?? panel.convertPoint(toScreen: event.locationInWindow).screenFlipped
        return panel.axis.coordinate(location)
    }
    override func mouseDragged(with event: NSEvent) {
        if dragging, let panel { panel.onDrag?(dividerCoordinate(for: event, in: panel)) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragging, let panel {
            dragging = false
            // The final drag event can be coalesced. Commit at the release location.
            panel.onDrag?(dividerCoordinate(for: event, in: panel))
            panel.onEnd?()
        }
        updateHoverCursor()
    }
    override func accessibilityPerformPress() -> Bool { panel?.onReset?(); return true }
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
        var drawsBorder = false
        override func draw(_ dirtyRect: NSRect) {
            if drawsBorder {
                NSColor.separatorColor.setStroke()
                let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5.5, yRadius: 5.5)
                edge.lineWidth = 1
                edge.stroke()
            }
            WindowDividerHandle.drawGrip(in: bounds, vertical: vertical)
        }
    }
}
