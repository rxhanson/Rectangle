import Cocoa
import ScreenCaptureKit

/// A pointer-transparent drag preview below the handle, limited to the pair.
final class WindowDividerOverlay: NSPanel {
    let guide = WindowDividerGuide(frame: .zero)
    var snapshotScreenFrame: CGRect?
    private let fade = PreviewOpacityAnimation()
    static let fadeDuration: TimeInterval = 0.08
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.transient, .moveToActiveSpace]
        guide.wantsLayer = true
        contentView = guide
    }

    func show(in frame: CGRect, divider: CGFloat, gap: CGFloat, axis: WindowSplitAxis = .horizontal,
              below handle: WindowDividerPanel) {
        cancelFade()
        guide.backdrop.isHidden = false
        guide.decoration.isHidden = false
        if let layer = guide.layer { fade.set(layer, to: 1, duration: 0) }
        // Reserve transparent space before capture so freezing the native
        // shadows does not resize the panel during the image handoff.
        let coverage = snapshotScreenFrame.map {
            WindowDividerSnapshot.coverageFrame(for: frame, screenFrame: $0)
        } ?? frame
        setFrame(coverage, display: false)
        guide.previewBounds = frame.offsetBy(dx: -coverage.minX, dy: -coverage.minY)
        guide.gap = gap
        guide.axis = axis
        guide.dividerX = axis == .horizontal ? divider - frame.minX : frame.maxY - CGPoint(x: 0, y: divider).screenFlipped.y
        if !isVisible { orderFront(nil) }
        if handle.isVisible { handle.order(.above, relativeTo: windowNumber) }
    }

    func freeze(_ image: CGImage) {
        guide.setFrozenImage(image)
    }

    func fadeOut(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime, completion: @escaping () -> Void) {
        cancelFade()
        guard let layer = guide.layer else { dismiss(); completion(); return }
        let remaining = max(0, Self.fadeDuration - (ProcessInfo.processInfo.systemUptime - startedAt))
        fade.set(layer, to: 0, duration: WindowAnimator.enabled ? remaining : 0,
                 timing: CAMediaTimingFunction(name: .linear)) { [weak self] in
            self?.dismiss()
            completion()
        }
    }

    func dismiss() {
        cancelFade()
        // Retire the surface before ordering it out to avoid a stale final frame.
        if let layer = guide.layer { fade.set(layer, to: 0, duration: 0) }
        orderOut(nil)
        guide.retire()
    }

    private func cancelFade() { fade.cancel() }

}
