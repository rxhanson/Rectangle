import AppKit
import SwiftUI

/// Keeps opaque previews above the material so vibrancy does not recolor them.
final class WindowDividerBackdrop: NSView {
    static func inset(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) / 8, min(size.width, size.height) < 320 ? 8 : 12)
    }

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
