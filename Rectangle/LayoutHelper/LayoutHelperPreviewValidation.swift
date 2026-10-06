import Cocoa
import ScreenCaptureKit

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
