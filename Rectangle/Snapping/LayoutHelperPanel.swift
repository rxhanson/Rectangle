import Cocoa

enum LayoutHelperAppearance {
    // The deployment SDK has no public native-window-radius accessor. Keep the
    // newer/legacy shapes in one place. The supplied macOS 27 reference has
    // an approximately 36 px corner at 2x scale (18 pt).
    static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { return 18 }
        return 10
    }
    static let outline = NSColor(calibratedWhite: 0.76, alpha: 1)
    static let selection = NSColor(calibratedWhite: 0.62, alpha: 1)
}

/// Preview geometry is independent of snap destinations and image arrival order.
struct LayoutHelperPreviewLayout {
    static let titleHeight: CGFloat = 40
    struct Result {
        let frames: [CGRect]
        let height: CGFloat
    }

    static func inset(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) / 8, min(size.width, size.height) < 320 ? 8 : 12)
    }

    static func arrange(sizes: [CGSize], in viewport: CGSize, compact: Bool = false) -> Result {
        let width = max(1, viewport.width)
        let height = max(1, viewport.height)
        let gap: CGFloat = 16
        let bases = sizes.map { raw -> CGSize in
            if compact { return CGSize(width: min(180, width), height: 100) }
            let source = raw.width.isFinite && raw.height.isFinite && raw.width > 0 && raw.height > 0
                ? raw : CGSize(width: 800, height: 500)
            // Shared 36% scale, a readability floor for tiny windows, and a cap
            // prevent a huge source window from taking over the chooser.
            let scale = min(max(0.36, 120 / max(source.width, source.height)),
                            min(420, width) / source.width, 260 / source.height)
            return CGSize(width: source.width * scale, height: source.height * scale)
        }
        func pack(_ scale: CGFloat) -> Result {
            var rows: [[CGSize]] = []
            var row: [CGSize] = []
            var used: CGFloat = 0
            for base in bases {
                let size = CGSize(width: base.width * scale, height: base.height * scale + titleHeight)
                if !row.isEmpty && used + gap + size.width > width {
                    rows.append(row); row = []; used = 0
                }
                used += (row.isEmpty ? 0 : gap) + size.width
                row.append(size)
            }
            if !row.isEmpty { rows.append(row) }
            let rowHeights = rows.map { $0.map(\.height).max() ?? 0 }
            let total = rowHeights.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * gap
            var y = max(0, (height - total) / 2)
            var frames: [CGRect] = []
            for (index, row) in rows.enumerated() {
                let rowWidth = row.map(\.width).reduce(0, +) + CGFloat(row.count - 1) * gap
                var x = (width - rowWidth) / 2
                for size in row {
                    frames.append(CGRect(x: x, y: y + (rowHeights[index] - size.height) / 2,
                                         width: size.width, height: size.height))
                    x += size.width + gap
                }
                y += rowHeights[index] + gap
            }
            return Result(frames: frames, height: max(height, total))
        }
        // Stop shrinking at 60%; overflow then scrolls instead of becoming unreadable.
        for scale in [CGFloat(1), 0.9, 0.8, 0.7] {
            let result = pack(scale)
            if result.height <= height { return result }
        }
        return pack(0.6)
    }
}

/// A full-region input surface with a visually inset blur. Transparent margins
/// still belong to this window, so dismissal never clicks through to another app.
class LayoutHelperSurface: NSPanel {
    var onDismiss: (() -> Void)?
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
    }

    @discardableResult func prepare(in frame: CGRect) -> NSView {
        setFrame(frame, display: false)
        let root = LayoutHelperDocument(frame: CGRect(origin: .zero, size: frame.size))
        let inset = LayoutHelperPreviewLayout.inset(for: frame.size)
        let blur = LayoutHelperBackground(frame: root.bounds.insetBy(dx: inset, dy: inset))
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = LayoutHelperAppearance.cornerRadius
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = LayoutHelperAppearance.outline.cgColor
        blur.layer?.masksToBounds = true
        blur.layer?.contentsFormat = .RGBA8Uint
        if #available(macOS 26, *) { blur.layer?.preferredDynamicRange = .standard }
        root.addSubview(blur)
        // Foreground content must be a sibling, never a descendant of the
        // visual-effect view: vibrancy can otherwise alter opaque drawing live.
        let foreground = LayoutHelperDocument(frame: blur.frame)
        root.addSubview(foreground)
        contentView = root
        return foreground
    }

    /// Used by the event path and native hit-testing tests. Disabled cards are
    /// still controls: clicking one must not dismiss the sequence.
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

final class LayoutHelperPanel: LayoutHelperSurface {
    struct Item {
        let id: CGWindowID
        let title: String
        let icon: NSImage?
        let unavailableReason: String?
        var sourceSize: CGSize = CGSize(width: 800, height: 500)
        var isCurrentWindow = false
    }

    var onSelect: ((CGWindowID) -> Void)?
    var onPermission: (() -> Void)?
    var onVisiblePreviewsChanged: (() -> Void)?
    private(set) var keyboardSelection = false
    private var scrollObserver: NSObjectProtocol?
    private var visibleIDs: [CGWindowID] = []
    var visiblePreviewIDs: [CGWindowID] {
        cards.filter { $0.superview?.visibleRect.intersects($0.frame) == true }.map { $0.item.id }
    }
    private var cards: [LayoutHelperCard] = []
    private var backdrops: [LayoutHelperSurface] = []
    override var canBecomeKey: Bool { true }

    func owns(_ window: NSWindow?) -> Bool {
        window === self || backdrops.contains { $0 === window }
    }

    func containsPointerEvent(_ event: NSEvent) -> Bool {
        let point = event.cgEvent?.location.screenFlipped ?? NSEvent.mouseLocation
        return isVisible && (owns(event.window) || frame.contains(point)
            || backdrops.contains { $0.frame.contains(point) })
    }

    func show(in frame: CGRect, items: [Item], offerPermission: Bool, message: String? = nil,
              remainingRegions: [CGRect] = [], keyboardTriggered: Bool = false, images: [CGWindowID: NSImage] = [:]) {
        let existingIDs = isVisible && self.frame == frame ? Set(cards.map { $0.item.id }) : []
        backdrops.forEach { $0.orderOut(nil) }
        backdrops = remainingRegions.map { region in
            let backdrop = LayoutHelperSurface()
            backdrop.onDismiss = { [weak self] in self?.onDismiss?() }
            backdrop.prepare(in: region)
            backdrop.orderFront(nil)
            return backdrop
        }
        configure(in: frame, items: items, offerPermission: offerPermission, message: message,
                  keyboardTriggered: keyboardTriggered, images: images)
        makeFirstResponder(initialFirstResponder)
        contentView?.layoutSubtreeIfNeeded()
        // Render the cached thumbnails before committing the entrance, so a
        // freshly created layer does not spend its first frames empty.
        displayIfNeeded()
        animatePresentation(excluding: existingIDs)
        makeKeyAndOrderFront(nil)
    }

    /// Build the native view without ordering a window, also used for offscreen rendering.
    func configure(in frame: CGRect, items: [Item], offerPermission: Bool, message: String? = nil,
                   keyboardTriggered: Bool = false, images: [CGWindowID: NSImage] = [:]) {
        finishPresentation()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        keyboardSelection = keyboardTriggered
        let surface = prepare(in: frame)
        let width = surface.bounds.width
        let height = surface.bounds.height
        let close = NSButton(title: "×", target: self, action: #selector(dismissPicker))
        close.isBordered = false
        close.font = .systemFont(ofSize: 22, weight: .regular)
        close.frame = NSRect(x: max(0, width - 38), y: 6, width: 30, height: 30)
        close.setAccessibilityLabel("Dismiss Layout Helper")
        close.toolTip = "Dismiss (Escape)"
        surface.addSubview(close)

        var top: CGFloat = 44
        if let message {
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 12)
            label.frame = NSRect(x: 20, y: top, width: max(1, width - 40), height: 36)
            surface.addSubview(label)
            top += 40
        }
        let bottom: CGFloat = offerPermission ? 48 : 20
        var footerControls: [NSView] = []
        if offerPermission {
            let permission = LayoutHelperPermissionButton(target: self, action: #selector(requestPermission))
            let buttonWidth = min(156, max(1, width - 40))
            permission.frame = NSRect(x: (width - buttonWidth) / 2, y: max(top, height - 40), width: buttonWidth, height: 28)
            permission.toolTip = "Window previews need Screen Recording access. Icons and titles still work."
            surface.addSubview(permission)
            footerControls.append(permission)
        }
        let scroll = NSScrollView(frame: NSRect(x: 20, y: top, width: max(1, width - 40), height: max(1, height - top - bottom)))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        let document = LayoutHelperDocument()
        scroll.documentView = document
        surface.addSubview(scroll)

        let arrangement = LayoutHelperPreviewLayout.arrange(sizes: items.map(\.sourceSize), in: scroll.contentSize, compact: offerPermission)
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: arrangement.height)
        cards = zip(items, arrangement.frames).map { item, frame in
            let card = LayoutHelperCard(item: item)
            card.frame = frame
            card.preview = images[item.id]
            card.target = self
            card.action = #selector(selectCard(_:))
            document.addSubview(card)
            return card
        }
        // Explicit traversal keeps focus in stable candidate order.
        let controls: [NSView] = cards.filter(\.isEnabled) + footerControls + [close]
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
        initialFirstResponder = cards.first(where: { $0.isEnabled }) ?? close
        scroll.contentView.postsBoundsChangedNotifications = true
        visibleIDs = visiblePreviewIDs
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.finishPresentation()
                let ids = self.visiblePreviewIDs
                if ids != self.visibleIDs { self.visibleIDs = ids; self.onVisiblePreviewsChanged?() }
            }
    }

    func updateImage(_ image: NSImage, for id: CGWindowID) {
        cards.first { $0.item.id == id }?.preview = image
    }

    /// Each visible card settles independently while layout and hit testing
    /// retain their final geometry. Input can finish every entrance immediately.
    func animatePresentation(excluding existingIDs: Set<CGWindowID> = [],
                             reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        finishPresentation()
        let entering = cards.filter {
            !existingIDs.contains($0.item.id) && $0.superview?.visibleRect.intersects($0.frame) == true
        }
        let largest = entering.map { sqrt($0.frame.width * $0.frame.height) }.max() ?? 1
        let stagger = min(0.028, 0.1 / Double(max(1, entering.count - 1)))
        let start = CACurrentMediaTime()
        for (index, card) in entering.enumerated() {
            guard let layer = card.layer else { continue }
            let weight = min(1, sqrt(card.frame.width * card.frame.height) / max(1, largest))
            let cadence = CGFloat(index % 3) / 2
            let duration = reduceMotion ? 0.083 : 0.24 + Double(weight) * 0.055 + Double(cadence) * 0.025
            let delay = reduceMotion ? 0 : Double(index) * stagger
            var animations: [CAAnimation] = []
            if !reduceMotion {
                let scale: CGFloat = 0.96
                let anchor = CGPoint(x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
                                     y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)
                var transform = CATransform3DMakeScale(scale, scale, 1)
                transform.m41 = (anchor.x - layer.bounds.midX) * (scale - 1)
                transform.m42 = (anchor.y - layer.bounds.midY) * (scale - 1) - (12 + weight * 8 + cadence * 2)
                let settle = CABasicAnimation(keyPath: "transform")
                settle.fromValue = NSValue(caTransform3D: transform)
                settle.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                settle.duration = duration
                settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.75, 0.25, 1)
                animations.append(settle)

                let shadow = CABasicAnimation(keyPath: "shadowRadius")
                shadow.fromValue = 14 + weight * 6
                shadow.toValue = layer.shadowRadius
                shadow.duration = duration
                shadow.timingFunction = settle.timingFunction
                animations.append(shadow)
                let depth = CABasicAnimation(keyPath: "shadowOffset")
                depth.fromValue = NSValue(size: CGSize(width: 0, height: 10 + weight * 4))
                depth.toValue = NSValue(size: layer.shadowOffset)
                depth.duration = duration
                depth.timingFunction = settle.timingFunction
                animations.append(depth)
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = reduceMotion ? duration : 0.1
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animations.append(fade)
            let entrance = CAAnimationGroup()
            entrance.animations = animations
            entrance.duration = duration
            entrance.beginTime = layer.convertTime(start + delay, from: nil)
            // Hold the initial appearance during the stagger without timers or
            // delayed callbacks that could outlive this panel.
            entrance.fillMode = .backwards
            layer.add(entrance, forKey: "layoutHelperEntrance")
        }
    }

    private func finishPresentation() {
        for card in cards {
            card.layer?.removeAnimation(forKey: "layoutHelperEntrance")
            card.layer?.removeAnimation(forKey: "layoutHelperEntranceOpacity")
        }
    }

    func dismiss() {
        finishPresentation()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        orderOut(nil)
        backdrops.forEach { $0.orderOut(nil) }
        backdrops.removeAll()
        cards.removeAll()
        contentView = nil
    }

    override func sendEvent(_ event: NSEvent) {
        // Resolve visual and hit-test positions immediately for early input.
        // No completion callbacks can reopen a dismissed or replaced panel.
        if [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel].contains(event.type) {
            finishPresentation()
        }
        if event.type == .leftMouseDown { setKeyboardSelection(false) }
        if event.type == .keyDown, [48, 123, 124, 125, 126, 36, 76, 49].contains(event.keyCode) {
            setKeyboardSelection(true)
            if [123, 124, 125, 126].contains(event.keyCode) {
                moveSelection(keyCode: event.keyCode)
                return
            }
            if [36, 76].contains(event.keyCode), let card = firstResponder as? LayoutHelperCard {
                card.performClick(nil)
                return
            }
        }
        super.sendEvent(event)
    }

    private func setKeyboardSelection(_ enabled: Bool) {
        keyboardSelection = enabled
        cards.forEach { $0.needsDisplay = true }
    }

    private func moveSelection(keyCode: UInt16) {
        let eligible = cards.filter(\.isEnabled)
        guard !eligible.isEmpty else { return }
        let current = firstResponder as? LayoutHelperCard
        var destination: LayoutHelperCard?
        if let current, let index = eligible.firstIndex(of: current) {
            if keyCode == 123 || keyCode == 124 {
                let delta = keyCode == 123 ? -1 : 1
                destination = eligible[(index + delta + eligible.count) % eligible.count]
            } else {
                let down = keyCode == 125
                destination = eligible.filter { down ? $0.frame.midY > current.frame.midY + 1 : $0.frame.midY < current.frame.midY - 1 }
                    .min { a, b in
                        let aDistance = abs(a.frame.midY - current.frame.midY) * 2 + abs(a.frame.midX - current.frame.midX)
                        let bDistance = abs(b.frame.midY - current.frame.midY) * 2 + abs(b.frame.midX - current.frame.midX)
                        return aDistance < bDistance
                    }
            }
        }
        if let destination = destination ?? current ?? eligible.first {
            makeFirstResponder(destination)
            destination.scrollToVisible(destination.bounds)
        }
    }

    @objc private func dismissPicker() { onDismiss?() }
    @objc private func requestPermission() { onPermission?() }
    @objc private func selectCard(_ sender: LayoutHelperCard) { onSelect?(sender.item.id) }
}

private final class LayoutHelperBackground: NSVisualEffectView {
    override var isFlipped: Bool { true }

}

private final class LayoutHelperDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class LayoutHelperCard: NSButton {
    let item: LayoutHelperPanel.Item
    var preview: NSImage? { didSet { needsDisplay = true } }
    override var allowsVibrancy: Bool { false }
    override var isFlipped: Bool { true }

    init(item: LayoutHelperPanel.Item) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        title = item.title
        isEnabled = item.unavailableReason == nil
        let status = item.unavailableReason ?? (item.isCurrentWindow ? "Current window".localized : nil)
        toolTip = status.map { "\(item.title) — \($0)" } ?? item.title
        setAccessibilityLabel(toolTip)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: 2)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let radius = min(LayoutHelperAppearance.cornerRadius, min(bounds.width, bounds.height) / 2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func draw(_ dirtyRect: NSRect) {
        let selected = isEnabled && (window as? LayoutHelperPanel)?.keyboardSelection == true && window?.firstResponder === self
        let lineWidth: CGFloat = selected ? 2 : 1
        let radius = min(LayoutHelperAppearance.cornerRadius, min(bounds.width, bounds.height) / 2)
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        // An opaque backing also flattens alpha in captured windows and fallback icons.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor(srgbRed: dark ? 0.12 : 1, green: dark ? 0.12 : 1, blue: dark ? 0.12 : 1, alpha: 1).setFill()
        bounds.fill()
        let imageArea = NSRect(x: 0, y: LayoutHelperPreviewLayout.titleHeight,
                               width: bounds.width, height: max(1, bounds.height - LayoutHelperPreviewLayout.titleHeight))
        if let image = preview ?? item.icon, image.size.width > 0, image.size.height > 0 {
            let cap: CGFloat = preview == nil ? 48 / max(image.size.width, image.size.height) : 1
            let scale = min(imageArea.width / image.size.width, imageArea.height / image.size.height, cap)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: imageArea.midX - size.width / 2, y: imageArea.midY - size.height / 2,
                                 width: size.width, height: size.height), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
        item.icon?.draw(in: NSRect(x: 16, y: 11, width: 18, height: 18), from: .zero,
                        operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        if item.isCurrentWindow {
            let status = "Current window".localized as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            let width = min(status.size(withAttributes: attributes).width + 12, max(1, bounds.width - 16))
            let badge = NSRect(x: 8, y: imageArea.minY + 6, width: width, height: 20)
            NSColor.controlBackgroundColor.withAlphaComponent(0.94).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
            status.draw(in: badge.insetBy(dx: 6, dy: 3), withAttributes: attributes)
        }
        (item.title as NSString).draw(in: NSRect(x: 44, y: 11, width: max(1, bounds.width - 60), height: 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        NSGraphicsContext.restoreGraphicsState()
        (selected ? LayoutHelperAppearance.selection : LayoutHelperAppearance.outline).setStroke()
        outline.lineWidth = lineWidth
        outline.stroke()
    }
}


/// Keeps the capture opt-in distinct from window candidates and readable over blur.
final class LayoutHelperPermissionButton: NSButton {
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        title = "Enable previews…"
        self.target = target
        self.action = action
        isBordered = false
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .labelColor
        focusRingType = .exterior
        setAccessibilityIdentifier("layoutHelperEnablePreviews")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isHighlighted ? NSColor.selectedControlColor : NSColor.controlBackgroundColor).withAlphaComponent(0.92).setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        super.draw(dirtyRect)
    }
}
