import Cocoa

final class LayoutHelperCloseButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: center.x - 4.5, y: center.y - 4.5))
        cross.line(to: CGPoint(x: center.x + 4.5, y: center.y + 4.5))
        cross.move(to: CGPoint(x: center.x - 4.5, y: center.y + 4.5))
        cross.line(to: CGPoint(x: center.x + 4.5, y: center.y - 4.5))
        cross.lineWidth = 2
        cross.lineCapStyle = .round
        (isHighlighted ? NSColor.secondaryLabelColor : NSColor.labelColor).setStroke()
        cross.stroke()
    }
}
