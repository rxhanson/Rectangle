import Cocoa

final class LayoutHelperShadow: NSView {
    override var isFlipped: Bool { true }

    init(frame: CGRect, radius: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = radius
        layer?.shadowOffset = .zero
        updateShadowPath()
        updateShadowOpacity()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        updateShadowPath()
    }

    private func updateShadowPath() {
        layer?.shadowPath = CGPath(roundedRect: bounds,
                                   cornerWidth: LayoutHelperAppearance.cornerRadius,
                                   cornerHeight: LayoutHelperAppearance.cornerRadius,
                                   transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateShadowOpacity()
    }

    private func updateShadowOpacity() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.shadowOpacity = FootprintStyle.shadowOpacity(isDark: dark) / 2
    }
}
