import AppKit
import Cocoa
import SwiftUI

/// Keeps opaque previews above the material so vibrancy does not recolor them.
final class LayoutHelperBlurView: NSView {
    let content = ContentView()
    private let effect = NSVisualEffectView()
    private let radius: CGFloat
    private let contentFlipped: Bool
    var blendingMode: NSVisualEffectView.BlendingMode {
        get { effect.blendingMode }
        set { effect.blendingMode = newValue }
    }
    override var isFlipped: Bool { contentFlipped }

    init(frame: CGRect = .zero, material: NSVisualEffectView.Material = .fullScreenUI,
         cornerRadius: CGFloat = FootprintStyle.cornerRadius, flipped: Bool = false) {
        radius = cornerRadius
        self.contentFlipped = flipped
        super.init(frame: frame)
        content.contentFlipped = flipped
        effect.material = material
        effect.state = .active
        effect.blendingMode = .behindWindow
        addSubview(effect)
        addSubview(content)
        layoutMaterial()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); layoutMaterial() }

    private func layoutMaterial() {
        effect.frame = bounds
        content.frame = bounds
        guard bounds.width > 0, bounds.height > 0 else { effect.maskImage = nil; return }
        let cap = max(0, min(radius, (min(bounds.width, bounds.height) - 1) / 2))
        let mask = NSImage(size: NSSize(width: cap * 2 + 1, height: cap * 2 + 1), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cap, yRadius: cap).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        mask.resizingMode = .stretch
        effect.maskImage = mask
    }

    final class ContentView: NSView {
        var contentFlipped = false
        override var isFlipped: Bool { contentFlipped }
    }
}

final class LayoutHelperDocument: NSView {
    override var isFlipped: Bool { true }
    // Keep pointer sessions neutral without AppKit focusing the close button.
    override var acceptsFirstResponder: Bool { window?.contentView === self }
}

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

final class LayoutHelperCardForeground: NSView {
    weak var card: LayoutHelperCard?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { card?.drawForeground() }
}

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
