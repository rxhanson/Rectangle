import Cocoa

/// A full-region input surface with a visually inset blur. Transparent margins
/// still belong to this window, so dismissal never clicks through to another app.
class LayoutHelperSurface: NSPanel {
    var onDismiss: (() -> Void)?
    private var frameTransition: Timer?
    private var appearanceObservers: [NSObjectProtocol] = []
    private(set) var destinationFrame: CGRect?

    func stopFrameTransition() {
        frameTransition?.invalidate()
        frameTransition = nil
        destinationFrame = nil
    }

    func transitionFrame(to target: CGRect, duration: TimeInterval) {
        stopFrameTransition()
        let start = frame
        guard duration > 0, start != target else { setFrame(target, display: true); return }
        destinationFrame = target
        let began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
            let progress = CGFloat(1 - pow(1 - t, 3))
            self.setFrame(CGRect(x: start.minX + (target.minX - start.minX) * progress,
                                 y: start.minY + (target.minY - start.minY) * progress,
                                 width: start.width + (target.width - start.width) * progress,
                                 height: start.height + (target.height - start.height) * progress), display: true)
            if t == 1 { self.stopFrameTransition() }
        }
        frameTransition = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .moveToActiveSpace]
        title = "Layout Helper"
        setAccessibilityLabel("Layout Helper")
        updateAppearance()
        for name in [Notification.Name.blurStyleChanged, .blurAppearanceChanged, .configImported] {
            appearanceObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateAppearance()
            })
        }
    }

    deinit { appearanceObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    private func updateAppearance() {
        let requested = Defaults.blurAppearance.value.appearance
        if appearance?.name != requested?.name { appearance = requested }
    }

    @discardableResult func prepare(in frame: CGRect, drawsBackground: Bool = true) -> NSView {
        stopFrameTransition()
        setFrame(frame, display: false)
        let root = LayoutHelperDocument(frame: CGRect(origin: .zero, size: frame.size))
        let inset = LayoutHelperPreviewLayout.inset(for: frame.size)
        let blur = LayoutHelperBlurView(frame: root.bounds.insetBy(dx: inset, dy: inset),
                                   cornerRadius: LayoutHelperAppearance.cornerRadius, flipped: true)
        if drawsBackground {
            let shadow = LayoutHelperShadow(frame: blur.frame, radius: min(12, inset))
            shadow.autoresizingMask = [.width, .height]
            blur.autoresizingMask = [.width, .height]
            root.addSubview(shadow)
            root.addSubview(blur)

        }
        let foreground: NSView
        if drawsBackground {
            foreground = blur.content
        } else {
            foreground = LayoutHelperDocument(frame: blur.frame)
            root.addSubview(foreground)
        }
        contentView = root
        return foreground
    }

    /// Disabled cards remain controls; clicking one must not dismiss the picker.
    func isBackground(at point: NSPoint) -> Bool {
        var hit = contentView?.hitTest(point)
        while let view = hit {
            if view is NSControl { return false }
            hit = view.superview
        }
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { onDismiss?(); return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if isBackground(at: event.locationInWindow) { onDismiss?(); return }
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
