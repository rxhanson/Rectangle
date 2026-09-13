/// FootprintWindow.swift

import Cocoa
import CoreImage

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

enum BlurPreviewStyle {
    // Approved in Snap Glow Studio; see tools/snap-glow-studio/presets/approved-pair.json.
    static let outlineWidth: CGFloat = 80
    static let outlineOverallOpacity: CGFloat = 0.87
    static let contrastWidth: CGFloat = 1.5
    static let contrastOpacity: Float = 0.35
    static let contrastSoftness: CGFloat = 2.5
    static func outlineColor(isDark: Bool) -> NSColor {
        isDark ? NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1) : .white
    }
    private static let outlineContext = CIContext(options: [.cacheIntermediates: false])

    static func outlineMask(radius: CGFloat) -> NSImage {
        let cap = outlineWidth + radius
        let size = cap * 2 + 1
        let scale: CGFloat = 2
        let pixels = Int(size * scale)
        let padding = ceil(outlineWidth * 2 * scale)
        let canvas = pixels + Int(padding * 2)
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let source = CGContext(data: nil, width: canvas, height: canvas,
                                     bitsPerComponent: 8, bytesPerRow: canvas * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: pixels * 4, bitsPerPixel: 32),
              let bytes = bitmap.bitmapData else { return image }
        let bounds = CGRect(x: padding, y: padding, width: CGFloat(pixels), height: CGFloat(pixels))
        let strokeWidth: CGFloat = 3.8
        let strokeInset = strokeWidth / 2
        source.setStrokeColor(CGColor(gray: 1, alpha: 1))
        source.setLineWidth(strokeWidth * scale)
        source.addPath(CGPath(roundedRect: bounds.insetBy(dx: strokeInset * scale, dy: strokeInset * scale),
                             cornerWidth: (radius - strokeInset) * scale,
                             cornerHeight: (radius - strokeInset) * scale, transform: nil))
        source.strokePath()
        guard let seed = source.makeImage() else { return image }
        let shape = CIImage(cgImage: seed)
        func blurredAlpha(radius: CGFloat) -> [Float] {
            let blurred = shape.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * scale])
            var result = [Float](repeating: 0, count: pixels * pixels * 4)
            result.withUnsafeMutableBytes { buffer in
                outlineContext.render(blurred, toBitmap: buffer.baseAddress!, rowBytes: pixels * 4 * MemoryLayout<Float>.size,
                                      bounds: bounds, format: .RGBAf, colorSpace: nil)
            }
            return result
        }
        // A continuous bright core plus three Gaussian halos, following the
        // same rounded path. Normalize each halo against a straight edge.
        let core = blurredAlpha(radius: 0)
        let tight = blurredAlpha(radius: 1.5)
        let medium = blurredAlpha(radius: 6)
        let broad = blurredAlpha(radius: 18)
        func halo(_ alpha: Float, radius: Double) -> Double {
            min(1, max(0, Double(alpha) * radius * sqrt(2 * .pi) / Double(strokeWidth)))
        }
        for y in 0..<pixels {
            for x in 0..<pixels {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                let qx = abs(point.x - size / 2) - (size / 2 - radius)
                let qy = abs(point.y - size / 2) - (size / 2 - radius)
                let distance = radius - hypot(max(qx, 0), max(qy, 0)) - min(max(qx, qy), 0)
                let entry = min(1, max(0, distance * scale))
                let tail = min(1, max(0, (distance - outlineWidth * 0.75) / (outlineWidth * 0.25)))
                let feather = entry * entry * (3 - 2 * entry) * (1 - tail * tail * (3 - 2 * tail))
                let offset = (y * pixels + x) * 4
                let coverage = 1 - (1 - Double(core[offset + 3]))
                    * (1 - 0.55 * halo(tight[offset + 3], radius: 1.5))
                    * (1 - 0.30 * halo(medium[offset + 3], radius: 6))
                    * (1 - 0.16 * halo(broad[offset + 3], radius: 18))
                let alpha = UInt8((min(1, max(0, coverage)) * Double(feather) * 255).rounded())
                for channel in 0..<4 { bytes[offset + channel] = alpha }
            }
        }
        bitmap.size = image.size
        image.addRepresentation(bitmap)
        return image
    }

    static let previewLevel = NSWindow.Level.modalPanel
    static let movingWindowLevel = NSWindow.Level(rawValue: previewLevel.rawValue + 1)
    static let cornerRadius: CGFloat = {
        // Use macOS 27's uniform window radius on both Liquid Glass releases.
        if #available(macOS 26.0, *) { return 16 }
        if #available(macOS 11.0, *) { return 10 }
        return 5
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

/// The selected fixture's opposite-color edge. It is independent of the
/// luminous mask so the main outline cannot paint over the fine border.
final class BlurPreviewContrastOutline {
    let layer = CAShapeLayer()
    private let outsideMask = CAShapeLayer()

    init() {
        layer.name = "outline-contrast"
        layer.zPosition = 10
        layer.fillColor = nil
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0.85
        outsideMask.fillRule = .evenOdd
        for item in [layer, outsideMask] {
            item.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) { item.preferredDynamicRange = .standard }
            else if #available(macOS 14, *) { item.wantsExtendedDynamicRangeContent = false }
        }
    }

    func update(bounds: CGRect, outline: CGRect, radius: CGFloat, isDark: Bool,
                visible: Bool, scale: CGFloat, outsideOnly: Bool = false) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.isHidden = !visible || outline.width <= BlurPreviewStyle.contrastWidth
            || outline.height <= BlurPreviewStyle.contrastWidth
        guard !layer.isHidden else { return }
        layer.frame = bounds
        layer.contentsScale = scale
        let inset = BlurPreviewStyle.contrastWidth / 2
        let path = CGPath(roundedRect: outline.insetBy(dx: inset, dy: inset),
                          cornerWidth: max(0, radius - inset), cornerHeight: max(0, radius - inset), transform: nil)
        layer.path = path
        layer.lineWidth = BlurPreviewStyle.contrastWidth
        let color = (isDark ? NSColor.white : NSColor.black).cgColor
        layer.strokeColor = color
        layer.shadowColor = color
        layer.shadowRadius = BlurPreviewStyle.contrastSoftness
        layer.shadowPath = path.copy(strokingWithWidth: BlurPreviewStyle.contrastWidth,
            lineCap: .round, lineJoin: .round, miterLimit: 1)
        // The companion window already carries the luminous outline's 87%
        // opacity. Compensate here so both halves of the soft edge remain 35%.
        layer.opacity = BlurPreviewStyle.contrastOpacity / (outsideOnly ? Float(BlurPreviewStyle.outlineOverallOpacity) : 1)
        if outsideOnly {
            let mask = CGMutablePath(); mask.addRect(bounds)
            mask.addRoundedRect(in: outline, cornerWidth: radius, cornerHeight: radius)
            outsideMask.frame = bounds; outsideMask.path = mask
            layer.mask = outsideMask
        } else { layer.mask = nil }
    }
}

/// Draw only the shadow outside the glass, keeping its transparent interior clear.
final class BlurPreviewShadow {
    let container = CALayer()
    let shape = CALayer()
    let cutout = CAShapeLayer()
    let cornerRadius: CGFloat
    var layers: [CALayer] { [container, shape, cutout] }
    private var size: CGSize?

    init(cornerRadius: CGFloat = BlurPreviewStyle.cornerRadius) {
        self.cornerRadius = cornerRadius
        for layer in layers {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) { layer.preferredDynamicRange = .standard }
            else if #available(macOS 14, *) { layer.wantsExtendedDynamicRangeContent = false }
        }
        let padding = BlurPreviewStyle.shadowPadding
        container.position = CGPoint(x: -padding, y: -padding)
        container.addSublayer(shape)
        container.mask = cutout
        cutout.fillRule = .evenOdd
        shape.shadowColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).cgColor
        shape.shadowRadius = BlurPreviewStyle.shadowRadius
        shape.shadowOffset = BlurPreviewStyle.shadowOffset
    }

    private func geometry(size: CGSize) -> (bounds: CGRect, outline: CGPath, cutout: CGPath) {
        let padding = BlurPreviewStyle.shadowPadding
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

    func animate(sizes: [CGSize], duration: TimeInterval, beginTime: CFTimeInterval,
                 timingFunction: CAMediaTimingFunction?, key: String) {
        for (layer, group) in prepareAnimations(sizes: sizes, duration: duration, timingFunction: timingFunction) {
            group.beginTime = layer.convertTime(beginTime, from: nil)
            layer.add(group, forKey: key)
        }
    }

    /// Construct paths before the shared compositor clock starts. Installation
    /// must remain separate so every display begins on the same time origin.
    func prepareAnimations(sizes: [CGSize], duration: TimeInterval,
                           timingFunction: CAMediaTimingFunction?) -> [(CALayer, CAAnimationGroup)] {
        guard sizes.count > 1 else { return [] }
        let samples = sizes.map { geometry(size: $0) }
        let times = sizes.indices.map { NSNumber(value: Double($0) / Double(sizes.count - 1)) }
        let bounds = samples.map { NSValue(rect: $0.bounds) }
        func keyframes(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values; animation.keyTimes = times
            animation.calculationMode = .linear; animation.duration = duration
            return animation
        }
        return layers.map { layer in
            var animations: [CAAnimation] = [keyframes("bounds", bounds)]
            if layer === shape { animations.append(keyframes("shadowPath", samples.map { $0.outline })) }
            if layer === cutout { animations.append(keyframes("path", samples.map { $0.cutout })) }
            let group = CAAnimationGroup()
            group.animations = animations; group.duration = duration
            group.timingFunction = timingFunction
            return (layer, group)
        }
    }

    func stop(key: String) { layers.forEach { $0.removeAnimation(forKey: key) } }
}

private final class FootprintShadowWindow: NSWindow {
    private let shadow: BlurPreviewShadow
    private let contrast = BlurPreviewContrastOutline()
    let cornerRadius: CGFloat
    private let padding = BlurPreviewStyle.shadowPadding

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        shadow = BlurPreviewShadow(cornerRadius: cornerRadius)
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = BlurPreviewStyle.previewLevel
        collectionBehavior = [.transient, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        shadow.container.position = .zero
        view.layer?.addSublayer(shadow.container)
        view.layer?.addSublayer(contrast.layer)
        contentView = view
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Allow shadow padding beyond screen edges without shifting the preview.
        frameRect
    }

    func update(around rect: CGRect, isDark: Bool, glow: Bool) {
        setFrame(rect.insetBy(dx: -padding, dy: -padding), display: false)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadow.setSize(rect.size)
        shadow.shape.shadowColor = (glow ? BlurPreviewStyle.outlineColor(isDark: isDark) : NSColor.black).cgColor
        shadow.shape.shadowRadius = glow ? 10 : BlurPreviewStyle.shadowRadius
        shadow.shape.shadowOffset = glow ? .zero : BlurPreviewStyle.shadowOffset
        shadow.shape.shadowOpacity = glow ? 0.85 : BlurPreviewStyle.shadowOpacity(isDark: isDark)
        CATransaction.commit()
        let bounds = CGRect(origin: .zero, size: frame.size)
        contrast.update(bounds: bounds, outline: bounds.insetBy(dx: padding, dy: padding),
            radius: cornerRadius, isDark: isDark, visible: glow,
            scale: screen?.backingScaleFactor ?? 1, outsideOnly: true)
    }
}

/// The renderer confirms coverage before the real window is revealed.
struct SnapPreviewHandoff {
    static let notification = Notification.Name("RectangleSnapPreviewHandoff")
    let windowID: CGWindowID
    let frame: CGRect
    let covered: Bool

    func post() { NotificationCenter.default.post(name: Self.notification, object: self) }
}

class FootprintWindow: NSWindow {
    private let boxView = NSBox()
    private let effectView = NSVisualEffectView()
    private var shadowWindow: FootprintShadowWindow?
    private var blurMaskRadius: CGFloat?
    private var blurMaskIsOutline = false
    private let outlineMask = CALayer()
    private let contrastOutline = BlurPreviewContrastOutline()
    private let frostedAnimationsEnabled: () -> Bool
    private let animationStyle: () -> WindowAnimationStyle
    private var handoffObserver: NSObjectProtocol?
    private var committedWindowID: CGWindowID?
    private var handoffDeadline: TimeInterval?
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
                              alpha: CGFloat(Defaults.effectiveFootprintAlpha),
                              fadeRequested: !Defaults.footprintFade.userDisabled,
                              animationRequested: Defaults.footprintAnimationDurationMultiplier.value > 0,
                              accessibility: accessibility())
    }

    var usesGlassOutline: Bool { animationStyle() == .frosted && frostedAnimationsEnabled() && presentation.usesBlur }

    private var cornerRadius: CGFloat {
        animationStyle() == .direct && Defaults.footprintBlur.enabled ? 12 : BlurPreviewStyle.cornerRadius
    }

    init(initialFrame: CGRect = .zero,
         accessibility: @escaping () -> FootprintAccessibility = { .current },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         frostedAnimationsEnabled: @escaping () -> Bool = { WindowAnimator.frostedEnabled },
         animationStyle: @escaping () -> WindowAnimationStyle = { Defaults.windowAnimationStyle.value }) {
        self.animationStyle = animationStyle
        self.frostedAnimationsEnabled = frostedAnimationsEnabled
        self.accessibility = accessibility
        self.clock = clock
        super.init(contentRect: initialFrame, styleMask: .titled, backing: .buffered, defer: false)
        title = "Rectangle"
        colorSpace = .sRGB
        isOpaque = false
        backgroundColor = .clear
        level = BlurPreviewStyle.previewLevel
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
        container.layer?.addSublayer(contrastOutline.layer)
        // Keep custom preview layers in SDR.
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
        handoffObserver = NotificationCenter.default.addObserver(forName: SnapPreviewHandoff.notification, object: nil, queue: .main) { [weak self] note in
            guard let handoff = note.object as? SnapPreviewHandoff else { return }
            self?.receiveSnapHandoff(handoff)
        }

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
        if let handoffObserver { NotificationCenter.default.removeObserver(handoffObserver) }
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
        let outline = usesGlassOutline
        contentView?.layer?.cornerRadius = radius
        boxView.cornerRadius = radius
        if style.usesBlur, blurMaskRadius != radius || blurMaskIsOutline != outline {
            // Clip the material itself to prevent bright corners outside the tint mask.
            let cap = outline ? BlurPreviewStyle.outlineWidth + radius : radius
            let mask: NSImage
            if outline {
                mask = BlurPreviewStyle.outlineMask(radius: radius)
            } else {
                mask = NSImage(size: NSSize(width: cap * 2 + 1, height: cap * 2 + 1), flipped: false) { rect in
                    NSColor.white.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                    return true
                }
            }
            mask.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
            mask.resizingMode = .stretch
            effectView.maskImage = mask
            if outline {
                outlineMask.contents = mask.cgImage(forProposedRect: nil, context: nil, hints: nil)
                let size = cap * 2 + 1
                outlineMask.contentsCenter = CGRect(x: cap / size, y: cap / size, width: 1 / size, height: 1 / size)
                outlineMask.contentsScale = screen?.backingScaleFactor ?? 1
                outlineMask.contentsFormat = .RGBA8Uint
            }
            blurMaskRadius = radius
            blurMaskIsOutline = outline
        }
        effectView.isHidden = !style.usesBlur || outline
        effectView.alphaValue = 1
        boxView.borderColor = style.usesBlur
            ? BlurPreviewStyle.borderColor(isDark: isDark)
            : .lightGray
        boxView.borderWidth = CGFloat(Defaults.footprintBorderWidth.value)
        if style.usesBlur {
            boxView.borderWidth = BlurPreviewStyle.borderWidth
        }
        if outline { boxView.borderWidth = 0 }
        let customColor = Defaults.footprintColor.typedValue?.nsColor
        let defaultTint: NSColor = Defaults.footprintBlur.enabled && !isDark ? .white : .black
        let color = customColor ?? defaultTint
        boxView.alphaValue = outline ? BlurPreviewStyle.outlineOverallOpacity : 1
        if outline {
            boxView.fillColor = BlurPreviewStyle.outlineColor(isDark: isDark)
        } else if accessibility().reduceTransparency {
            boxView.fillColor = color.withAlphaComponent(1)
        } else if style.usesBlur {
            let tintAlpha = min(1, max(0, CGFloat(Defaults.effectiveFootprintAlpha)))
            boxView.fillColor = color.withAlphaComponent(tintAlpha)
        } else {
            boxView.fillColor = color
        }
        updateOutlineMask()
        updateShadow()
    }

    private func updateOutlineMask() {
        let bounds = contentView?.bounds ?? .zero
        let isDark = (contentView?.effectiveAppearance ?? effectiveAppearance)
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        contrastOutline.update(bounds: bounds, outline: bounds, radius: cornerRadius,
            isDark: isDark, visible: usesGlassOutline, scale: screen?.backingScaleFactor ?? 1)
        guard usesGlassOutline, let bounds = contentView?.bounds else {
            boxView.layer?.mask = nil
            return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outlineMask.frame = bounds
        boxView.layer?.mask = outlineMask
        CATransaction.commit()
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
        shadow.update(around: frame, isDark: isDark, glow: usesGlassOutline)
        shadow.alphaValue = alphaValue * (usesGlassOutline ? BlurPreviewStyle.outlineOverallOpacity : 1)
        if shadow.parent != self {
            addChildWindow(shadow, ordered: .below)
        }
        if !shadow.isVisible {
            shadow.order(.below, relativeTo: windowNumber)
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateOutlineMask()
        updateShadow()
    }

    override var alphaValue: CGFloat {
        get { super.alphaValue }
        set {
            super.alphaValue = newValue
            shadowWindow?.alphaValue = newValue * (usesGlassOutline ? BlurPreviewStyle.outlineOverallOpacity : 1)
        }
    }

    private func hidePreview() {
        shadowWindow?.orderOut(nil)
        super.orderOut(nil)
        tracePresentation("hidden")
    }

    private func tracePresentation(_ event: String, target: CGRect? = nil) {
        let rect = (target ?? frame).screenFlipped
        WindowFrostDiagnostics.event("footprint." + event, fields: ["windowID": windowNumber,
            "shadowWindowID": shadowWindow?.windowNumber ?? 0, "committedWindowID": committedWindowID ?? 0,
            "frame": [rect.minX, rect.minY, rect.width, rect.height],
            "alpha": alphaValue, "glassOutline": usesGlassOutline,
            "handoff": committedWindowID != nil, "showing": showing, "visible": super.isVisible])
    }

    func refreshAccessibility() {
        updateAppearance()
        if !presentation.animates { frameAnimation?.finish() }
        // Apply accessibility changes immediately, including during an active fade.
        fade = nil
        committedWindowID = nil
        handoffDeadline = nil
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

    var realIsVisible: Bool { (showing || committedWindowID != nil) && super.isVisible }

    func showPreview(in rect: CGRect, from origin: CGPoint?, duration: TimeInterval) {
        tracePresentation("target", target: rect)
        frameAnimation?.cancel()
        updateAppearance()
        if usesGlassOutline || !super.isVisible || alphaValue == 0 {
            let initial = presentation.animates && !usesGlassOutline ? origin.map { FootprintAnimationGeometry.initialFrame(in: rect, from: $0) } : nil
            setFrame(initial ?? rect, display: false)
        }
        orderFront(nil)
        movePreview(to: rect, duration: duration)
    }

    func movePreview(to rect: CGRect, duration: TimeInterval) {
        frameAnimation?.cancel()
        guard !usesGlassOutline, presentation.animates, duration > 0, frame != rect else {
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
        committedWindowID = nil
        handoffDeadline = nil
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
        tracePresentation("ordered")
    }

    override func orderOut(_ sender: Any?) {
        showing = false
        committedWindowID = nil
        handoffDeadline = nil
        tracePresentation("dismiss")
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

    /// Hold the final glass outline until the moving surface covers it.
    func commitSnapPreview(windowID: CGWindowID? = nil) {
        guard realIsVisible else { return }
        guard usesGlassOutline, let windowID else {
            orderOut(nil)
            return
        }
        showing = false
        committedWindowID = windowID
        // Bounded cleanup for actions that bypass the animation coordinator.
        handoffDeadline = clock() + 3
        tracePresentation("handoff")
        startTimer()
    }

    func receiveSnapHandoff(_ handoff: SnapPreviewHandoff) {
        guard committedWindowID == handoff.windowID else { return }
        let target = frame.screenFlipped
        guard abs(target.minX - handoff.frame.minX) <= 1,
              abs(target.minY - handoff.frame.minY) <= 1,
              abs(target.width - handoff.frame.width) <= 1,
              abs(target.height - handoff.frame.height) <= 1 else { return }
        tracePresentation(handoff.covered ? "covered" : "cancelled")
        committedWindowID = nil
        handoffDeadline = nil
        orderOut(nil)
    }

    override func close() {
        showing = false
        committedWindowID = nil
        handoffDeadline = nil
        fade = nil
        frameAnimation?.cancel()
        timer?.invalidate()
        timer = nil
        shadowWindow?.orderOut(nil)
        super.close()
    }

    private func startFade(to alpha: CGFloat, duration: TimeInterval) {
        guard alphaValue != alpha else {
            fade = nil
            if !showing && committedWindowID == nil { hidePreview() }
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
        if let deadline = handoffDeadline, time >= deadline {
            tracePresentation("handoff-timeout")
            orderOut(nil)
        }
        if let fade {
            let progress = min(1, max(0, (time - fade.start) / fade.duration))
            alphaValue = fade.from + (fade.to - fade.from) * WindowAnimationCurve.value(at: progress)
            if progress >= 1 {
                self.fade = nil
                if !showing && committedWindowID == nil { hidePreview() }
            }
        }
        stopTimerIfIdle()
    }

    private func stopTimerIfIdle() {
        if frameAnimation == nil && fade == nil && committedWindowID == nil {
            timer?.invalidate()
            timer = nil
        }
    }
}
