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
        // A visual-effect view must remain at full window opacity for AppKit to
        // composite its material correctly. The configured alpha tints its fill.
        self.alpha = usesBlur || accessibility.reduceTransparency ? 1 : min(1, max(0, alpha))
        fades = fadeRequested && !accessibility.reduceMotion && !accessibility.reduceTransparency
        animates = animationRequested && !accessibility.reduceMotion
    }
}

private final class FootprintContentView: NSView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

private final class FootprintShadowWindow: NSWindow {
    private let shadowLayer = CALayer()
    private let cutoutLayer = CAShapeLayer()
    private let padding: CGFloat = 96

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .modalPanel
        collectionBehavior = [.transient, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(shadowLayer)
        view.layer?.mask = cutoutLayer
        cutoutLayer.fillRule = .evenOdd
        shadowLayer.shadowColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).cgColor
        shadowLayer.shadowRadius = 32
        shadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        for layer in [view.layer, shadowLayer, cutoutLayer].compactMap({ $0 }) {
            layer.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) {
                layer.preferredDynamicRange = .standard
            } else if #available(macOS 14, *) {
                layer.wantsExtendedDynamicRangeContent = false
            }
        }
        contentView = view
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Shadow padding must extend offscreen without shifting the cutout
        // away from the preview when it reaches the top edge.
        frameRect
    }

    func update(around rect: CGRect, cornerRadius: CGFloat, isDark: Bool) {
        setFrame(rect.insetBy(dx: -padding, dy: -padding), display: false)
        let bounds = CGRect(origin: .zero, size: frame.size)
        let panel = CGRect(origin: CGPoint(x: padding, y: padding), size: rect.size)
        let radius = min(cornerRadius, min(panel.width, panel.height) / 2)
        let outline = CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let cutout = CGMutablePath()
        cutout.addRect(bounds)
        cutout.addPath(outline)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = outline
        shadowLayer.shadowOpacity = isDark ? 0.65 : 0.42
        cutoutLayer.frame = bounds
        // Remove the entire panel from the shadow, even behind transparent blur.
        cutoutLayer.path = cutout
        CATransaction.commit()
    }
}

class FootprintWindow: NSWindow {
    private let boxView = NSBox()
    private let effectView = NSVisualEffectView()
    private var shadowWindow: FootprintShadowWindow?
    private var plainCornerRadius: CGFloat = 5
    private var blurMaskRadius: CGFloat?
    private let accessibility: () -> FootprintAccessibility
    private let clock: () -> TimeInterval
    private var accessibilityObserver: NSObjectProtocol?
    private var showing = false
    private var frameAnimation: WindowFrameAnimation?
    private var fade: Fade?
    private var timer: Timer?

    private struct Fade {
        let from: CGFloat
        let to: CGFloat
        let start: TimeInterval
        let duration: TimeInterval
    }

    var presentation: FootprintPresentation {
        FootprintPresentation(blurRequested: Defaults.footprintBlur.enabled,
                              alpha: Defaults.footprintAlpha.cgFloat,
                              fadeRequested: !Defaults.footprintFade.userDisabled,
                              animationRequested: Defaults.footprintAnimationDurationMultiplier.value > 0,
                              accessibility: accessibility())
    }

    init(accessibility: @escaping () -> FootprintAccessibility = { .current },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.accessibility = accessibility
        self.clock = clock
        super.init(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        title = "Rectangle"
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        level = .modalPanel
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
        let radius: CGFloat
        if #available(macOS 26.0, *) {
            radius = 16
        } else if #available(macOS 11.0, *) {
            radius = 10
        } else {
            radius = 5
        }
        plainCornerRadius = radius
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = true
        effectView.material = .fullScreenUI
        // Inherit the system appearance so AppKit selects its light/dark material.
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        container.addSubview(effectView)
        boxView.boxType = .custom
        boxView.cornerRadius = radius
        boxView.wantsLayer = true
        boxView.autoresizingMask = [.width, .height]
        container.addSubview(boxView)
        // Keep the authored preview layers in SDR. NSVisualEffectView supplies
        // blur without Liquid Glass.
        for view in [container, effectView, boxView] {
            view.wantsLayer = true
            view.layer?.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) {
                view.layer?.preferredDynamicRange = .standard
            } else if #available(macOS 14, *) {
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
        let radius = Defaults.footprintBlur.enabled ? 12 : plainCornerRadius
        contentView?.layer?.cornerRadius = radius
        boxView.cornerRadius = radius
        if style.usesBlur, blurMaskRadius != radius {
            // Mask the material itself as well as the tint, so the compositor
            // cannot leave bright material outside the rounded surface.
            let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
                NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            mask.resizingMode = .stretch
            effectView.maskImage = mask
            blurMaskRadius = radius
        }
        effectView.isHidden = !style.usesBlur
        let outlineGray: CGFloat = isDark ? 0.7 : 0.35
        boxView.borderColor = style.usesBlur
            ? NSColor(srgbRed: outlineGray, green: outlineGray, blue: outlineGray, alpha: 0.35)
            : .lightGray
        boxView.borderWidth = CGFloat(Defaults.footprintBorderWidth.value)
        // Keep the native material fully applied.
        effectView.alphaValue = 1
        if style.usesBlur {
            boxView.borderWidth = UserDefaults.standard.object(forKey: Defaults.footprintBorderWidth.key) == nil
                ? 1 : max(0, CGFloat(Defaults.footprintBorderWidth.value))
        }
        let customColor = Defaults.footprintColor.typedValue?.nsColor
        let defaultTint: NSColor = Defaults.footprintBlur.enabled && !isDark ? .white : .black
        let color = customColor ?? defaultTint
        if accessibility().reduceTransparency {
            boxView.fillColor = color.withAlphaComponent(1)
        } else if style.usesBlur {
            // Alpha controls the tint while the native blur remains fully applied.
            let tintAlpha = min(1, max(0, Defaults.footprintAlpha.cgFloat))
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
        let shadow = shadowWindow ?? FootprintShadowWindow()
        shadowWindow = shadow
        let isDark = (contentView?.effectiveAppearance ?? effectiveAppearance)
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        shadow.update(around: frame, cornerRadius: boxView.cornerRadius, isDark: isDark)
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
    }

    func refreshAccessibility() {
        updateAppearance()
        if !presentation.animates { frameAnimation?.finish() }
        // System display changes take effect immediately, including a fade that
        // was already running when Reduce Motion/Transparency was enabled.
        fade = nil
        alphaValue = showing ? presentation.alpha : 0
        if !showing { hidePreview() }
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
        frameAnimation?.cancel()
        if !super.isVisible || alphaValue == 0 {
            let initial = presentation.animates ? origin.map { CGRect(origin: $0, size: .zero) } : nil
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
                                             write: { [weak self] frame in
            self?.setFrame(frame, display: true)
            return true
        }, cleanup: { [weak self] in
            self?.frameAnimation = nil
        }, completion: { [weak self] frame in
            self?.setFrame(frame, display: true)
        })
        startTimer()
    }

    override func orderFront(_ sender: Any?) {
        updateAppearance()
        showing = true
        if presentation.fades {
            super.orderFront(sender)
            startFade(to: presentation.alpha, duration: 0.18)
        } else {
            fade = nil
            alphaValue = presentation.alpha
            super.orderFront(sender)
        }
        updateShadow()
    }

    override func orderOut(_ sender: Any?) {
        showing = false
        frameAnimation?.cancel()
        if presentation.fades && super.isVisible {
            startFade(to: 0, duration: 0.12)
        } else {
            fade = nil
            alphaValue = 0
            hidePreview()
            stopTimerIfIdle()
        }
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
            timer?.invalidate()
            timer = nil
        }
    }
}
