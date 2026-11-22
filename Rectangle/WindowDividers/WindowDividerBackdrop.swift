import AppKit

final class WindowDividerBackdrop: NSView {
    let material: BlurSurfaceView
    let capturedPreview = WindowDividerCapturedPreview(frame: .zero)

    static func inset(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) / 8, min(size.width, size.height) < 320 ? 8 : 12)
    }

    init(notifications: NotificationCenter) {
        material = BlurSurfaceView(material: .fullScreenUI, cornerRadius: FootprintStyle.cornerRadius,
                                   notifications: notifications)
        super.init(frame: .zero)
        material.autoresizingMask = [.width, .height]
        addSubview(material)
        capturedPreview.autoresizingMask = [.width, .height]
        material.content.addSubview(capturedPreview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func fit(to preview: CGRect, coverage: CGRect) {
        frame = preview
        material.frame = bounds
        capturedPreview.sourceFrame = preview.offsetBy(dx: -coverage.minX, dy: -coverage.minY)
        capturedPreview.coverageSize = coverage.size
    }

    func setCapture(_ image: NSImage?) {
        capturedPreview.image = image
        updatePresentation()
    }

    func updatePresentation() {
        let hasCapture = capturedPreview.image != nil
        let samplesFrozenBackdrop = hasCapture && material.effectiveMaterial == .standard
        material.blendingMode = samplesFrozenBackdrop ? .withinWindow : .behindWindow
        capturedPreview.isHidden = !hasCapture || samplesFrozenBackdrop
        capturedPreview.present(material.effectiveMaterial)
    }
}

/// Native Glass has no within-window blending mode. Present the captured pixels explicitly
/// inside the material so a moving live window cannot show through the frozen preview.
final class WindowDividerCapturedPreview: NSView {
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var material: OverlayMaterial = .noBlur
    private var frostedCoverage: CGSize = .zero
    private(set) var frostedImage: NSImage?
    var image: NSImage? {
        didSet {
            if image !== oldValue { frostedImage = nil }
            needsDisplay = true
        }
    }
    var sourceFrame: CGRect = .zero { didSet { needsDisplay = true } }
    var coverageSize: CGSize = .zero {
        didSet {
            if coverageSize != oldValue { present(material) }
        }
    }

    func present(_ material: OverlayMaterial) {
        self.material = material
        if material == .liquidGlass, let image, coverageSize.width > 0, coverageSize.height > 0,
           frostedImage == nil || frostedCoverage != coverageSize {
            frostedImage = Self.frostedCopy(of: image, coverage: coverageSize)
            frostedCoverage = coverageSize
        }
        needsDisplay = true
    }

    private static func frostedCopy(of image: NSImage, coverage: CGSize) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Glass obscures fine detail. Filter a small copy once at this display scale,
        // keeping the original full-resolution capture for shadows and No blur.
        let scale = min(0.25, 768 / max(coverage.width, coverage.height))
        let width = max(1, (coverage.width * scale).rounded())
        let height = max(1, (coverage.height * scale).rounded())
        let transform = CGAffineTransform(scaleX: width / CGFloat(source.width), y: height / CGFloat(source.height))
        let reduced = CIImage(cgImage: source).transformed(by: transform, highQualityDownsample: true)
        let blurred = reduced.clampedToExtent().applyingGaussianBlur(sigma: 14 * scale)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        guard let rendered = imageContext.createCGImage(blurred, from: extent) else { return nil }
        return NSImage(cgImage: rendered, size: image.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, !sourceFrame.isEmpty, coverageSize.width > 0, coverageSize.height > 0 else { return }
        // Leave the rounded material rim visible. The source and destination insets
        // must match so the captured content lines up with the shadow outside the guide.
        let target = bounds.insetBy(dx: 2, dy: 2)
        guard !target.isEmpty else { return }
        let radius = min(max(0, FootprintStyle.cornerRadius - 2), min(target.width, target.height) / 2)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: target, xRadius: radius, yRadius: radius).addClip()
        let crop = sourceFrame.insetBy(dx: 2, dy: 2)
        let scaleX = image.size.width / coverageSize.width
        let scaleY = image.size.height / coverageSize.height
        let source = CGRect(x: crop.minX * scaleX, y: crop.minY * scaleY,
                            width: crop.width * scaleX, height: crop.height * scaleY)
        NSColor.windowBackgroundColor.withAlphaComponent(1).setFill()
        target.fill(using: .copy)
        let displayed = material == .liquidGlass ? frostedImage : image
        NSGraphicsContext.current?.imageInterpolation = .high
        displayed?.draw(in: target, from: source, operation: .sourceOver, fraction: 1)
        let tintOpacity: CGFloat = material == .noBlur ? 0.40 : 0.18
        NSColor.windowBackgroundColor.withAlphaComponent(tintOpacity).setFill()
        target.fill(using: .sourceOver)
    }
}
