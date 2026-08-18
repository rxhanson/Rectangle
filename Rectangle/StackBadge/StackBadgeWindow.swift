//
//  StackBadgeWindow.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

/// Click-through count pill at the stack's top-left: a solid accent-color
/// capsule with an SF Symbol stack glyph, sized to fit its contents.
final class StackBadgeWindow: NSWindow {

    init(count: Int, corner: CGPoint) {
        let label = NSTextField(labelWithString: "\(count)")
        label.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        let labelW = ceil(label.frame.width)
        let labelH = ceil(label.frame.height)

        var symbolView: NSImageView?
        if #available(macOS 11, *),
           let symbol = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "stacked windows")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)) {
            let imageView = NSImageView(image: symbol)
            imageView.contentTintColor = .white
            symbolView = imageView
        }
        let symbolW: CGFloat = symbolView == nil ? 0 : 19
        let symbolH: CGFloat = 16
        let gap: CGFloat = symbolView == nil ? 0 : 7
        let hPad: CGFloat = 12
        let height: CGFloat = 28
        let size = NSSize(width: symbolW + gap + labelW + hPad * 2, height: height)
        let frame = NSRect(x: corner.x, y: corner.y - size.height, width: size.width, height: size.height)

        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.transient, .ignoresCycle]
        ignoresMouseEvents = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        container.layer?.cornerRadius = height / 2
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        var x = hPad
        if let symbolView {
            symbolView.frame = NSRect(x: x, y: (height - symbolH) / 2, width: symbolW, height: symbolH)
            container.addSubview(symbolView)
            x += symbolW + gap
        }
        label.frame = NSRect(x: x, y: (height - labelH) / 2, width: labelW, height: labelH)
        container.addSubview(label)
        contentView = container
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
