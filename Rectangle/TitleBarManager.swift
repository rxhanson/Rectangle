/// TitleBarManager.swift

import Foundation

class TitleBarManager {
    private var eventMonitor: EventMonitor!
    private var lastEventNumber: Int?
    private var clicks = TitleBarClickSequence<AccessibilityElement>()

    init() {
        eventMonitor = PassiveEventMonitor(mask: [.leftMouseDown, .leftMouseUp, .leftMouseDragged], handler: handle)
        toggleListening()
        Notification.Name.windowTitleBar.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }
    
    private func toggleListening() {
        clicks.reset()
        if WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil {
            eventMonitor.start()
        } else {
            eventMonitor.stop()
        }
    }
    
    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDragged {
            clicks.reset()
            return
        }
        guard Self.systemSettingDisabled,
              let action = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1),
              let location = event.cgEvent?.location else {
            clicks.reset()
            return
        }
        if event.type == .leftMouseDown {
            // Capture the pressed region before a close/reorder changes the header.
            let window = eligibleWindow(at: location)
            WindowFrostDiagnostics.event("titlebar-press", fields: ["clickCount": event.clickCount,
                "eventTimestamp": event.timestamp, "point": [location.x, location.y],
                "windowID": window?.windowId ?? 0, "doubleClickInterval": NSEvent.doubleClickInterval])
            clicks.press(count: event.clickCount, timestamp: event.timestamp,
                         point: location, window: window, interval: NSEvent.doubleClickInterval)
            return
        }
        guard event.type == .leftMouseUp, event.eventNumber != lastEventNumber else { return }
        lastEventNumber = event.eventNumber
        let pressedWindow = clicks.release(count: event.clickCount, timestamp: event.timestamp, point: location)
        let windowElement = pressedWindow.flatMap { _ in eligibleWindow(at: location) }
        WindowFrostDiagnostics.event("titlebar-release", fields: ["clickCount": event.clickCount,
            "eventTimestamp": event.timestamp, "pressedWindowID": pressedWindow?.windowId ?? 0,
            "windowID": windowElement?.windowId ?? 0])
        guard let pressedWindow, let windowElement, windowElement == pressedWindow else { return }
        let historyAction = windowElement.windowId.flatMap { AppDelegate.windowHistory.lastRectangleActions[$0] }
        let resolvedAction = Self.resolveAction(action,
            restoreEnabled: Defaults.doubleClickTitleBarRestore.enabled != false,
            windowFrame: windowElement.frame,
            pendingFrame: WindowAnimator.shared.logicalFrame(for: windowElement),
            lastAction: historyAction)
        resolvedAction.postTitleBar(windowElement: windowElement)
    }

    private func eligibleWindow(at location: CGPoint) -> AccessibilityElement? {
        guard let hit = AccessibilityElement(location),
              let windowElement = hit.windowElement,
              var titleBarFrame = windowElement.titleBarFrame else { return nil }
        let nativeTitleBarFrame = titleBarFrame
        
        var bundleIdentifier: String?
        if let pid = hit.pid {
            bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        
        if let toolbarFrame = windowElement.getChildElement(.toolbar)?.frame, toolbarFrame != .null {
            if let bundleIdentifier,
               let toolbarIgnoredIds = Defaults.doubleClickToolBarIgnoredApps.typedValue,
               toolbarIgnoredIds.contains(bundleIdentifier) {
               // don't add the toolbar frame to the title bar
            } else {
                titleBarFrame = titleBarFrame.union(toolbarFrame)
            }
        }
        // Most mouse presses are in document content. Avoid descending through
        // that tree just to discover that the point is outside the header.
        guard titleBarFrame.contains(location) else { return nil }
        if let bundleIdentifier,
            let ignoredApps = Defaults.doubleClickTitleBarIgnoredApps.typedValue,
            ignoredApps.contains(bundleIdentifier) {
            return nil
        }
        guard let element = hit.getSelfOrChildElementRecursively(location),
              element.isWindow == true || element.isToolbar == true || element.isGroup == true
                || element.isTabGroup == true || element.isStaticText == true
                || element.isTitleBarSpacer(in: nativeTitleBarFrame) else { return nil }
        // Point hit-testing can return an empty overlay group while the actual
        // button lives in a sibling subtree (notably Chromium's tab strip).
        guard windowElement.isTitleBarPointPassive(location, titleBar: titleBarFrame) else { return nil }
        return windowElement
    }

    static func resolveAction(_ action: WindowAction, restoreEnabled: Bool,
                              windowFrame: CGRect, pendingFrame: CGRect?,
                              lastAction: RectangleAction?) -> WindowAction {
        // During an animation the real window may be parked away from its target.
        let frame = pendingFrame ?? windowFrame
        guard restoreEnabled, frame != .null,
              let lastAction, lastAction.action == action, lastAction.rect == frame
        else { return action }
        return .restore
    }
}

extension TitleBarManager {
    static var systemSettingDisabled: Bool {
        UserDefaults(suiteName: ".GlobalPreferences")?.string(forKey: "AppleActionOnDoubleClick") == "None"
    }
}

/// A control click must not turn into a titlebar click when its UI disappears.
/// NSEvent supplies the system's click count; retain the first press as well.
struct TitleBarClickSequence<Window: Equatable> {
    private struct Press {
        let window: Window
        let point: CGPoint
        let timestamp: TimeInterval
    }
    private var first: Press?
    private var second: Press?
    private var firstReleased = false

    mutating func reset() {
        first = nil
        second = nil
        firstReleased = false
    }

    mutating func press(count: Int, timestamp: TimeInterval, point: CGPoint,
                        window: Window?, interval: TimeInterval) {
        if count == 1 {
            reset()
            if let window { first = Press(window: window, point: point, timestamp: timestamp) }
        } else if count == 2, let first, firstReleased, let window,
                  window == first.window, timestamp >= first.timestamp,
                  timestamp - first.timestamp <= interval,
                  Self.near(point, first.point) {
            second = Press(window: window, point: point, timestamp: timestamp)
        } else {
            reset()
        }
    }

    mutating func release(count: Int, timestamp: TimeInterval, point: CGPoint) -> Window? {
        if count == 1, let first, !firstReleased, timestamp >= first.timestamp,
           Self.near(point, first.point) {
            firstReleased = true
            return nil
        }
        defer { reset() }
        guard count == 2, firstReleased, let second, timestamp >= second.timestamp,
              Self.near(point, second.point) else { return nil }
        return second.window
    }

    private static func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= 4 && abs(a.y - b.y) <= 4
    }
}
