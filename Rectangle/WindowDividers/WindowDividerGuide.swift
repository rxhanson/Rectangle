import Cocoa
import ScreenCaptureKit

final class WindowDividerGuide: NSView {
    let backdrop = WindowDividerBackdrop()
    let decoration = WindowDividerDecoration(frame: .zero)
    private(set) var frozenImage: NSImage?
    var previewBounds: CGRect? { didSet { needsLayout = true } }
    var axis: WindowSplitAxis = .horizontal { didSet { needsLayout = true } }
    var gap: CGFloat = 0 { didSet { needsLayout = true } }
    var dividerX: CGFloat = 0 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
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
            let inset = WindowDividerBackdrop.inset(for: region.size)
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
