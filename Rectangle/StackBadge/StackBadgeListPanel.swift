//
//  StackBadgeListPanel.swift
//  Rectangle
//
//  Copyright © 2026 Ryan Hanson. All rights reserved.
//

import Cocoa

struct StackBadgeStackedWindow {
    let windowId: CGWindowID
    let pid: pid_t
    let title: String

    static func titledWindows(for windows: [WindowInfo], axTimeout: Float) -> [StackBadgeStackedWindow] {
        var titles = [CGWindowID: String]()
        for pid in Set(windows.map { $0.pid }) {
            let appElement = AccessibilityElement(pid)
            appElement.setMessagingTimeout(axTimeout)
            let windowIds = Set(windows.filter { $0.pid == pid }.map { $0.id })
            for element in appElement.windowElements ?? [] {
                // The cap is per accessibility object, so the app's timeout
                // does not cover the window elements it just handed back -
                // each one has to be capped before it is asked anything.
                element.setMessagingTimeout(axTimeout)
                if let id = element.windowId, windowIds.contains(id) {
                    titles[id] = element.title
                }
            }
        }

        return windows.map { info in
            StackBadgeStackedWindow(windowId: info.id,
                                    pid: info.pid,
                                    title: displayTitle(for: info, axTitle: titles[info.id]))
        }
    }

    func focus(axTimeout: Float) {
        let pid = self.pid
        let windowId = self.windowId
        DispatchQueue.global(qos: .userInitiated).async {
            let appElement = AccessibilityElement(pid)
            appElement.setMessagingTimeout(axTimeout)
            guard let windowElement = (appElement.windowElements?.first { $0.windowId == windowId }) else {
                // A timed-out request and a genuinely absent window both
                // arrive here as nil, so the message must not claim to know
                // which one happened.
                Logger.log("Unable to focus stacked window \(windowId) - it has closed, or its app did not answer in time")
                return
            }
            windowElement.setMessagingTimeout(axTimeout)
            if windowElement.isMainWindow != true {
                windowElement.isMainWindow = true
            }
            // All accessibility traffic stays off the main thread; only the
            // activation is AppKit and hops over.
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.activate(options: .activateIgnoringOtherApps)
            }
        }
    }

    private static func displayTitle(for info: WindowInfo, axTitle: String?) -> String {
        let processName = info.processName ?? ""
        var title = axTitle ?? ""
        for separator in [" — ", " - ", ": "] where !processName.isEmpty {
            let prefix = processName + separator
            if title.hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                break
            }
        }
        return title.isEmpty ? processName : title
    }
}

/// Clickable window-name list, opening downward from the peek into the window
/// body. The panel owns its rows and shared mouse/keyboard selection state.
final class StackBadgeListPanel: NSPanel {

    private static let rowHeight: CGFloat = 22
    private static let listPadding: CGFloat = 4
    private let windows: [StackBadgeStackedWindow]
    private var rows: [StackBadgeRowView] = []
    private var selectedIndex = 0

    var selectedWindow: StackBadgeStackedWindow? {
        guard windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex]
    }

    static func rowsThatFit(below top: CGFloat, above bottom: CGFloat) -> Int {
        let available = top - bottom - listPadding * 2
        return max(0, Int(available / rowHeight))
    }

    init(windows: [StackBadgeStackedWindow],
         listTop: CGPoint,
         screenFrame: CGRect,
         onSelect: @escaping (StackBadgeStackedWindow) -> Void) {
        self.windows = windows
        let width: CGFloat = 260
        let padding = Self.listPadding
        let height = CGFloat(windows.count) * Self.rowHeight + padding * 2
        var frame = NSRect(x: listTop.x,
                           y: listTop.y - height,
                           width: width,
                           height: height)
        if frame.maxX > screenFrame.maxX { frame.origin.x = screenFrame.maxX - frame.width }

        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.transient, .ignoresCycle]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        for (index, window) in windows.enumerated() {
            let row = StackBadgeRowView(
                title: window.title,
                icon: Self.appIcon(pid: window.pid),
                onHover: { [weak self] in self?.select(index: index) },
                onClick: { [weak self] in
                    guard let self else { return }
                    self.select(index: index)
                    if let selectedWindow = self.selectedWindow {
                        onSelect(selectedWindow)
                    }
                })
            row.frame = NSRect(x: padding,
                               y: frame.height - padding - CGFloat(index + 1) * Self.rowHeight,
                               width: width - padding * 2,
                               height: Self.rowHeight)
            container.addSubview(row)
            rows.append(row)
        }

        contentView = container
        applySelection()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        applySelection()
    }

    func moveSelection(by delta: Int) {
        guard let next = StackBadgeManager.selection(from: selectedIndex,
                                                     movedBy: delta,
                                                     count: rows.count)
        else { return }
        select(index: next)
    }

    /// `cursor` is where the pointer actually dwelled, which with a screen
    /// gap can sit left of the gap-shifted badge - the corridor has to reach
    /// it or the first move toward the badge counts as leaving.
    func visibleUIFrames(with badge: StackBadgeWindow, triggerCorner: CGPoint, cursor: CGPoint) -> [CGRect] {
        let uiMinX = min(badge.frame.minX, frame.minX, cursor.x)
        let uiMaxX = max(badge.frame.maxX, frame.maxX, cursor.x)
        let corridorBottom = frame.maxY
        let corridorTop = max(triggerCorner.y, cursor.y)
        let corridor = CGRect(x: uiMinX, y: corridorBottom,
                              width: uiMaxX - uiMinX,
                              height: max(0, corridorTop - corridorBottom))
        return [badge.frame, frame, corridor]
    }

    private func applySelection() {
        for (index, row) in rows.enumerated() {
            row.setSelected(index == selectedIndex)
        }
    }

    private static func appIcon(pid: pid_t) -> NSImage? {
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        let size = NSSize(width: 16, height: 16)
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()
        return resized
    }
}
