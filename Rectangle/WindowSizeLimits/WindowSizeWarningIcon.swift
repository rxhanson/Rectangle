import Cocoa

final class WindowSizeWarningIcon: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.scaleX(by: bounds.width / 48, yBy: bounds.height / 36)
        transform.concat()
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        let outline = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 48, height: 36).insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        outline.lineWidth = 2
        outline.stroke()

        let arrows = NSBezierPath()
        arrows.lineWidth = 2.5
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        arrows.move(to: NSPoint(x: 14, y: 26))
        arrows.line(to: NSPoint(x: 22, y: 18))
        arrows.move(to: NSPoint(x: 16, y: 18))
        arrows.line(to: NSPoint(x: 22, y: 18))
        arrows.line(to: NSPoint(x: 22, y: 24))
        arrows.move(to: NSPoint(x: 34, y: 10))
        arrows.line(to: NSPoint(x: 26, y: 18))
        arrows.move(to: NSPoint(x: 26, y: 12))
        arrows.line(to: NSPoint(x: 26, y: 18))
        arrows.line(to: NSPoint(x: 32, y: 18))
        arrows.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
