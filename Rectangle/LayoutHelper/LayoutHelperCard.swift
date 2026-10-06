import Cocoa

final class LayoutHelperCard: NSButton {
    private let artwork = LayoutHelperPreviewContent()
    private let foreground = LayoutHelperCardForeground()
    var item: LayoutHelperPanel.Item {
        didSet {
            title = item.title
            isEnabled = item.unavailableReason == nil
            updateAccessibilityStatus()
            artwork.icon = item.icon
            artwork.isMinimized = item.isMinimized
            artwork.needsDisplay = true
            foreground.needsDisplay = true
            needsDisplay = true
        }
    }
    var previewUnavailable = false {
        didSet { updateAccessibilityStatus() }
    }
    private func updateAccessibilityStatus() {
        let status = item.unavailableReason ?? (item.isMinimized ? "minimized" : item.isCurrentWindow ? String(localized: "Current window") : nil)
        let hints = [status, previewUnavailable ? "Preview unavailable" : nil].compactMap { $0 }
        toolTip = ([item.title] + hints).joined(separator: " — ")
        setAccessibilityLabel(toolTip)
    }
    var layoutSlot = CGRect.zero {
        didSet { updatePreviewFrame() }
    }
    private func updatePreviewFrame() {
        frame = LayoutHelperPreviewLayout.cardFrame(for: artwork.preview?.size, in: layoutSlot, isMinimized: item.isMinimized)
    }
    var preview: NSImage? {
        get { artwork.preview }
        set {
            if newValue != nil { previewUnavailable = false }
            artwork.setPreview(newValue, animated: !isHidden && window?.isVisible == true
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            updatePreviewFrame()
            needsDisplay = true
        }
    }
    override var allowsVibrancy: Bool { false }
    override var isFlipped: Bool { true }

    init(item: LayoutHelperPanel.Item) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        title = item.title
        isEnabled = item.unavailableReason == nil
        updateAccessibilityStatus()
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        refreshMaterialStyle()
        layer?.shadowRadius = 12
        layer?.shadowOffset = .zero
        artwork.wantsLayer = true
        artwork.icon = item.icon
        artwork.isMinimized = item.isMinimized
        artwork.setAccessibilityElement(false)
        addSubview(artwork)
        foreground.card = self
        foreground.wantsLayer = true
        foreground.setAccessibilityElement(false)
        addSubview(foreground)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refreshMaterialStyle() {
        layer?.shadowOpacity = 0.07
        focusRingType = .none
    }
    override func layout() {
        super.layout()
        layer?.shadowPath = LayoutHelperAppearance.cardPath(
            in: bounds.insetBy(dx: -1.5, dy: -1.5),
            radius: LayoutHelperAppearance.cardCornerRadius + 1.5)
        artwork.frame = NSRect(x: 0, y: LayoutHelperPreviewLayout.titleHeight,
                               width: bounds.width, height: max(1, bounds.height - LayoutHelperPreviewLayout.titleHeight))
        foreground.frame = bounds
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
        let selected = state == .on || (isEnabled && (window as? LayoutHelperPanel)?.keyboardSelection == true && window?.firstResponder === self)
        NSGraphicsContext.saveGraphicsState()
        // Match the screenshot's outer clip. Selection only changes the stroke,
        // so the title and screenshot keep the same edge when focus moves.
        NSBezierPath(cgPath: LayoutHelperAppearance.cardPath(in: bounds)).addClip()
        // An opaque backing also flattens alpha in captured windows and fallback icons.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor(srgbRed: dark ? 0.12 : 1, green: dark ? 0.12 : 1, blue: dark ? 0.12 : 1, alpha: 1).setFill()
        bounds.fill()
        let hasPreview = artwork.preview != nil
        if hasPreview {
            item.icon?.draw(in: NSRect(x: 16, y: 11, width: 18, height: 18), from: .zero,
                            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleX: CGFloat = hasPreview ? 44 : 16
        (item.title as NSString).draw(in: NSRect(x: titleX, y: 11, width: max(1, bounds.width - titleX - 16), height: 20), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        NSGraphicsContext.restoreGraphicsState()
        foreground.needsDisplay = true
    }

    func drawForeground() {
        let selected = state == .on || (isEnabled && (window as? LayoutHelperPanel)?.keyboardSelection == true && window?.firstResponder === self)
        let lineWidth: CGFloat = selected ? 2 : 1
        let outline = NSBezierPath(cgPath: LayoutHelperAppearance.cardPath(
            in: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            radius: LayoutHelperAppearance.cardCornerRadius - lineWidth / 2))
        let imageArea = NSRect(x: 0, y: LayoutHelperPreviewLayout.titleHeight,
                               width: bounds.width, height: max(1, bounds.height - LayoutHelperPreviewLayout.titleHeight))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        if item.isMinimized {
            if artwork.preview != nil {
                NSColor.gray.withAlphaComponent(0.08).setFill()
                imageArea.fill()
            }
            let status = "Minimized" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = status.size(withAttributes: attributes)
            let badge = NSRect(x: imageArea.midX - (size.width + 20) / 2,
                               y: imageArea.maxY - 12 - 24, width: size.width + 20, height: 24)
            NSColor(calibratedWhite: 0.16, alpha: 0.72).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
            status.draw(at: CGPoint(x: badge.midX - size.width / 2,
                                   y: badge.midY - size.height / 2), withAttributes: attributes)
        }
        if item.isCurrentWindow {
            let status = String(localized: "Current window") as NSString
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
        NSGraphicsContext.restoreGraphicsState()
        // Selection is an interaction cue, not a decoration on the glass.
        (selected ? LayoutHelperAppearance.selection : LayoutHelperAppearance.outline).setStroke()
        outline.lineWidth = lineWidth
        outline.stroke()
    }
}
