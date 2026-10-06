import Cocoa

final class LayoutHelperCardForeground: NSView {
    weak var card: LayoutHelperCard?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { card?.drawForeground() }
}
