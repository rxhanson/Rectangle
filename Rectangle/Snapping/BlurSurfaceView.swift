import AppKit
import SwiftUI

/// Hosts content inside native glass on macOS 26+, or above the older blur view
/// so vibrancy does not recolor opaque previews.
final class BlurSurfaceView: NSView {
    static var liquidGlassEnabled: Bool {
        if #available(macOS 26, *) { return Defaults.liquidGlassForBlur.enabled }
        return false
    }

    let content = ContentView()
    private let legacy = NSVisualEffectView()
    private var glass: NSView?
    private var legacyMaskRadius: CGFloat?
    private let radius: CGFloat
    private let contentFlipped: Bool
    private var observers: [NSObjectProtocol] = []
    private(set) var usesLiquidGlass = false
    var onStyleChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var blendingMode: NSVisualEffectView.BlendingMode {
        get { legacy.blendingMode }
        set { legacy.blendingMode = newValue }
    }
    override var isFlipped: Bool { contentFlipped }

    init(frame: CGRect = .zero, material: NSVisualEffectView.Material = .fullScreenUI,
         cornerRadius: CGFloat = FootprintStyle.cornerRadius, flipped: Bool = false) {
        radius = cornerRadius
        self.contentFlipped = flipped
        super.init(frame: frame)
        content.contentFlipped = flipped
        content.autoresizingMask = [.width, .height]
        legacy.material = material
        legacy.state = .active
        legacy.blendingMode = .behindWindow
        legacy.wantsLayer = true
        legacy.layer?.cornerRadius = radius
        legacy.layer?.masksToBounds = true
        legacy.layer?.cornerCurve = .continuous
        refresh()
        for name in [Notification.Name.blurStyleChanged, .blurAppearanceChanged, .configImported] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if name == .blurAppearanceChanged {
                    self.updateAppearance()
                    self.onAppearanceChange?()
                } else {
                    self.refresh()
                    self.onStyleChange?()
                }
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func refresh() {
        updateAppearance()
        let enabled = Self.liquidGlassEnabled
        if enabled, #available(macOS 26, *) {
            legacy.removeFromSuperview()
            legacy.maskImage = nil
            legacyMaskRadius = nil
            if glass == nil && bounds.width > 1 && bounds.height > 1 {
                content.removeFromSuperview()
                content.frame = bounds
                content.translatesAutoresizingMaskIntoConstraints = false
                let effect = NSGlassEffectView(frame: bounds)
                effect.style = .regular
                effect.cornerRadius = max(0, min(radius, min(bounds.width, bounds.height) / 2))
                // No tint, custom mask, overlay, border, or shadow. AppKit owns
                // the material and adapts it to appearance and accessibility.
                effect.contentView = content
                addSubview(effect)
                glass = effect
            }
        } else {
            if #available(macOS 26, *), let effect = glass as? NSGlassEffectView { effect.contentView = nil }
            glass?.removeFromSuperview()
            glass = nil
            content.translatesAutoresizingMaskIntoConstraints = true
            if legacy.superview == nil {
                addSubview(legacy)
                addSubview(content)
            }
        }
        usesLiquidGlass = enabled
        layoutMaterial()
    }

    private func updateAppearance() {
        let requested = Defaults.blurAppearance.value.appearance
        if appearance?.name != requested?.name { appearance = requested }
    }

    private func layoutMaterial() {
        if !usesLiquidGlass {
            layoutLegacyMaterial()
            content.frame = bounds
            return
        }
        guard bounds.width > 1 && bounds.height > 1 else { glass?.isHidden = true; return }
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
        if Self.liquidGlassEnabled && glass == nil && bounds.width > 1 && bounds.height > 1 { refresh() }
        else { layoutMaterial() }
    }

    final class ContentView: NSView {
        var contentFlipped = false
        override var isFlipped: Bool { contentFlipped }
    }
}
