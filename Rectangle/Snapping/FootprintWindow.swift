/// FootprintWindow.swift

import Cocoa

struct FootprintAccessibility {
    var reduceMotion: Bool
    var reduceTransparency: Bool

    static var current: Self {
        Self(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
             reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}

struct FootprintPresentation {
    let usesBlur: Bool
    let alpha: CGFloat
    let fades: Bool
    let animates: Bool

    init(blurRequested: Bool, alpha: CGFloat, fadeRequested: Bool,
         animationRequested: Bool, accessibility: FootprintAccessibility) {
        usesBlur = blurRequested && !accessibility.reduceTransparency
        // AppKit blur needs full window opacity; configured alpha controls its tint.
        self.alpha = usesBlur || accessibility.reduceTransparency ? 1 : min(1, max(0, alpha))
        fades = fadeRequested && !accessibility.reduceMotion && !accessibility.reduceTransparency
        animates = animationRequested && !accessibility.reduceMotion
    }
}

enum FootprintAnimationGeometry {
    static func initialFrame(in destination: CGRect, from origin: CGPoint) -> CGRect {
        // A zero-sized frame on a shared edge can attach to the neighboring
        // display's Space. Keep the first visible pixel inside the destination.
        let width = min(1, destination.width)
        let height = min(1, destination.height)
        return CGRect(x: min(max(origin.x, destination.minX), destination.maxX - width),
                      y: min(max(origin.y, destination.minY), destination.maxY - height),
                      width: width, height: height)
    }
}

private final class FootprintContentView: NSView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

enum FootprintStyle {
    static let previewLevel = NSWindow.Level.modalPanel
    static let cornerRadius: CGFloat = {
        if #available(macOS 26.0, *) { return 16 }
        return 10
    }()
    static let shadowPadding: CGFloat = 96
    static let shadowRadius: CGFloat = 32
    static let shadowOffset = CGSize(width: 0, height: -8)

    static func shadowOpacity(isDark: Bool) -> Float { isDark ? 0.65 : 0.42 }
    static func borderColor(isDark: Bool) -> NSColor {
        let gray: CGFloat = isDark ? 0.7 : 0.35
        return NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 0.35)
    }
    static var borderWidth: CGFloat {
        UserDefaults.standard.object(forKey: Defaults.footprintBorderWidth.key) == nil
            ? 1 : max(0, CGFloat(Defaults.footprintBorderWidth.value))
    }
}

/// Draw only the shadow outside the glass, keeping its transparent interior clear.
final class FootprintShadow {
    let container = CALayer()
    let shape = CALayer()
    let cutout = CAShapeLayer()
    let cornerRadius: CGFloat
    var layers: [CALayer] { [container, shape, cutout] }

    init(cornerRadius: CGFloat = FootprintStyle.cornerRadius) {
        self.cornerRadius = cornerRadius
        for layer in layers {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) { layer.preferredDynamicRange = .standard }
            else { layer.wantsExtendedDynamicRangeContent = false }
        }
        let padding = FootprintStyle.shadowPadding
        container.position = CGPoint(x: -padding, y: -padding)
        container.addSublayer(shape)
        container.mask = cutout
        cutout.fillRule = .evenOdd
        shape.shadowColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).cgColor
        shape.shadowRadius = FootprintStyle.shadowRadius
        shape.shadowOffset = FootprintStyle.shadowOffset
    }

    private func geometry(size: CGSize) -> (bounds: CGRect, outline: CGPath, cutout: CGPath) {
        let padding = FootprintStyle.shadowPadding
        let bounds = CGRect(x: 0, y: 0, width: size.width + 2 * padding, height: size.height + 2 * padding)
        let panel = CGRect(origin: CGPoint(x: padding, y: padding), size: size)
        let radius = min(cornerRadius, min(size.width, size.height) / 2)
        let outline = CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        cutout.addPath(outline)
        return (bounds, outline, cutout)
    }

    func update(rect: CGRect, duration: TimeInterval) {
        let geometry = geometry(size: rect.size)
        let padding = FootprintStyle.shadowPadding
        PreviewLayerTransition.set(container, "position", to: NSValue(point: CGPoint(x: rect.minX - padding, y: rect.minY - padding)), duration: duration)
        for layer in layers { PreviewLayerTransition.set(layer, "bounds", to: NSValue(rect: geometry.bounds), duration: duration) }
        PreviewLayerTransition.set(shape, "shadowPath", to: geometry.outline, duration: duration)
        PreviewLayerTransition.set(cutout, "path", to: geometry.cutout, duration: duration)
    }

}

class FootprintWindow: NSWindow {
    private let surface = NSView()
    private let effectView = NSVisualEffectView()
    private let decoration = CAShapeLayer()
    private let shadow = FootprintShadow()
    private let shadowView = NSView()
    private let fade = PreviewOpacityAnimation()
    private let accessibility: () -> FootprintAccessibility
    private var accessibilityObserver: NSObjectProtocol?
    private var showing = false
    private var closing = false
    private var destination = CGRect.zero
    private var geometryGeneration = UUID()
    private var moving = false
    private let capturePauseID = UUID()

    var presentation: FootprintPresentation {
        FootprintPresentation(blurRequested: Defaults.footprintBlur.enabled,
                              alpha: CGFloat(Defaults.effectiveFootprintAlpha),
                              fadeRequested: !Defaults.footprintFade.userDisabled,
                              animationRequested: Defaults.footprintAnimationDurationMultiplier.value > 0,
                              accessibility: accessibility())
    }

    init(initialFrame: CGRect = .zero,
         accessibility: @escaping () -> FootprintAccessibility = { .current }) {
        self.accessibility = accessibility
        super.init(contentRect: initialFrame, styleMask: .borderless, backing: .buffered, defer: false)
        title = "Rectangle"
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        level = FootprintStyle.previewLevel
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle]

        let root = FootprintContentView(frame: .zero)
        for view in [root, shadowView, surface, effectView] {
            view.wantsLayer = true
            view.layer?.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) { view.layer?.preferredDynamicRange = .standard }
            else { view.layer?.wantsExtendedDynamicRangeContent = false }
        }
        root.layer?.opacity = 0
        shadowView.layer?.addSublayer(shadow.container)
        root.addSubview(shadowView)
        root.addSubview(surface)
        surface.layer?.cornerRadius = FootprintStyle.cornerRadius
        surface.layer?.masksToBounds = true
        effectView.material = .fullScreenUI
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        surface.addSubview(effectView)
        surface.layer?.addSublayer(decoration)
        decoration.contentsScale = backingScaleFactor
        decoration.contentsFormat = .RGBA8Uint
        if #available(macOS 26, *) { decoration.preferredDynamicRange = .standard }
        let radius = FootprintStyle.cornerRadius
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        effectView.maskImage = mask
        contentView = root
        root.appearanceDidChange = { [weak self] in self?.updateAppearance() }
        updateAppearance()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAccessibility() }
    }

    deinit {
        LayoutHelperCaptureGate.shared.end(capturePauseID)
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    private func updateAppearance() {
        let style = presentation
        let requested = Defaults.footprintBlur.enabled ? Defaults.blurAppearance.value.appearance : nil
        if appearance?.name != requested?.name { appearance = requested }
        let dark = (contentView?.effectiveAppearance ?? effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = Defaults.footprintColor.typedValue?.nsColor
            ?? (Defaults.footprintBlur.enabled && !dark ? NSColor.white : NSColor.black)
        let tint = style.usesBlur ? min(1, max(0, CGFloat(Defaults.effectiveFootprintAlpha))) : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectView.isHidden = !style.usesBlur
        shadowView.isHidden = !style.usesBlur
        decoration.fillColor = color.withAlphaComponent(accessibility().reduceTransparency ? 1 : tint).cgColor
        decoration.strokeColor = (style.usesBlur ? FootprintStyle.borderColor(isDark: dark) : NSColor.lightGray).cgColor
        decoration.lineWidth = style.usesBlur ? FootprintStyle.borderWidth : max(0, CGFloat(Defaults.footprintBorderWidth.value))
        shadow.shape.shadowOpacity = FootprintStyle.shadowOpacity(isDark: dark)
        CATransaction.commit()
    }

    private var displayedRect: CGRect {
        let local = surface.layer?.presentation()?.frame ?? surface.frame
        return local.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    // The window stays fixed; only its contents move, including the live material.
    private func prepareHost(for rect: CGRect) {
        let screen = NSScreen.screens.max { a, b in
            let x = a.frame.intersection(rect), y = b.frame.intersection(rect)
            return max(0, x.width) * max(0, x.height) < max(0, y.width) * max(0, y.height)
        }
        let host = (screen?.frame ?? rect).union(rect).insetBy(dx: -FootprintStyle.shadowPadding, dy: -FootprintStyle.shadowPadding)
        guard frame != host else { return }
        let current = displayedRect
        stopGeometry()
        super.setFrame(host, display: false)
        shadowView.frame = CGRect(origin: .zero, size: host.size)
        setGeometry(current, duration: 0)
        decoration.contentsScale = screen?.backingScaleFactor ?? backingScaleFactor
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    private func setGeometry(_ rect: CGRect, duration: TimeInterval) {
        let local = rect.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let bounds = CGRect(origin: .zero, size: rect.size)
        let inset = decoration.lineWidth / 2
        let outline = bounds.insetBy(dx: min(inset, bounds.width / 2), dy: min(inset, bounds.height / 2))
        let radius = max(0, min(FootprintStyle.cornerRadius - inset, min(outline.width, outline.height) / 2))
        let path = CGPath(roundedRect: outline, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let generation = UUID()
        geometryGeneration = generation
        moving = duration > 0
        if moving { LayoutHelperCaptureGate.shared.begin(capturePauseID) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = WindowPreviewDeceleration.timingFunction
            context.allowsImplicitAnimation = duration > 0
            if duration > 0 {
                surface.animator().frame = local
                effectView.animator().frame = bounds
            } else {
                surface.frame = local
                effectView.frame = bounds
            }
            PreviewLayerTransition.set(decoration, "path", to: path, duration: duration)
            shadow.update(rect: local, duration: duration)
        } completionHandler: { [weak self] in
            guard let self, self.geometryGeneration == generation else { return }
            self.moving = false
            self.updateCaptureGate()
            self.tracePresentation("arrived")
        }
        updateCaptureGate()
    }

    private func stopGeometry() {
        geometryGeneration = UUID()
        moving = false
        let current = displayedRect
        surface.layer?.removeAllAnimations()
        effectView.layer?.removeAllAnimations()
        setGeometry(current, duration: 0)
    }

    func showPreview(in rect: CGRect, from origin: CGPoint?, duration: TimeInterval) {
        tracePresentation("target", target: rect)
        let fresh = !super.isVisible || (contentView?.layer?.presentation()?.opacity ?? contentView?.layer?.opacity ?? 0) == 0
        stopGeometry()
        prepareHost(for: rect)
        updateAppearance()
        if fresh {
            let initial = presentation.animates ? origin.map { FootprintAnimationGeometry.initialFrame(in: rect, from: $0) } : nil
            setGeometry(initial ?? rect, duration: 0)
            // Publish the new starting geometry before reading presentation layers again.
            CATransaction.flush()
        }
        orderFront(nil)
        destination = rect
        setGeometry(rect, duration: presentation.animates ? duration : 0)
    }

    func movePreview(to rect: CGRect, duration: TimeInterval) {
        stopGeometry()
        prepareHost(for: rect)
        destination = rect
        setGeometry(rect, duration: presentation.animates ? duration : 0)
    }

    override func orderFront(_ sender: Any?) {
        updateAppearance()
        showing = true
        super.orderFront(sender)
        startFade(to: presentation.alpha, duration: presentation.fades ? 0.12 : 0)
        tracePresentation("ordered")
    }

    override func orderOut(_ sender: Any?) {
        showing = false
        if closing { super.orderOut(sender); return }
        tracePresentation("dismiss")
        stopGeometry()
        startFade(to: 0, duration: presentation.fades && super.isVisible ? 0.09 : 0)
    }

    private func startFade(to opacity: CGFloat, duration: TimeInterval) {
        guard let layer = contentView?.layer else { return }
        if duration > 0 { LayoutHelperCaptureGate.shared.begin(capturePauseID) }
        fade.set(layer, to: opacity, duration: duration) { [weak self] in
            guard let self else { return }
            if !self.showing { self.hidePreview() }
            self.updateCaptureGate()
        }
        updateCaptureGate()
    }

    private func hidePreview() {
        super.orderOut(nil)
        tracePresentation("hidden")
    }

    private func updateCaptureGate() {
        if moving || fade.isAnimating { LayoutHelperCaptureGate.shared.begin(capturePauseID) }
        else { LayoutHelperCaptureGate.shared.end(capturePauseID) }
    }

    func refreshAccessibility() {
        updateAppearance()
        if !presentation.animates { stopGeometry(); setGeometry(destination, duration: 0) }
        startFade(to: showing ? presentation.alpha : 0, duration: 0)
    }

    override var isVisible: Bool {
        if StageUtil.stageCapable && StageUtil.stageEnabled && StageUtil.stageStripShow { return true }
        return realIsVisible
    }
    var realIsVisible: Bool { showing && super.isVisible }

    override func close() {
        closing = true
        showing = false
        fade.cancel()
        geometryGeneration = UUID()
        moving = false
        LayoutHelperCaptureGate.shared.end(capturePauseID)
        super.close()
    }

    private func tracePresentation(_ event: String, target: CGRect? = nil) {
        let rect = (target ?? displayedRect).screenFlipped
        WindowAnimationDiagnostics.event("footprint." + event, fields: ["windowID": windowNumber,
            "frame": [rect.minX, rect.minY, rect.width, rect.height],
            "alpha": contentView?.layer?.presentation()?.opacity ?? contentView?.layer?.opacity ?? 0,
            "showing": showing, "visible": super.isVisible])
    }
}
