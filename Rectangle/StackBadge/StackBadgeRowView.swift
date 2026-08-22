//
//  StackBadgeRowView.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

/// A single window row: app icon, then the window name. Highlights like a
/// native menu row when selected by hover or arrow keys.
final class StackBadgeRowView: NSView {
    private let onHover: () -> Void
    private let onClick: () -> Void
    private let textField: NSTextField

    init(title: String, icon: NSImage?, onHover: @escaping () -> Void, onClick: @escaping () -> Void) {
        self.onHover = onHover
        self.onClick = onClick
        self.textField = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous

        let iconView = NSImageView(frame: NSRect(x: 6, y: 3, width: 16, height: 16))
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        textField.font = NSFont.systemFont(ofSize: 13)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.autoresizingMask = [.width]
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let x: CGFloat = 28
        let height: CGFloat = 16
        textField.frame = NSRect(x: x, y: (bounds.height - height) / 2,
                                 width: bounds.width - x - 6, height: height)
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.cgColor : nil
        textField.textColor = selected ? .selectedMenuItemTextColor : .labelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
