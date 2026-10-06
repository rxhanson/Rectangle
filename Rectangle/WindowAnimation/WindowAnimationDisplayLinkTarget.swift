import Cocoa
import QuartzCore

@available(macOS 14.0, *)
final class WindowAnimationDisplayLinkTarget: NSObject {
    private let onFrame: (TimeInterval) -> Void
    init(onFrame: @escaping (TimeInterval) -> Void) { self.onFrame = onFrame }
    @objc func tick(_ link: CADisplayLink) { onFrame(link.targetTimestamp) }
}
