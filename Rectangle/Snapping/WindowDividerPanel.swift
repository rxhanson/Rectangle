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

final class WindowDividerGuide: NSView {
    let backdrop = NSVisualEffectView(frame: .zero)
    let decoration = WindowDividerDecoration(frame: .zero)
    private(set) var frozenImage: NSImage?
    var previewBounds: CGRect? { didSet { needsLayout = true } }
    var axis: WindowSplitAxis = .horizontal { didSet { needsLayout = true } }
    var gap: CGFloat = 0 { didSet { needsLayout = true } }
    var dividerX: CGFloat = 0 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        backdrop.material = .fullScreenUI
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        let radius = FootprintStyle.cornerRadius
        backdrop.layer?.cornerRadius = radius
        backdrop.layer?.masksToBounds = true
        // Clip the material itself as well as its layer to avoid bright corners.
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        backdrop.maskImage = mask
        backdrop.layer?.contentsFormat = .RGBA8Uint
        if #available(macOS 26, *) { backdrop.layer?.preferredDynamicRange = .standard }
        // Cover the margins and gutter from the start of the drag. Rounded
        // outlines belong above the backdrop so they cannot cut holes in it.
        addSubview(backdrop)
        addSubview(decoration)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setFrozenImage(_ image: CGImage?) {
        frozenImage = image.map { NSImage(cgImage: $0, size: bounds.size) }
        backdrop.blendingMode = image == nil ? .behindWindow : .withinWindow
        backdrop.isHidden = false
        decoration.isHidden = false
        needsDisplay = true
    }

    func retire() {
        frozenImage = nil
        backdrop.blendingMode = .behindWindow
        backdrop.isHidden = true
        decoration.isHidden = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let preview = previewBounds ?? bounds
        backdrop.frame = preview
        decoration.frame = preview
        decoration.axis = axis
        decoration.dividerX = dividerX
        let bounds = axis.rect(CGRect(origin: .zero, size: preview.size))
        let leftEdge = max(0, min(bounds.width, dividerX - gap / 2))
        let rightEdge = max(leftEdge, min(bounds.width, dividerX + gap / 2))
        let regions = [CGRect(x: 0, y: 0, width: leftEdge, height: bounds.height),
                       CGRect(x: rightEdge, y: 0, width: bounds.width - rightEdge, height: bounds.height)]
        decoration.outlines = regions.map { region in
            let inset = LayoutHelperPreviewLayout.inset(for: region.size)
            let physical = axis.rect(region.insetBy(dx: inset, dy: inset))
            return axis == .horizontal ? physical : CGRect(x: physical.minX, y: preview.height - physical.maxY,
                                                           width: physical.width, height: physical.height)
        }
        decoration.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if let frozenImage {
            frozenImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor.clear.setFill()
            bounds.fill(using: .copy)
        }
    }
}

/// Transparent outlines keep the preview shape independent of blur coverage.
final class WindowDividerDecoration: NSView {
    var axis: WindowSplitAxis = .horizontal
    var dividerX: CGFloat = 0
    var outlines: [CGRect] = []

    private func line(thickness: CGFloat) -> CGRect {
        axis == .horizontal
            ? CGRect(x: dividerX - thickness / 2, y: 0, width: thickness, height: bounds.height)
            : CGRect(x: 0, y: bounds.height - dividerX - thickness / 2, width: bounds.width, height: thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        LayoutHelperAppearance.outline.setStroke()
        for frame in outlines {
            let radius = min(min(12, FootprintStyle.cornerRadius), min(frame.width, frame.height) / 2)
            let outline = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
            outline.lineWidth = 1
            outline.stroke()
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        line(thickness: 4).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        line(thickness: 1.5).fill()
    }
}

/// Capture the background once per drag. Rectangle's blur and moving outlines
/// are rendered separately so the snapshot does not depend on the final split.
final class WindowDividerSnapshot {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func coverageFrame(for frame: CGRect, screenFrame: CGRect) -> CGRect {
        // AppKit coordinates: reserve the native shadow below the pair.
        CGRect(x: frame.minX, y: frame.minY - 64, width: frame.width,
               height: frame.height + 64).intersection(screenFrame)
    }

    private var contentTask: Any?

    static var enabled: Bool {
        shouldCapture(enhanced: Defaults.windowDividerEnhanced.enabled) { LayoutHelperPermission.previewsAllowed }
    }

    static func shouldCapture(enhanced: Bool, hasAccess: () -> Bool) -> Bool {
        enhanced && hasAccess()
    }

    func prepare() {
        guard #available(macOS 14, *), Self.enabled else { return }
        contentTask = Task { try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    }

    func clear() {
        if #available(macOS 14, *), let task = contentTask as? Task<SCShareableContent?, Never> { task.cancel() }
        contentTask = nil
    }

    @MainActor func capture(frame: CGRect, displayID: CGDirectDisplayID, scale: CGFloat) async -> CGImage? {
        guard #available(macOS 14, *), Self.enabled, !Task.isCancelled else { return nil }
        do {
            if contentTask == nil { prepare() }
            guard let task = contentTask as? Task<SCShareableContent?, Never>, let content = await task.value,
                  !Task.isCancelled, Self.enabled,
                  let display = content.displays.first(where: { $0.displayID == displayID }),
                  display.frame.contains(frame) else { return nil }
            let applications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard !applications.isEmpty else { return nil }
            let filter = SCContentFilter(display: display, excludingApplications: applications, exceptingWindows: [])
            let config = Self.configuration(frame: frame, displayFrame: display.frame, scale: scale)
            // captureImage can omit native window shadows on macOS 26. Keep
            // the composited sample buffer, including the reserved bottom edge.
            let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
            guard !Task.isCancelled, let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
            return await Task.detached(priority: .userInitiated) {
                let image = CIImage(cvPixelBuffer: buffer)
                return Self.imageContext.createCGImage(image, from: image.extent)
            }.value
        } catch { return nil }
    }

    @available(macOS 14, *) static func configuration(frame: CGRect, displayFrame: CGRect, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = frame.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
        config.width = max(1, Int((frame.width * scale).rounded()))
        config.height = max(1, Int((frame.height * scale).rounded()))
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }
}

private final class WindowDividerHandle: NSView {
    private var dragging = false
    private var hoverTracking: NSTrackingArea?
    private var ownsCursor = false
    private var panel: WindowDividerPanel? { window as? WindowDividerPanel }
    private var resizeCursor: NSCursor { panel?.axis == .vertical ? .resizeUpDown : .resizeLeftRight }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Resize split")
        setAccessibilityHelp("Drag to resize both windows. Double-click to return to equal sizes.")
        toolTip = "Drag to resize both windows. Double-click for equal sizes."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: resizeCursor) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        // Cursor-update tracking does not support activeAlways. This panel
        // deliberately stays inactive, so set the cursor from mouse tracking.
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }
    func updateHoverCursor() {
        guard let panel, panel.acceptsPointer,
              dragging || bounds.contains(convert(panel.mouseLocationOutsideOfEventStream, from: nil)) else {
            releaseHoverCursor(); return
        }
        if !ownsCursor { resizeCursor.push(); ownsCursor = true }
        else { resizeCursor.set() }
    }
    func releaseHoverCursor() {
        if ownsCursor { NSCursor.pop(); ownsCursor = false }
    }
    override func mouseEntered(with event: NSEvent) { updateHoverCursor() }
    override func mouseMoved(with event: NSEvent) { updateHoverCursor() }
    override func mouseExited(with event: NSEvent) { if !dragging { releaseHoverCursor() } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { panel?.onReset?(); return }
        guard let panel else { return }
        // The global pointer may have advanced while AX validation runs.
        // Preserve the actual mouse-down point instead of dropping that motion.
        let downX = panel.axis.coordinate(panel.convertPoint(toScreen: event.locationInWindow).screenFlipped)
        dragging = panel.onBegin?(downX) == true
        updateHoverCursor()
    }
    override func mouseDragged(with event: NSEvent) {
        if dragging, let panel { panel.onDrag?(panel.axis.coordinate(NSEvent.mouseLocation.screenFlipped)) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { dragging = false; panel?.onEnd?() }
        updateHoverCursor()
    }
    override func accessibilityPerformPress() -> Bool { panel?.onReset?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6)
        (dark ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
        shape.fill()
        NSColor(calibratedWhite: dark ? 0.58 : 0.7, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        NSColor.secondaryLabelColor.setFill()
        let grip = panel?.axis == .vertical
            ? CGRect(x: bounds.midX - 14, y: bounds.midY - 1, width: 28, height: 2)
            : CGRect(x: bounds.midX - 1, y: bounds.midY - 14, width: 2, height: 28)
        NSBezierPath(roundedRect: grip,
                     xRadius: 1, yRadius: 1).fill()
    }
}
