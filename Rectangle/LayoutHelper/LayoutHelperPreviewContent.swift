import Cocoa

/// Screenshot transitions have their own backing layer, below the fixed card chrome.
final class LayoutHelperPreviewContent: NSView {
    private(set) var preview: NSImage?
    var icon: NSImage?
    var isMinimized = false
    private var imageIdentity: CGImage?
    private var previewBackground: NSColor?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setPreview(_ image: NSImage?, animated: Bool) {
        let identity = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if preview === image || (identity != nil && identity === imageIdentity) { return }
        preview = image
        imageIdentity = identity
        previewBackground = nil
        if let identity {
            let bitmap = NSBitmapImageRep(cgImage: identity)
            // Captured windows keep transparent rounded corners. Extend the
            // top edge's color underneath them so they join the card header.
            for row in 0..<min(8, bitmap.pixelsHigh) {
                if let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: row), color.alphaComponent >= 0.99 {
                    previewBackground = color
                    break
                }
            }
        }
        if image == nil || !animated {
            layer?.removeAnimation(forKey: kCATransition)
        } else if layer?.animation(forKey: kCATransition) == nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.12
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(fade, forKey: kCATransition)
        }
        // An update during a fade replaces its destination without queuing or
        // extending the transition. Re-delivering a cached image does nothing.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let card = superview else { return }
        let cardBounds = card.bounds.offsetBy(dx: -frame.minX, dy: -frame.minY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(cgPath: LayoutHelperAppearance.cardPath(in: cardBounds)).addClip()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        (previewBackground ?? NSColor(srgbRed: dark ? 0.12 : 1, green: dark ? 0.12 : 1, blue: dark ? 0.12 : 1, alpha: 1)).setFill()
        bounds.fill()
        if let image = preview ?? icon, image.size.width > 0, image.size.height > 0 {
            let cap: CGFloat = preview == nil ? 64 / max(image.size.width, image.size.height) : .greatestFiniteMagnitude
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height, cap)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2 - (preview == nil && isMinimized ? 20 : 0),
                                 width: size.width, height: size.height), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
