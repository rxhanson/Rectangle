//
//  OverlapCountBadge.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

struct StackedRegion {
    let origin: CGPoint
    let rect: CGRect
    let screen: NSScreen
}

class OverlapCountBadge {
    private static var badgeWindow: NSWindow?
    private static var pollTimer: Timer?
    private static var stackedRegions: [StackedRegion] = []
    private static var currentlyShowing = false
    private static let hoverMargin: CGFloat = 30
    private static let originTolerance: CGFloat = 15

    private static let maxRegions = 20

    static func recordStack(origin: CGPoint, rect: CGRect, screen: NSScreen) {
        stackedRegions.removeAll { abs($0.origin.x - origin.x) < 4 && abs($0.origin.y - origin.y) < 4 }
        stackedRegions.append(StackedRegion(origin: origin, rect: rect, screen: screen))

        if stackedRegions.count > maxRegions {
            stackedRegions.removeFirst(stackedRegions.count - maxRegions)
        }

        if pollTimer == nil {
            startPolling()
        }
    }

    static func removeStack(near origin: CGPoint) {
        stackedRegions.removeAll { abs($0.origin.x - origin.x) < 4 && abs($0.origin.y - origin.y) < 4 }
        if stackedRegions.isEmpty {
            dismiss()
            stopPolling()
        }
    }

    static func clearAll() {
        stackedRegions.removeAll()
        dismiss()
        stopPolling()
    }

    private static func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            checkHover(at: NSEvent.mouseLocation)
        }
    }

    private static func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private static func checkHover(at point: NSPoint) {
        for region in stackedRegions {
            let hoverRect = region.rect.insetBy(dx: -hoverMargin, dy: -hoverMargin)
            if hoverRect.contains(point) {
                let count = liveCount(near: region.origin, on: region.screen)
                if count > 1 {
                    show(count: count, near: region.rect)
                } else {
                    stackedRegions.removeAll { abs($0.origin.x - region.origin.x) < 4 && abs($0.origin.y - region.origin.y) < 4 }
                    if currentlyShowing { dismiss() }
                    if stackedRegions.isEmpty { stopPolling() }
                }
                return
            }
        }

        if currentlyShowing {
            dismiss()
        }
    }

    private static func liveCount(near origin: CGPoint, on screen: NSScreen) -> Int {
        let screenFrameAX = screen.adjustedVisibleFrame().screenFlipped
        let windows = AccessibilityElement.getAllWindowElements().filter { element in
            guard element.isWindow == true,
                  element.isMinimized != true,
                  element.isHidden != true,
                  element.isSheet != true
            else { return false }

            let frame = element.frame
            guard !frame.isNull, screenFrameAX.intersects(frame) else { return false }

            return abs(frame.origin.x - origin.x) < originTolerance
                && abs(frame.origin.y - origin.y) < originTolerance
        }
        return windows.count
    }

    private static func show(count: Int, near rect: CGRect) {
        let window = badgeWindow ?? createWindow()
        badgeWindow = window

        let badgeSize = NSSize(width: 28, height: 22)
        let badgeOrigin = NSPoint(
            x: rect.origin.x + rect.width - badgeSize.width - 6,
            y: rect.origin.y + 6
        )

        window.setFrame(NSRect(origin: badgeOrigin, size: badgeSize), display: false)

        if let label = window.contentView?.subviews.first as? NSTextField {
            label.stringValue = "\(count)"
        }

        window.alphaValue = 0.9
        window.orderFront(nil)
        currentlyShowing = true
    }

    private static func dismiss() {
        guard currentlyShowing else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            badgeWindow?.animator().alphaValue = 0.0
        } completionHandler: {
            badgeWindow?.orderOut(nil)
            currentlyShowing = false
        }
    }

    private static func createWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 28, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.transient)
        window.ignoresMouseEvents = true

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.9).cgColor
        label.layer?.cornerRadius = 6
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        window.contentView = container
        return window
    }
}
