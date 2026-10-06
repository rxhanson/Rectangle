import Cocoa

final class LayoutHelperPermissionButton: NSButton {
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        title = "Enable previews…"
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .labelColor
        focusRingType = .exterior
        setAccessibilityIdentifier("layoutHelperEnablePreviews")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isHighlighted ? NSColor.selectedControlColor : NSColor.controlBackgroundColor).withAlphaComponent(0.92).setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        super.draw(dirtyRect)
    }
}
