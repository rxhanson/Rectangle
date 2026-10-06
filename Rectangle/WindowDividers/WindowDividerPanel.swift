import Cocoa
import ScreenCaptureKit

final class WindowDividerPanel: NSPanel {
    private(set) var axis: WindowSplitAxis = .horizontal
    var onBegin: ((CGFloat) -> Bool)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var onReset: (() -> Void)?
    private let handle = WindowDividerHandle(frame: CGRect(x: 0, y: 0, width: 18, height: 76))
    private let fade = PreviewOpacityAnimation()
    private var fadeCompletion: (() -> Void)?
    private(set) var isHiding = false
    var acceptsPointer: Bool { isVisible && !isHiding }
    func containsPointerEvent(_ event: NSEvent) -> Bool {
        let point = event.cgEvent?.location.screenFlipped ?? NSEvent.mouseLocation
        return acceptsPointer && (event.window === self || frame.contains(point))
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: handle.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.transient, .moveToActiveSpace]
        title = "Resize split"
        handle.wantsLayer = true
        contentView = handle
        acceptsMouseMovedEvents = true
    }

    func show(at center: CGPoint, axis: WindowSplitAxis = .horizontal) {
        self.axis = axis
        let size = axis.size(CGSize(width: 18, height: 76))
        setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                       width: size.width, height: size.height), display: true)
        invalidateCursorRects(for: handle)
        if acceptsPointer { handle.updateHoverCursor(); return }
        if !isVisible { handle.layer?.opacity = 0; orderFront(nil) }
        isHiding = false; ignoresMouseEvents = false
        startFade(to: 1)
        handle.updateHoverCursor()
    }

    func holdVisible() {
        cancelFade()
        isHiding = false; ignoresMouseEvents = false
        if let layer = handle.layer { fade.set(layer, to: 1, duration: 0) }
        handle.updateHoverCursor()
    }

    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        handle.releaseHoverCursor()
        if !isVisible { cancelFade(); completion?(); return }
        if isHiding && animated {
            if let completion { fadeCompletion = completion }
            return
        }
        isHiding = true; ignoresMouseEvents = true
        startFade(to: 0, animated: animated, completion: completion)
    }

    private func startFade(to target: CGFloat, animated: Bool = true, completion: (() -> Void)? = nil) {
        cancelFade()
        fadeCompletion = completion
        guard let layer = handle.layer else { completion?(); return }
        fade.set(layer, to: target, duration: animated && WindowAnimator.enabled ? 0.12 : 0,
                 timing: PreviewLayerTransition.smoothstep) { [weak self] in
            guard let self else { return }
            let completion = self.fadeCompletion
            self.fadeCompletion = nil
            if self.isHiding { self.orderOut(nil) }
            completion?()
        }
    }

    private func cancelFade() {
        fade.cancel()
        fadeCompletion = nil
    }
}
