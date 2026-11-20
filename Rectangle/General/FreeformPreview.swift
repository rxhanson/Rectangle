/// FreeformPreview.swift

import AppKit

/// A picture of a Freeform preset's area in the style of the other window position icons:
/// a display outline with the window's area filled in.
enum FreeformPreview {
    /// The size of the other window position icons.
    static let size = CGSize(width: 30, height: 20)
    /// The display inside its one point outline.
    static let screen = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
    /// The opacity of the display around the window, as in the other icons.
    static let screenAlpha: CGFloat = 0.4

    /// The window's area in the icon, on whole points and at least one point in each direction,
    /// so a small area still shows where it is.
    static func windowRect(for region: FreeformRegion) -> CGRect {
        let relative = region.relativeRect
        func span(_ low: CGFloat, _ high: CGFloat, origin: CGFloat, length: CGFloat) -> (CGFloat, CGFloat) {
            var start = (low * length).rounded()
            var end = (high * length).rounded()
            if end - start < 1 {
                start = min(start, length - 1)
                end = start + 1
            }
            return (origin + start, end - start)
        }
        let (x, width) = span(relative.minX, relative.maxX, origin: screen.minX, length: screen.width)
        let (y, height) = span(relative.minY, relative.maxY, origin: screen.minY, length: screen.height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func image(for region: FreeformRegion) -> NSImage {
        let window = windowRect(for: region)
        let image = NSImage(size: size, flipped: false) { bounds in
            NSColor.black.setFill()
            bounds.fill()
            NSColor.black.withAlphaComponent(screenAlpha).setFill()
            screen.fill(using: .copy)
            NSColor.black.setFill()
            window.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
