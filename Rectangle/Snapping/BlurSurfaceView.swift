import AppKit

/// Hosts content inside native glass on macOS 26+, or above the older blur view
/// so vibrancy does not recolor opaque previews.
final class BlurSurfaceView: NSView {
    struct Presentation {
        var material: OverlayMaterial
        var appearance: NSAppearance?

        static var overlay: Self {
            let material = Defaults.effectiveOverlayMaterial
            return Self(material: material, appearance: material.usesBlur ? Defaults.blurAppearance.value.appearance : nil)
        }
    }

    let content = NSView()
    private let legacy = NSVisualEffectView()
    private let solid = NSView()
    private let solidColor: NSColor
    private var glass: NSView?
    private var legacyMaskRadius: CGFloat?
    private let radius: CGFloat
    private let presentation: () -> Presentation
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObserver: NSObjectProtocol?
    private let notifications: NotificationCenter
    private(set) var effectiveMaterial: OverlayMaterial = .noBlur
    var usesLiquidGlass: Bool { effectiveMaterial == .liquidGlass }
    var onStyleChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var blendingMode: NSVisualEffectView.BlendingMode {
        get { legacy.blendingMode }
        set { legacy.blendingMode = newValue }
    }

    init(frame: CGRect = .zero, material: NSVisualEffectView.Material, cornerRadius: CGFloat,
         notifications: NotificationCenter = .default,
         solidColor: NSColor = .windowBackgroundColor,
         presentation: @escaping () -> Presentation = { .overlay }) {
        self.notifications = notifications
        self.presentation = presentation
        self.solidColor = solidColor
        radius = cornerRadius
        super.init(frame: frame)
        content.autoresizingMask = [.width, .height]
        legacy.material = material
        legacy.state = .active
        legacy.blendingMode = .behindWindow
        legacy.wantsLayer = true
        legacy.layer?.cornerRadius = radius
        legacy.layer?.masksToBounds = true
        legacy.layer?.cornerCurve = .continuous
        solid.wantsLayer = true
        solid.layer?.cornerCurve = .continuous
        refresh()
        for name in [Notification.Name.blurStyleChanged, .blurAppearanceChanged, .configImported] {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if name == .blurAppearanceChanged {
                    self.updateAppearance(self.presentation().appearance)
                    self.onAppearanceChange?()
                } else {
                    self.refresh()
                    self.onStyleChange?()
                }
            })
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
            self?.onStyleChange?()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        observers.forEach { notifications.removeObserver($0) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    func refresh() {
        let style = presentation()
        updateAppearance(style.appearance)
        effectiveMaterial = style.material.effective(supportsLiquidGlass: OverlayMaterial.supportsLiquidGlass,
                                                     reduceTransparency: false)
        switch effectiveMaterial {
        case .liquidGlass:
            if #available(macOS 26, *) { showGlass() }
        case .standard:
            solid.removeFromSuperview()
            showContent(above: legacy)
        case .noBlur:
            removeLegacyMaterial()
            showContent(above: solid)
        }
        layoutMaterial()
    }

    @available(macOS 26, *)
    private func showGlass() {
        removeLegacyMaterial()
        solid.removeFromSuperview()
        guard glass == nil, bounds.width > 1, bounds.height > 1 else { return }
        let effect = NSGlassEffectView(frame: bounds)
        effect.style = .regular
        content.removeFromSuperview()
        content.frame = bounds
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.contentView = content
        addSubview(effect)
        glass = effect
    }

    private func showContent(above background: NSView) {
        if #available(macOS 26, *), let effect = glass as? NSGlassEffectView { effect.contentView = nil }
        glass?.removeFromSuperview()
        glass = nil
        if content.superview !== self {
            content.translatesAutoresizingMaskIntoConstraints = true
            addSubview(content)
        }
        if background.superview == nil { addSubview(background, positioned: .below, relativeTo: content) }
    }

    private func removeLegacyMaterial() {
        legacy.removeFromSuperview()
        legacy.maskImage = nil
        legacyMaskRadius = nil
    }

    private func updateAppearance(_ requested: NSAppearance?) {
        if appearance?.name != requested?.name { appearance = requested }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            solid.layer?.backgroundColor = solidColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            solid.layer?.backgroundColor = solidColor.cgColor
        }
    }

    private func layoutMaterial() {
        if !usesLiquidGlass {
            if effectiveMaterial == .standard {
                layoutLegacyMaterial()
            } else {
                solid.frame = bounds
                solid.layer?.cornerRadius = max(0, min(radius, min(bounds.width, bounds.height) / 2))
            }
            content.frame = bounds
            return
        }
        guard bounds.width > 1 && bounds.height > 1 else {
            glass?.isHidden = true
            return
        }
        glass?.isHidden = false
        if NSAnimationContext.current.allowsImplicitAnimation { glass?.animator().frame = bounds }
        else { glass?.frame = bounds }
        if #available(macOS 26, *), let effect = glass as? NSGlassEffectView {
            effect.cornerRadius = max(0, min(radius, min(bounds.width, bounds.height) / 2))
        }
    }

    private func layoutLegacyMaterial() {
        // Stretch-mask caps must fit even the first animation frame. Installing
        // a full-size mask on an empty view gives AppKit negative slice sizes.
        let cap = max(0, min(radius, (min(bounds.width, bounds.height) - 1) / 2))
        if cap < (legacyMaskRadius ?? 0) || bounds.width <= 0 || bounds.height <= 0 {
            legacy.maskImage = nil
            legacyMaskRadius = nil
        }
        legacy.frame = bounds
        guard bounds.width > 0 && bounds.height > 0, legacyMaskRadius != cap else { return }
        let mask = NSImage(size: NSSize(width: cap * 2 + 1, height: cap * 2 + 1), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cap, yRadius: cap).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        mask.resizingMode = .stretch
        legacy.maskImage = mask
        legacyMaskRadius = cap
    }
    override func layout() {
        super.layout()
        if usesLiquidGlass && glass == nil && bounds.width > 1 && bounds.height > 1 { refresh() }
        else { layoutMaterial() }
    }

}
