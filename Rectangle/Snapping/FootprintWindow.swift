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
        // Use macOS 27's uniform window radius on both Liquid Glass releases.
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
    private var size: CGSize?

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

    func setSize(_ size: CGSize) {
        guard self.size != size else { return }
        self.size = size
        let geometry = geometry(size: size)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layers.forEach { $0.bounds = geometry.bounds }
        shape.shadowPath = geometry.outline
        cutout.path = geometry.cutout
        CATransaction.commit()
    }

}

private final class FootprintShadowWindow: NSWindow {
    private let shadow: FootprintShadow
    let cornerRadius: CGFloat
    private let padding = FootprintStyle.shadowPadding

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        shadow = FootprintShadow(cornerRadius: cornerRadius)
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = FootprintStyle.previewLevel
        collectionBehavior = [.transient, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        shadow.container.position = .zero
        view.layer?.addSublayer(shadow.container)
        contentView = view
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Allow shadow padding beyond screen edges without shifting the preview.
        frameRect
    }

    func update(around rect: CGRect, isDark: Bool) {
        setFrame(rect.insetBy(dx: -padding, dy: -padding), display: false)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadow.setSize(rect.size)
        shadow.shape.shadowColor = NSColor.black.cgColor
        shadow.shape.shadowRadius = FootprintStyle.shadowRadius
        shadow.shape.shadowOffset = FootprintStyle.shadowOffset
        shadow.shape.shadowOpacity = FootprintStyle.shadowOpacity(isDark: isDark)
        CATransaction.commit()
    }
}

class FootprintWindow: NSWindow {
    private let boxView = NSBox()
    private let effectView = NSVisualEffectView()
    private var shadowWindow: FootprintShadowWindow?
    private var blurMaskRadius: CGFloat?
    private let accessibility: () -> FootprintAccessibility
    private let clock: () -> TimeInterval
    private var accessibilityObserver: NSObjectProtocol?
    private var showing = false
    private var frameAnimation: WindowFrameAnimation?
    private var fade: Fade?
    private let capturePauseID = UUID()
    private var timer: Timer?

    private struct Fade {
        let from: CGFloat
        let to: CGFloat
        let start: TimeInterval
        let duration: TimeInterval
    }

    var presentation: FootprintPresentation {
        FootprintPresentation(blurRequested: Defaults.footprintBlur.enabled,
                              alpha: CGFloat(Defaults.effectiveFootprintAlpha),
                              fadeRequested: !Defaults.footprintFade.userDisabled,
                              animationRequested: Defaults.footprintAnimationDurationMultiplier.value > 0,
                              accessibility: accessibility())
    }


    private var cornerRadius: CGFloat {
        Defaults.footprintBlur.enabled ? 12 : FootprintStyle.cornerRadius
    }

    init(initialFrame: CGRect = .zero,
         accessibility: @escaping () -> FootprintAccessibility = { .current },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.accessibility = accessibility
        self.clock = clock
        super.init(contentRect: initialFrame, styleMask: .titled, backing: .buffered, defer: false)
        title = "Rectangle"
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        level = FootprintStyle.previewLevel
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        alphaValue = 0

        styleMask.insert(.fullSizeContentView)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior.insert(.transient)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.toolbarButton)?.isHidden = true

        let container = FootprintContentView(frame: .zero)
        container.wantsLayer = true
        let radius = cornerRadius
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = true
        effectView.material = .fullScreenUI
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        container.addSubview(effectView)
        boxView.boxType = .custom
        boxView.cornerRadius = radius
        boxView.wantsLayer = true
        boxView.autoresizingMask = [.width, .height]
        container.addSubview(boxView)
        // Keep custom preview layers in SDR.
        for view in [container, effectView, boxView] {
            view.wantsLayer = true
            view.layer?.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) {
                view.layer?.preferredDynamicRange = .standard
            } else {
                view.layer?.wantsExtendedDynamicRangeContent = false
            }
        }
        contentView = container
        container.appearanceDidChange = { [weak self] in self?.updateAppearance() }
        updateAppearance()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshAccessibility()
        }
    }

    deinit {
        LayoutHelperCaptureGate.shared.end(capturePauseID)
        timer?.invalidate()
        if let shadowWindow {
            removeChildWindow(shadowWindow)
            shadowWindow.close()
        }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
    }

    private func updateAppearance() {
        let style = presentation
        let requestedAppearance = Defaults.footprintBlur.enabled ? Defaults.blurAppearance.value.appearance : nil
        if appearance?.name != requestedAppearance?.name {
            appearance = requestedAppearance
        }
        let windowStyle: NSWindow.StyleMask = Defaults.footprintBlur.enabled ? .borderless : [.titled, .fullSizeContentView]
        if styleMask != windowStyle {
            styleMask = windowStyle
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton, .toolbarButton] {
                standardWindowButton(button)?.isHidden = true
            }
        }
        let isDark = (contentView?.effectiveAppearance ?? effectiveAppearance)
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let radius = cornerRadius
        contentView?.layer?.cornerRadius = radius
        boxView.cornerRadius = radius
        if style.usesBlur, blurMaskRadius != radius {
            // Clip the material itself to prevent bright corners outside the tint mask.
            let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
                NSColor.white.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            mask.resizingMode = .stretch
            effectView.maskImage = mask
            blurMaskRadius = radius
        }
        effectView.isHidden = !style.usesBlur
        effectView.alphaValue = 1
        boxView.borderColor = style.usesBlur
            ? FootprintStyle.borderColor(isDark: isDark)
            : .lightGray
        boxView.borderWidth = CGFloat(Defaults.footprintBorderWidth.value)
        if style.usesBlur {
            boxView.borderWidth = FootprintStyle.borderWidth
        }
        let customColor = Defaults.footprintColor.typedValue?.nsColor
        let defaultTint: NSColor = Defaults.footprintBlur.enabled && !isDark ? .white : .black
        let color = customColor ?? defaultTint
        boxView.alphaValue = 1
        if accessibility().reduceTransparency {
            boxView.fillColor = color.withAlphaComponent(1)
        } else if style.usesBlur {
            let tintAlpha = min(1, max(0, CGFloat(Defaults.effectiveFootprintAlpha)))
            boxView.fillColor = color.withAlphaComponent(tintAlpha)
        } else {
            boxView.fillColor = color
        }
        updateShadow()
    }



    private func updateShadow() {
        guard presentation.usesBlur, super.isVisible, !frame.isEmpty else {
            shadowWindow?.orderOut(nil)
            return
        }
        if let previous = shadowWindow, previous.cornerRadius != cornerRadius {
            removeChildWindow(previous)
            previous.close()
            shadowWindow = nil
        }
        let shadow = shadowWindow ?? FootprintShadowWindow(cornerRadius: cornerRadius)
        shadowWindow = shadow
        let isDark = (contentView?.effectiveAppearance ?? effectiveAppearance)
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        shadow.update(around: frame, isDark: isDark)
        shadow.alphaValue = alphaValue
        if shadow.parent != self {
            addChildWindow(shadow, ordered: .below)
        }
        if !shadow.isVisible {
            shadow.order(.below, relativeTo: windowNumber)
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateShadow()
    }

    override var alphaValue: CGFloat {
        get { super.alphaValue }
        set {
            super.alphaValue = newValue
            shadowWindow?.alphaValue = newValue
        }
    }

    private func hidePreview() {
        shadowWindow?.orderOut(nil)
        super.orderOut(nil)
        tracePresentation("hidden")
    }

    private func tracePresentation(_ event: String, target: CGRect? = nil) {
        let rect = (target ?? frame).screenFlipped
        WindowAnimationDiagnostics.event("footprint." + event, fields: ["windowID": windowNumber,
            "frame": [rect.minX, rect.minY, rect.width, rect.height],
            "alpha": alphaValue, "showing": showing, "visible": super.isVisible])
    }

    func refreshAccessibility() {
        updateAppearance()
        if !presentation.animates { frameAnimation?.finish() }
        // Apply accessibility changes immediately, including during an active fade.
        fade = nil
        alphaValue = showing ? presentation.alpha : 0
        if !showing {
            frameAnimation?.cancel()
            hidePreview()
        }
        stopTimerIfIdle()
    }

    override var isVisible: Bool {
        // Workaround for footprint getting pushed off of Stage Manager.
        if StageUtil.stageCapable && StageUtil.stageEnabled && StageUtil.stageStripShow {
            return true
        }
        return realIsVisible
    }

    var realIsVisible: Bool { showing && super.isVisible }

    func showPreview(in rect: CGRect, from origin: CGPoint?, duration: TimeInterval) {
        tracePresentation("target", target: rect)
        frameAnimation?.cancel()
        updateAppearance()
        if !super.isVisible || alphaValue == 0 {
            let initial = presentation.animates ? origin.map { FootprintAnimationGeometry.initialFrame(in: rect, from: $0) } : nil
            setFrame(initial ?? rect, display: false)
        }
        orderFront(nil)
        movePreview(to: rect, duration: duration)
    }

    func movePreview(to rect: CGRect, duration: TimeInterval) {
        frameAnimation?.cancel()
        guard presentation.animates, duration > 0, frame != rect else {
            setFrame(rect, display: true)
            stopTimerIfIdle()
            return
        }
        frameAnimation = WindowFrameAnimation(from: frame, to: rect, startTime: clock(), duration: duration,
                                             curve: WindowPreviewDeceleration.value,
                                             write: { [weak self] frame, _ in
            self?.setFrame(frame, display: true)
            return true
        }, cleanup: { [weak self] in
            self?.frameAnimation = nil
        }, completion: { [weak self] frame in
            self?.setFrame(frame, display: true)
            self?.tracePresentation("arrived")
        })
        startTimer()
    }

    override func orderFront(_ sender: Any?) {
        updateAppearance()
        showing = true
        if presentation.fades {
            super.orderFront(sender)
            startFade(to: presentation.alpha, duration: 0.12)
        } else {
            fade = nil
            alphaValue = presentation.alpha
            super.orderFront(sender)
        }
        updateShadow()
        tracePresentation("ordered")
    }

    override func orderOut(_ sender: Any?) {
        showing = false
        tracePresentation("dismiss")
        frameAnimation?.cancel()
        if presentation.fades && super.isVisible {
            startFade(to: 0, duration: 0.09)
        } else {
            fade = nil
            alphaValue = 0
            hidePreview()
            stopTimerIfIdle()
        }
    }

    override func close() {
        showing = false
        fade = nil
        frameAnimation?.cancel()
        timer?.invalidate()
        timer = nil
        LayoutHelperCaptureGate.shared.end(capturePauseID)
        shadowWindow?.orderOut(nil)
        super.close()
    }

    private func startFade(to alpha: CGFloat, duration: TimeInterval) {
        guard alphaValue != alpha else {
            fade = nil
            if !showing { hidePreview() }
            stopTimerIfIdle()
            return
        }
        fade = Fade(from: alphaValue, to: alpha, start: clock(), duration: duration)
        startTimer()
    }

    private func startTimer() {
        LayoutHelperCaptureGate.shared.begin(capturePauseID)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.advanceAnimations(at: self.clock())
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func advanceAnimations(at time: TimeInterval) {
        frameAnimation?.tick(at: time)
        if let fade {
            let progress = min(1, max(0, (time - fade.start) / fade.duration))
            alphaValue = fade.from + (fade.to - fade.from) * WindowAnimationCurve.value(at: progress)
            if progress >= 1 {
                self.fade = nil
                if !showing { hidePreview() }
            }
        }
        stopTimerIfIdle()
    }

    private func stopTimerIfIdle() {
        if frameAnimation == nil && fade == nil {
            LayoutHelperCaptureGate.shared.end(capturePauseID)
            timer?.invalidate()
            timer = nil
        }
    }
}
