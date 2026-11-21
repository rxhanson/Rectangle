/// FreeformSelectionController.swift
///
/// A screenshot-style area picker for the Freeform presets. Every display is covered by an
/// overlay, and dragging on one of them selects the area the preset moves windows to.

import AppKit
import Carbon

/// A display that the selection overlay covers.
struct FreeformSelectionDisplay {
    /// The display's frame in AppKit screen coordinates. Its overlay covers all of it.
    let frame: CGRect
    /// The part of the display windows can be moved to. Selections stay inside it.
    let workArea: CGRect
    let id: UUID?
}

final class FreeformSelectionController: NSObject {
    private let displays: () -> [FreeformSelectionDisplay]
    private var completion: ((FreeformRegion?) -> Void)?
    private(set) var panels: [FreeformSelectionPanel] = []
    private var hiddenWindow: HiddenWindow?

    /// The window that started the selection, and how it looked before it was hidden.
    private struct HiddenWindow {
        let window: NSWindow
        let alphaValue: CGFloat
        let ignoresMouseEvents: Bool
    }

    var isSelecting: Bool { completion != nil }

    init(displays: @escaping () -> [FreeformSelectionDisplay]) {
        self.displays = displays
    }

    deinit {
        if isSelecting {
            NSCursor.pop()
        }
        closeOverlays()
        restoreWindow(bringToFront: false)
    }

    /// Covers every display with an overlay and calls `completion` once, with the selected
    /// area, or with nil when the selection is cancelled or interrupted.
    ///
    /// `window` is made transparent until the selection ends, so it doesn't hide the area being
    /// selected. It is not ordered out, because that would make its view controllers disappear.
    func begin(from window: NSWindow, title: String, current: FreeformRegion? = nil,
               completion: @escaping (FreeformRegion?) -> Void) {
        guard !isSelecting else { return }
        let panels = displays().compactMap { display -> FreeformSelectionPanel? in
            guard !display.workArea.isNull, !display.workArea.isEmpty,
                  display.frame.contains(display.workArea) else { return nil }
            let currentArea = current.flatMap { region in
                region.displayID == display.id ? region.rect(in: display.workArea) : nil
            }
            let view = FreeformSelectionView(display: display, title: title, currentArea: currentArea)
            view.onSelection = { [weak self] region in self?.finish(with: region) }
            view.onCancel = { [weak self] in self?.cancel() }
            return FreeformSelectionPanel(display: display, view: view)
        }
        guard let firstPanel = panels.first else { return completion(nil) }

        self.panels = panels
        self.completion = completion
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interrupted), name: NSApplication.didResignActiveNotification, object: NSApp)
        center.addObserver(self, selector: #selector(interrupted), name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(interrupted),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSCursor.crosshair.push()

        let mouse = NSEvent.mouseLocation
        let keyPanel = panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? firstPanel
        for panel in panels where panel !== keyPanel {
            panel.orderFrontRegardless()
        }
        keyPanel.makeKeyAndOrderFront(nil)

        // Anything above could have ended the selection already, and then the window stays as it is.
        guard isSelecting else { return }
        hiddenWindow = HiddenWindow(window: window, alphaValue: window.alphaValue,
                                    ignoresMouseEvents: window.ignoresMouseEvents)
        window.ignoresMouseEvents = true
        window.alphaValue = 0
    }

    func cancel() {
        finish(with: nil)
    }

    @objc private func interrupted(_ notification: Notification) {
        finish(with: nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        finish(with: nil, bringWindowToFront: false)
    }

    private func finish(with region: FreeformRegion?, bringWindowToFront: Bool = true) {
        guard let completion else { return }
        self.completion = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSCursor.pop()
        closeOverlays()
        restoreWindow(bringToFront: bringWindowToFront)
        completion(region)
    }

    private func closeOverlays() {
        for panel in panels {
            panel.close()
        }
        panels.removeAll()
    }

    private func restoreWindow(bringToFront: Bool) {
        guard let hidden = hiddenWindow else { return }
        hiddenWindow = nil
        let window = hidden.window
        window.alphaValue = hidden.alphaValue
        window.ignoresMouseEvents = hidden.ignoresMouseEvents
        guard bringToFront, window.isVisible else { return }
        if NSApp.isActive {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }
}

/// A borderless overlay covering one display.
final class FreeformSelectionPanel: NSPanel {
    let selectionView: FreeformSelectionView

    init(display: FreeformSelectionDisplay, view: FreeformSelectionView) {
        selectionView = view
        super.init(contentRect: display.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = view
        initialFirstResponder = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The overlay has a single view, which handles every key.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged:
            selectionView.handleKey(event)
        default:
            super.sendEvent(event)
        }
    }
}

final class FreeformSelectionView: NSView {
    let display: FreeformSelectionDisplay
    var onSelection: ((FreeformRegion) -> Void)?
    var onCancel: (() -> Void)?

    /// The preset's current area on this display, in screen coordinates.
    let currentArea: CGRect?
    private let title: String
    private(set) var drag: FreeformDrag?
    /// The pointer during a drag, in screen coordinates.
    private var pointer: CGPoint?
    private var isSpaceDown = false
    private var modifierFlags: NSEvent.ModifierFlags = []

    init(display: FreeformSelectionDisplay, title: String, currentArea: CGRect?) {
        self.display = display
        self.title = title
        self.currentArea = currentArea
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
                                       owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Selecting

    override func mouseDown(with event: NSEvent) {
        guard let point = screenLocation(of: event) else { return }
        modifierFlags = event.modifierFlags
        drag = FreeformDrag(start: point, bounds: display.workArea)
        pointer = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard drag != nil, let point = screenLocation(of: event) else { return }
        modifierFlags = event.modifierFlags
        pointer = point
        drag?.update(to: point, modifiers: modifiers)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var drag, let point = screenLocation(of: event) else { return }
        modifierFlags = event.modifierFlags
        let rect = drag.finish(at: point, modifiers: modifiers)
        self.drag = nil
        pointer = nil
        needsDisplay = true
        // A click doesn't select anything, so the user can try again.
        if let rect, let region = FreeformRegion(rect: rect, in: display.workArea, displayID: display.id) {
            onSelection?(region)
        }
    }

    func handleKey(_ event: NSEvent) {
        switch event.type {
        case .keyDown where event.keyCode == kVK_Escape:
            onCancel?()
        case .keyDown where event.keyCode == kVK_Space:
            setSpaceDown(true)
        case .keyUp where event.keyCode == kVK_Space:
            setSpaceDown(false)
        case .flagsChanged:
            modifierFlags = event.modifierFlags
            refreshDrag()
        default:
            break
        }
    }

    private func setSpaceDown(_ isDown: Bool) {
        guard isSpaceDown != isDown else { return }
        isSpaceDown = isDown
        refreshDrag()
    }

    private var modifiers: FreeformDrag.Modifiers {
        var modifiers: FreeformDrag.Modifiers = []
        if isSpaceDown { modifiers.insert(.move) }
        if modifierFlags.contains(.option) { modifiers.insert(.fromCenter) }
        if modifierFlags.contains(.shift) { modifiers.insert(.lockAxis) }
        return modifiers
    }

    /// A modifier pressed or released mid-drag applies at once, as in the screenshot selection.
    private func refreshDrag() {
        guard let pointer, drag != nil else { return }
        drag?.update(to: pointer, modifiers: modifiers)
        needsDisplay = true
    }

    private func screenLocation(of event: NSEvent) -> CGPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }

    private func local(_ screenRect: CGRect) -> CGRect {
        guard let window else { return screenRect }
        return convert(window.convertFromScreen(screenRect), from: nil)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        let workArea = local(display.workArea)
        let selection = drag.map { local($0.rect) }.flatMap { $0.isEmpty ? nil : $0 }

        // The menu bar and the Dock can't be selected, so they are darker.
        let unavailable = NSBezierPath(rect: bounds)
        unavailable.appendRect(workArea)
        unavailable.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        unavailable.fill()

        let shade = NSBezierPath(rect: workArea)
        if let selection {
            shade.appendRect(selection)
        }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.25).setFill()
        shade.fill()

        if let selection {
            NSColor.white.withAlphaComponent(0.08).setFill()
            selection.fill()
            strokeOutline(of: selection, dashed: false)
            let size = "\(Int(selection.width)) × \(Int(selection.height))"
            let anchor = pointer.map { local(CGRect(origin: $0, size: .zero)).origin } ?? CGPoint(x: selection.maxX, y: selection.minY)
            drawLabel(size, at: CGPoint(x: anchor.x + 14, y: anchor.y - 14), alignment: .topLeft)
        } else {
            if let currentArea {
                strokeOutline(of: local(currentArea), dashed: true)
            }
            let hint = String(localized: "\(title): drag to select an area. Hold Space to move it, press Esc to cancel.")
            drawLabel(hint, at: CGPoint(x: workArea.midX, y: workArea.maxY - 40), alignment: .center)
        }
    }

    private func strokeOutline(of rect: CGRect, dashed: Bool) {
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        if dashed {
            path.setLineDash([6, 4], count: 2, phase: 0)
        }
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private enum LabelAlignment {
        case center, topLeft
    }

    private func drawLabel(_ text: String, at point: CGPoint, alignment: LabelAlignment) {
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        let size = label.size()
        let padding = CGSize(width: 8, height: 4)
        var origin = alignment == .center
            ? CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            : CGPoint(x: point.x, y: point.y - size.height)
        origin.x = max(bounds.minX + padding.width + 4, min(origin.x, bounds.maxX - size.width - padding.width - 4))
        origin.y = max(bounds.minY + padding.height + 4, min(origin.y, bounds.maxY - size.height - padding.height - 4))
        let background = CGRect(origin: origin, size: size).insetBy(dx: -padding.width, dy: -padding.height)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        label.draw(at: origin)
    }
}
