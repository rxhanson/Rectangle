import Cocoa

final class LayoutHelperDocument: NSView {
    override var isFlipped: Bool { true }
    // Keep pointer sessions neutral without AppKit focusing the close button.
    override var acceptsFirstResponder: Bool { window?.contentView === self }
}
