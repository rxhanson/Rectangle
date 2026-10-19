import Cocoa
import ScreenCaptureKit

/// Capture the background once per drag. Rectangle's blur and moving outlines
/// are rendered separately so the snapshot does not depend on the final split.
final class WindowDividerSnapshot {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func coverageFrame(for frame: CGRect, screenFrame: CGRect) -> CGRect {
        // AppKit coordinates: reserve the native shadow below the pair.
        CGRect(x: frame.minX, y: frame.minY - 64, width: frame.width,
               height: frame.height + 64).intersection(screenFrame)
    }

    private var contentTask: Any?
    private var capturing = false

    static var enabled: Bool {
        shouldCapture(enhanced: Defaults.windowDividerEnhanced.enabled) { WindowCapturePermission.previewsAllowed }
    }

    static func shouldCapture(enhanced: Bool, hasAccess: () -> Bool) -> Bool {
        enhanced && hasAccess()
    }

    func prepare() {
        guard #available(macOS 14, *), Self.enabled, !capturing, contentTask == nil else { return }
        contentTask = Task { try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    }

    func clear() {
        if #available(macOS 14, *), let task = contentTask as? Task<SCShareableContent?, Never> { task.cancel() }
        contentTask = nil
    }

    @MainActor func capture(frame: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) async -> CGImage? {
        guard #available(macOS 14, *), Self.enabled, !Task.isCancelled, !capturing else { return nil }
        if contentTask == nil { prepare() }
        // Cancellation does not stop an outstanding ScreenCaptureKit call.
        // A new drag uses its live guide until the old capture releases its slot.
        capturing = true
        defer { capturing = false }
        do {
            guard let task = contentTask as? Task<SCShareableContent?, Never>, let content = await task.value,
                  !Task.isCancelled, Self.enabled,
                  let display = content.displays.first(where: { $0.displayID == displayID }),
                  display.frame.contains(frame) else { return nil }
            let applications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard !applications.isEmpty else { return nil }
            let filter = SCContentFilter(display: display, excludingApplications: applications, exceptingWindows: [])
            let config = Self.configuration(frame: frame, displayFrame: display.frame, scale: scale)
            // captureImage can omit native window shadows on macOS 26. Keep
            // the composited sample buffer, including the reserved bottom edge.
            let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
            guard !Task.isCancelled, let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
            return await Task.detached(priority: .userInitiated) {
                let image = CIImage(cvPixelBuffer: buffer)
                return Self.imageContext.createCGImage(image, from: image.extent)
            }.value
        } catch { return nil }
    }

    @available(macOS 14, *) static func configuration(frame: CGRect, displayFrame: CGRect, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = frame.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
        config.width = max(1, Int((frame.width * scale).rounded()))
        config.height = max(1, Int((frame.height * scale).rounded()))
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }
}
