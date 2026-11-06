import AppKit

enum WindowSizeConstraint {
    static func isExceeded(requested: CGRect, actual: CGRect, action: WindowAction) -> Bool {
        guard action.resizes, isValid(requested), isValid(actual) else { return false }

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
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let iconImage = NSImage(systemSymbolName: "arrow.down.forward.and.arrow.up.backward.rectangle", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)

        let imageView = NSImageView(image: iconImage ?? NSImage())
        imageView.contentTintColor = .labelColor
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: String(localized: "Minimum window size reached", comment: "Title of the on-screen message when a window cannot fit its requested size"))
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .labelColor

        let stackView = NSStackView(views: [imageView, title])
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            container.heightAnchor.constraint(equalToConstant: 48)
        ])

        contentView = container
    }

    func show(on screen: NSScreen, duration: TimeInterval = 3) {
        hide()
        guard let contentView else { return }
        let visibleFrame = screen.visibleFrame

        let targetWidth = min(contentView.fittingSize.width, visibleFrame.width - 32)
        let targetHeight: CGFloat = 48

        let frame = NSRect(x: visibleFrame.midX - targetWidth / 2,
                           y: min(visibleFrame.minY + 32, visibleFrame.maxY - targetHeight),
                           width: targetWidth,
                           height: targetHeight)

        setFrame(frame, display: true)
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
