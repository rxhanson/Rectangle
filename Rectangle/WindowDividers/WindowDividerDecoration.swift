import Cocoa
import ScreenCaptureKit

/// Transparent outlines keep the preview shape independent of blur coverage.
final class WindowDividerDecoration: NSView {
    var axis: WindowSplitAxis = .horizontal
    var dividerX: CGFloat = 0
    var outlines: [CGRect] = []

    private func line(thickness: CGFloat) -> CGRect {
        axis == .horizontal
            ? CGRect(x: dividerX - thickness / 2, y: 0, width: thickness, height: bounds.height)
            : CGRect(x: 0, y: bounds.height - dividerX - thickness / 2, width: bounds.width, height: thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        if !BlurSurfaceView.liquidGlassEnabled {
            NSColor(calibratedWhite: 0.76, alpha: 1).setStroke()
            for frame in outlines {
                let radius = min(min(12, FootprintStyle.cornerRadius), min(frame.width, frame.height) / 2)
                let outline = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
                outline.lineWidth = 1
                outline.stroke()
            }
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        line(thickness: 4).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        line(thickness: 1.5).fill()
    }
}
