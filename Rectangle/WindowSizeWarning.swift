/// WindowSizeWarning.swift

import Cocoa

enum WindowSizeConstraint {
    static func isExceeded(requested: CGRect, actual: CGRect, action: WindowAction) -> Bool {
        guard action.resizes, isValid(requested), isValid(actual) else { return false }

        // Ignore rounding differences, and windows limited by a maximum size.
        // AX minimum-size attributes are unavailable for many apps, so use the
        // achieved size after all of the window mover's attempts have finished.
        return actual.width > requested.width + 1 || actual.height > requested.height + 1
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }
}

final class WindowSizeWarning: NSPanel {
    private static var current: WindowSizeWarning?
    static var shared: WindowSizeWarning {
        if let current { return current }
        let warning = WindowSizeWarning()
        current = warning
        return warning
    }
    static func hideCurrent() { current?.hide() }

    private static let padding: CGFloat = 16.8
    private var dismissal: DispatchWorkItem?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        let radius: CGFloat = 14
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = true

        // Mask the material itself so its blur does not bleed outside the rounded corners.
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        container.maskImage = mask

        let icon = WindowSizeWarningIcon()
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        let title = NSTextField(labelWithString: NSLocalizedString("windowSizeWarningTitle", tableName: "Main", value: "Minimum size reached", comment: "Window size warning title"))
        title.font = .systemFont(ofSize: 14.7, weight: .semibold)
        title.maximumNumberOfLines = 1
        title.lineBreakMode = .byTruncatingTail

        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding),
            icon.widthAnchor.constraint(equalToConstant: 33.6),
            icon.heightAnchor.constraint(equalToConstant: 25.2),
            icon.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.padding),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9.8),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            title.centerYAnchor.constraint(equalTo: icon.centerYAnchor)
        ])
        contentView = container
    }

    func show(on screen: NSScreen, duration: TimeInterval = 3) {
        hide()
        guard !Defaults.showMinimumWindowSizeWarning.userDisabled else { return }
        guard let contentView else { return }
        let visibleFrame = screen.adjustedVisibleFrame()
        let fittingSize = contentView.fittingSize
        let width = min(fittingSize.width, visibleFrame.width - 32)
        guard width > Self.padding * 2, visibleFrame.height > 0 else { return }
        let height = min(fittingSize.height, visibleFrame.height)
        setFrame(NSRect(x: visibleFrame.midX - width / 2,
                        y: min(visibleFrame.minY + 32, visibleFrame.maxY - height),
                        width: width, height: height), display: true)
        orderFrontRegardless()

        let dismissal = DispatchWorkItem { [weak self] in self?.hide() }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        orderOut(nil)
    }

    deinit {
        dismissal?.cancel()
    }
}

private final class WindowSizeWarningIcon: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.scaleX(by: bounds.width / 48, yBy: bounds.height / 36)
        transform.concat()
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        let outline = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 48, height: 36).insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        outline.lineWidth = 2
        outline.stroke()

        let arrows = NSBezierPath()
        arrows.lineWidth = 2.5
        arrows.lineCapStyle = .round
        arrows.lineJoinStyle = .round
        arrows.move(to: NSPoint(x: 14, y: 26))
        arrows.line(to: NSPoint(x: 22, y: 18))
        arrows.move(to: NSPoint(x: 16, y: 18))
        arrows.line(to: NSPoint(x: 22, y: 18))
        arrows.line(to: NSPoint(x: 22, y: 24))
        arrows.move(to: NSPoint(x: 34, y: 10))
        arrows.line(to: NSPoint(x: 26, y: 18))
        arrows.move(to: NSPoint(x: 26, y: 12))
        arrows.line(to: NSPoint(x: 26, y: 18))
        arrows.line(to: NSPoint(x: 32, y: 18))
        arrows.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
