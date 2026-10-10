import Cocoa
import ScreenCaptureKit

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

struct LayoutHelperPreviewKey: Hashable {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let width: Int
    let height: Int
    var captureWidth: Int = 420
    var captureHeight: Int = 260
    var captureScale: CGFloat = 1

    func on(_ screen: NSScreen) -> Self {
        let size = LayoutHelperPreviewResolution.shared.limit(on: screen)
        var key = self
        key.captureWidth = Int(size.width); key.captureHeight = Int(size.height)
        key.captureScale = screen.backingScaleFactor >= 2 ? 2 : 1
        return key
    }
}

/// Only worker-side validation constructs images delivered to the main owner.
struct LayoutHelperValidatedPreview {
    let image: CGImage
    init?(_ image: CGImage) {
        guard LayoutHelperPreviewValidation.isValid(image) else { return nil }
        self.image = image
    }
}

/// Reject degenerate or fully transparent captures before adding an opaque backing.
/// Solid colors and partially transparent content remain valid.
enum LayoutHelperPreviewValidation {
    static func validSourceSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 1 && size.height > 1
    }
    static func isValid(_ image: CGImage) -> Bool {
        guard image.width > 1, image.height > 1 else { return false }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let sampledContent = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
        }
        if sampledContent { return true }
        // Sampling can miss a narrow edge or isolated pixel. Before rejecting,
        // inspect every source pixel at its original resolution, in bounded tiles.
        // Floating-point alpha preserves faint content in higher-depth captures.
        let tileSize = 256
        var components = [Float](repeating: 0, count: tileSize * tileSize * 4)
        for y in stride(from: 0, to: image.height, by: tileSize) {
            for x in stride(from: 0, to: image.width, by: tileSize) {
                let width = min(tileSize, image.width - x)
                let height = min(tileSize, image.height - y)
                guard let tile = image.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { return false }
                let hasContent = components.withUnsafeMutableBytes { bytes -> Bool in
                    guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                        bitsPerComponent: 32, bytesPerRow: tileSize * 4 * MemoryLayout<Float>.size,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.floatComponents.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                    context.interpolationQuality = .none
                    context.draw(tile, in: CGRect(x: 0, y: 0, width: width, height: height))
                    let values = bytes.bindMemory(to: Float.self)
                    return (0..<height).contains { row in
                        (0..<width).contains { column in values[(row * tileSize + column) * 4 + 3] > 0 }
                    }
                }
                if hasContent { return true }
            }
        }
        return false
    }
}
