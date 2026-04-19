import Cocoa

class MonitorVisualizationView: NSView {

    private var screenRects: [(frame: NSRect, label: String, isPrimary: Bool)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        refresh()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        refresh()
    }

    func refresh() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let primaryScreen = PresetManager.primaryScreen()

        screenRects = screens.map { screen in
            let label: String
            if screen == primaryScreen {
                label = "Primary Display\n\(screen.localizedName)\n\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            } else {
                label = "Secondary Display\n\(screen.localizedName)\n\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            }
            return (frame: screen.frame, label: label, isPrimary: screen == primaryScreen)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !screenRects.isEmpty else { return }

        // Compute bounding box of all screens in NSScreen coords
        let allX = screenRects.flatMap { [$0.frame.minX, $0.frame.maxX] }
        let allY = screenRects.flatMap { [$0.frame.minY, $0.frame.maxY] }
        let minX = allX.min()!, maxX = allX.max()!
        let minY = allY.min()!, maxY = allY.max()!
        let totalW = maxX - minX
        let totalH = maxY - minY
        guard totalW > 0, totalH > 0 else { return }

        let padding: CGFloat = 10
        let availW = bounds.width - padding * 2
        let availH = bounds.height - padding * 2
        let scale = min(availW / totalW, availH / totalH)

        // Center the drawing
        let drawW = totalW * scale
        let drawH = totalH * scale
        let offsetX = (bounds.width - drawW) / 2
        let offsetY = (bounds.height - drawH) / 2

        for item in screenRects {
            let sx = (item.frame.minX - minX) * scale + offsetX
            // Flip Y: NSScreen Y increases upward, view Y increases upward in flipped view context
            let sy = (item.frame.minY - minY) * scale + offsetY
            let sw = item.frame.width * scale
            let sh = item.frame.height * scale

            let rect = NSRect(x: sx, y: sy, width: sw, height: sh)

            // Fill
            let fillColor: NSColor = item.isPrimary
                ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.tertiaryLabelColor.withAlphaComponent(0.1)
            fillColor.setFill()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
            path.fill()

            // Border
            let borderColor: NSColor = item.isPrimary
                ? NSColor.controlAccentColor
                : NSColor.secondaryLabelColor
            borderColor.setStroke()
            path.lineWidth = item.isPrimary ? 2 : 1
            path.stroke()

            // Label
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let fontSize: CGFloat = max(8, min(11, sh / 4))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: item.isPrimary ? .semibold : .regular),
                .foregroundColor: item.isPrimary ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle
            ]

            let labelStr = item.label as NSString
            let labelRect = rect.insetBy(dx: 4, dy: 4)
            labelStr.draw(in: labelRect, withAttributes: attrs)
        }
    }
}
