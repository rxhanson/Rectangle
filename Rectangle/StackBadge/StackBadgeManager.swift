//
//  StackBadgeManager.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

/// Shows a small badge and a window-name list when the cursor dwells on a
/// grid corner where multiple windows are stacked. Clicking a name brings
/// that window forward.
///
/// Deliberately stateless: nothing about windows or screens is retained
/// between dwells. Every dwell asks the window server fresh, so windows
/// moving, closing, or changing screens through paths Rectangle doesn't
/// control cannot leave stale UI behind.
class StackBadgeManager {

    struct StackedWindow {
        let windowId: CGWindowID
        let pid: pid_t
        let title: String
    }

    private static let tickInterval: TimeInterval = 0.2
    private static let dwellInterval: TimeInterval = 0.25
    private static let hoverZone: CGFloat = 30
    private static let moveTolerance: CGFloat = 2
    private static let axTimeout: Float = 0.25

    // A Timer polling NSEvent.mouseLocation is deliberate: a global
    // mouse-moved event monitor stops delivering events after sleep/wake,
    // while the synchronous location read cannot. The tick is a coordinate
    // comparison and only runs while the feature is enabled.
    private var timer: Timer?
    private var lastMouseLocation = CGPoint.zero
    private var lastMoveTime: TimeInterval = 0
    private var dwellFired = false
    private var generation = 0

    private var badgeWindow: NSWindow?
    private var listWindow: NSPanel?
    private var visibleUIFrames = [CGRect]()

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
        NotificationCenter.default.addObserver(
            forName: .stackBadgeChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.toggleListening()
        }
        NotificationCenter.default.addObserver(
            forName: .configImported,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.toggleListening()
        }
        toggleListening()
    }

    private func toggleListening() {
        if Defaults.stackBadge.userEnabled {
            guard timer == nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
            timer.tolerance = 0.05
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            dismiss()
        }
    }

    private func tick() {
        let location = NSEvent.mouseLocation
        let dx = location.x - lastMouseLocation.x
        let dy = location.y - lastMouseLocation.y

        if abs(dx) > Self.moveTolerance || abs(dy) > Self.moveTolerance {
            lastMouseLocation = location
            lastMoveTime = ProcessInfo.processInfo.systemUptime
            dwellFired = false
            generation += 1
            if !visibleUIFrames.isEmpty, !isInsideVisibleUI(location) {
                dismiss()
            }
            return
        }

        guard !dwellFired,
              ProcessInfo.processInfo.systemUptime - lastMoveTime >= Self.dwellInterval
        else { return }
        dwellFired = true

        // Gaps shift window origins away from the geometric grid corner, so
        // the hover zone has to reach across the gap to the shifted peek.
        let zone = Self.hoverZone + CGFloat(Defaults.gapSize.value)

        // Corner points are recomputed per dwell (a few hundred additions)
        // rather than cached: adjustedVisibleFrame depends on more inputs
        // than post didChangeScreenParametersNotification (Todo mode, Stage
        // Manager, edge-gap defaults), so a cache has no reliable
        // invalidation signal - the same reason window state isn't cached.
        guard visibleUIFrames.isEmpty,
              let screen = (NSScreen.screens.first { NSPointInRect(location, $0.frame) })
        else { return }
        let screenFrame = screen.adjustedVisibleFrame()
        let corners = StackBadgeGeometry.cornerPoints(in: screenFrame)
        guard let corner = StackBadgeGeometry.corner(near: location, in: corners, zone: zone) else { return }

        query(corner: corner, screenFrame: screenFrame)
    }

    private func isInsideVisibleUI(_ location: CGPoint) -> Bool {
        visibleUIFrames.contains { $0.insetBy(dx: -8, dy: -8).contains(location) }
    }

    /// One fresh look at reality per dwell. The count comes from the window
    /// server (CGWindowList - cannot block on an unresponsive app); AX is
    /// touched only to read the titles of the few windows that matched, off
    /// the main thread, discarded if the cursor has moved on.
    private func query(corner: CGPoint, screenFrame: CGRect) {
        let cornerAX = corner.screenFlipped
        let screenFrameAX = screenFrame.screenFlipped
        let tolerance: CGFloat = 4
        let offsetSize = CGFloat(Defaults.cyclingOverlapOffsetSize.value)
        let maxCascade = CGFloat(min(5, max(1, Defaults.cyclingOverlapMaxCascade.value)))
        let cascadeRange = max(offsetSize, 1) * maxCascade + tolerance

        // Gaps place a cell's window up to a full gap away from the
        // geometric corner, so candidates are gathered from a widened box...
        let gap = CGFloat(Defaults.gapSize.value)
        let candidateRange = gap + cascadeRange

        // The cascade offset is diagonal in x but can run either way in y
        // (the offset is applied in AppKit coords, where +y converts to an
        // upward move in AX space), so the y window is symmetric.
        let candidates = WindowUtil.getWindowList().filter { info in
            guard info.level == kCGNormalWindowLevel else { return false }
            let coversScreen = info.frame.width > screenFrameAX.width * 0.9
                && info.frame.height > screenFrameAX.height * 0.9
            guard !coversScreen else { return false }
            let dx = info.frame.origin.x - cornerAX.x
            let dy = info.frame.origin.y - cornerAX.y
            return dx >= -tolerance && dx <= candidateRange
                && dy >= -candidateRange && dy <= candidateRange
        }

        // ...and the stack is the densest cascade cluster among them, so
        // the widened box doesn't count unrelated neighbors and an
        // unrelated leftmost window doesn't mask a real stack.
        let stacked = StackBadgeGeometry
            .stackIndices(among: candidates.map { $0.frame.origin }, cascadeRange: cascadeRange, tolerance: tolerance)
            .map { candidates[$0] }

        guard stacked.count >= 2,
              let leftMost = (stacked.min { $0.frame.origin.x < $1.frame.origin.x }),
              let topMost = (stacked.min { $0.frame.origin.y < $1.frame.origin.y })
        else { return }

        // The badge sits at the stack's visual top-left extremity - where
        // the title bars start - not the geometric corner the gaps shifted
        // the windows away from.
        let anchorTopLeft = CGPoint(x: leftMost.frame.origin.x, y: topMost.frame.origin.y).screenFlipped

        let requestGeneration = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let titles = Self.titlesByWindowId(for: stacked)
            // CGWindowList order is front to back; keep it for the list.
            let windows = stacked.map { info in
                StackedWindow(windowId: info.id,
                              pid: info.pid,
                              title: Self.displayTitle(for: info, axTitle: titles[info.id]))
            }
            DispatchQueue.main.async {
                guard let self,
                      self.generation == requestGeneration,
                      self.timer != nil
                else { return }
                self.show(windows: windows, corner: anchorTopLeft, screenFrame: screenFrame)
            }
        }
    }

    /// One AX window enumeration per application, however many of its
    /// windows are in the stack.
    private static func titlesByWindowId(for stacked: [WindowInfo]) -> [CGWindowID: String] {
        var titles = [CGWindowID: String]()
        for pid in Set(stacked.map { $0.pid }) {
            let appElement = AccessibilityElement(pid)
            appElement.setMessagingTimeout(axTimeout)
            let stackedIds = Set(stacked.filter { $0.pid == pid }.map { $0.id })
            for element in appElement.windowElements ?? [] {
                if let id = element.windowId, stackedIds.contains(id) {
                    titles[id] = element.title
                }
            }
        }
        return titles
    }

    private static func displayTitle(for info: WindowInfo, axTitle: String?) -> String {
        let title = axTitle ?? ""
        let processName = info.processName ?? ""
        if title.isEmpty { return processName }
        if processName.isEmpty || title.hasPrefix(processName) { return title }
        return "\(processName) — \(title)"
    }

    // MARK: - UI

    private func show(windows: [StackedWindow], corner: CGPoint, screenFrame: CGRect) {
        dismiss()

        let badge = Self.makeBadgeWindow(count: windows.count, corner: corner)
        badge.orderFrontRegardless()
        badgeWindow = badge

        let list = Self.makeListWindow(windows: windows, corner: corner, screenFrame: screenFrame) { [weak self] window in
            self?.focus(window)
        }
        list.orderFrontRegardless()
        listWindow = list

        visibleUIFrames = [badge.frame, list.frame]
    }

    private func dismiss() {
        // Invalidate any in-flight title fetch so a stale result can't
        // resurrect the UI after a dismissal.
        generation += 1
        badgeWindow?.orderOut(nil)
        badgeWindow = nil
        listWindow?.orderOut(nil)
        listWindow = nil
        visibleUIFrames = []
    }

    /// Resolves the window by pid directly (no shared window-list cache off
    /// the main thread), with AX timeouts so an unresponsive app can't hang
    /// the focus attempt.
    private func focus(_ window: StackedWindow) {
        dismiss()
        DispatchQueue.global(qos: .userInitiated).async {
            let appElement = AccessibilityElement(window.pid)
            appElement.setMessagingTimeout(Self.axTimeout)
            guard let windowElement = (appElement.windowElements?.first { $0.windowId == window.windowId }) else { return }
            windowElement.setMessagingTimeout(Self.axTimeout)
            windowElement.bringToFront(force: true)
        }
    }

    /// Small click-through count pill sitting in the peek. Kept under 16pt
    /// tall so it clears the front window's traffic lights, which the
    /// offset pushes out of the peek strip.
    private static func makeBadgeWindow(count: Int, corner: CGPoint) -> NSWindow {
        let size = NSSize(width: 26, height: 15)
        let frame = NSRect(x: corner.x, y: corner.y - size.height, width: size.width, height: size.height)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.ignoresMouseEvents = true

        let label = NSTextField(labelWithString: "⧉ \(count)")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(origin: .zero, size: size)
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.92).cgColor
        label.layer?.cornerRadius = 5
        window.contentView = label
        return window
    }

    /// Clickable window-name list, opening downward from the peek into the
    /// window body and clamped to the screen so every row stays reachable.
    /// A non-activating panel so clicking a name doesn't activate Rectangle
    /// itself.
    private static func makeListWindow(windows: [StackedWindow],
                                       corner: CGPoint,
                                       screenFrame: CGRect,
                                       onSelect: @escaping (StackedWindow) -> Void) -> NSPanel {
        let rowHeight: CGFloat = 22
        let width: CGFloat = 260
        let padding: CGFloat = 4
        let height = CGFloat(windows.count) * rowHeight + padding * 2
        var frame = NSRect(x: corner.x + 12,
                           y: corner.y - 18 - height,
                           width: width,
                           height: height)
        if frame.maxX > screenFrame.maxX { frame.origin.x = screenFrame.maxX - frame.width }
        if frame.origin.y < screenFrame.minY { frame.origin.y = screenFrame.minY }

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8

        for (index, window) in windows.enumerated() {
            let button = StackBadgeRowButton(title: window.title) {
                onSelect(window)
            }
            button.frame = NSRect(x: padding,
                                  y: frame.height - padding - CGFloat(index + 1) * rowHeight,
                                  width: width - padding * 2,
                                  height: rowHeight)
            container.addSubview(button)
        }

        panel.contentView = container
        return panel
    }
}

/// A flat, left-aligned row button with a hover highlight.
private class StackBadgeRowButton: NSButton {
    private let onClick: () -> Void

    init(title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        alignment = .left
        lineBreakMode = .byTruncatingTail
        font = NSFont.systemFont(ofSize: 12)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 5
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    @objc private func clicked() {
        onClick()
    }
}
