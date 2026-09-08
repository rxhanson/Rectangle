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
    private static let padding: CGFloat = 24
    private var dismissal: DispatchWorkItem?
    private var labels: [NSTextField] = []

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
        let radius: CGFloat = 20
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

        let title = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "windowSizeWarningTitle", tableName: "Main", value: "Minimum window size reached",
            comment: "Title of the on-screen message when a window cannot fit its requested size"))
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.alignment = .center

        let message = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "windowSizeWarningMessage", tableName: "Main",
            value: "Unable to resize window smaller.\nWindows may overlap.",
            comment: "Explains that an app can prevent a window from shrinking to the requested layout"))
        message.font = .systemFont(ofSize: NSFont.systemFontSize)
        message.textColor = .secondaryLabelColor
        message.alignment = .center

        labels = [title, message]
        for label in labels {
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding),
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 36),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 17),
            message.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            message.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.padding)
        ])
        contentView = container
    }

    func show(on screen: NSScreen, duration: TimeInterval = 3) {
        hide()
        guard let contentView else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(360, visibleFrame.width - 32)
        guard width > Self.padding * 2, visibleFrame.height > 0 else { return }

        // Fix the text width before measuring so localized messages can wrap.
        labels.forEach { $0.preferredMaxLayoutWidth = width - Self.padding * 2 }
        contentView.setFrameSize(NSSize(width: width, height: 0))
        contentView.layoutSubtreeIfNeeded()
        let height = min(contentView.fittingSize.height, visibleFrame.height)
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
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
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
