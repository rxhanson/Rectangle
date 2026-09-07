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
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        let title = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "windowSizeWarningTitle", tableName: "Main", value: "Minimum window size reached",
            comment: "Title of the on-screen message when a window cannot fit its requested size"))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let message = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "windowSizeWarningMessage", tableName: "Main",
            value: "Unable to resize window smaller. Windows may overlap.",
            comment: "Explains that an app can prevent a window from shrinking to the requested layout"))
        message.font = .systemFont(ofSize: NSFont.systemFontSize)

        labels = [title, message]
        for label in labels {
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            message.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            message.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        contentView = container
    }

    func show(on screen: NSScreen, duration: TimeInterval = 3) {
        hide()
        guard let contentView else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(360, visibleFrame.width - 32)
        guard width > 36, visibleFrame.height > 0 else { return }

        // Fix the text width before measuring so localized messages can wrap.
        labels.forEach { $0.preferredMaxLayoutWidth = width - 36 }
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
