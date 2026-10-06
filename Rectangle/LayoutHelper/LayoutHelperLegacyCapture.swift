import Cocoa
import ScreenCaptureKit

/// Resolve optional WindowServer capture symbols without linking private frameworks.
/// The caller owns permission, identity and concurrency checks; capture runs off-main.
enum LayoutHelperLegacyCapture {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Capture = @convention(c) (UInt32, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32) -> Unmanaged<CFArray>?
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private static func lookup<T>(_ names: [String], as type: T.Type) -> T? {
        guard let library else { return nil }
        for name in names {
            if let symbol = dlsym(library, name) { return unsafeBitCast(symbol, to: type) }
        }
        return nil
    }
    static func capture(id: CGWindowID, limit: CGSize) -> CGImage? {
        guard CGPreflightScreenCaptureAccess(),
              let connection = lookup(["SLSMainConnectionID", "CGSMainConnectionID"], as: Connection.self),
              let capture = lookup(["CGSHWCaptureWindowList"], as: Capture.self) else { return nil }
        var windowID = id
        // Best resolution, full size, and no desktop clipping.
        let options: UInt32 = (1 << 8) | (1 << 19) | (1 << 11)
        guard let images = capture(connection(), &windowID, 1, options)?.takeRetainedValue() as? [CGImage],
              let image = images.first, LayoutHelperPreviewValidation.isValid(image) else { return nil }
        let pixels = LayoutHelperPreviewStore.pixelSize(for: CGSize(width: image.width, height: image.height),
            limit: limit, sourceScale: 1)
        guard let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: pixels))
        guard let preview = context.makeImage(), LayoutHelperPreviewValidation.isValid(preview) else { return nil }
        return preview
    }
}
