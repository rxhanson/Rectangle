import Cocoa
import ScreenCaptureKit

/// One capture budget per display, independent of candidate count and card layout.
final class LayoutHelperPreviewResolution {
    static let shared = LayoutHelperPreviewResolution()
    private var sizes: [CGDirectDisplayID: CGSize] = [:]
    private struct Input: Equatable {
        let size: CGSize
        let scale: CGFloat
    }
    private var inputs: [CGDirectDisplayID: Input] = [:]
    private var observer: NSObjectProtocol?

    static func limit(for available: CGSize, backingScale: CGFloat = 1) -> CGSize {
        let region = CGSize(width: available.width, height: available.height / 2)
        let inset = LayoutHelperPreviewLayout.inset(for: region)
        let scale = backingScale >= 2 ? CGFloat(2) : 1
        return CGSize(width: max(1, min(420, floor(region.width - inset * 2 - 40))) * scale, height: 260 * scale)
    }

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func refresh() {
        var live = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let key = id.uint32Value
            live.insert(key)
            let input = Input(size: screen.visibleFrame.size, scale: screen.backingScaleFactor)
            if inputs[key] != input {
                inputs[key] = input
                sizes[key] = Self.limit(for: input.size, backingScale: input.scale)
            }
        }
        sizes = sizes.filter { live.contains($0.key) }
        inputs = inputs.filter { live.contains($0.key) }
    }
    func limit(on screen: NSScreen) -> CGSize {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let size = sizes[id.uint32Value] else { return Self.limit(for: screen.visibleFrame.size, backingScale: screen.backingScaleFactor) }
        return size
    }
}
