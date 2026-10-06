import Cocoa
import ScreenCaptureKit

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
