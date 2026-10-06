import Cocoa
import QuartzCore

/// Readbacks are reusable only until a write invalidates the affected geometry.
final class WindowAnimationReadCache {
    var position: CGPoint?
    var size: CGSize?
    var server: CGRect?
    func invalidate() { position = nil; size = nil; server = nil }
}
