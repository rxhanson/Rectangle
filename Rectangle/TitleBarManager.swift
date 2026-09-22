/// TitleBarManager.swift

import Foundation

class TitleBarManager {
    private var eventMonitor: EventMonitor!
    private var lastEventNumber: Int?
    private let tabButtonPress = TitleBarTabButtonPress()

    init() {
        eventMonitor = PassiveEventMonitor(mask: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .keyDown], handler: handle)
        toggleListening()
        Notification.Name.windowTitleBar.onPost { notification in
            self.toggleListening()
        }
        Notification.Name.configImported.onPost { notification in
            self.toggleListening()
        }
    }
    
    private func toggleListening() {
        if WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1) != nil {
            tabButtonPress.start()
            if !eventMonitor.running { eventMonitor.start() }
        } else {
            tabButtonPress.stop()
            eventMonitor.stop()
        }
    }
    
    private func handle(_ event: NSEvent) {
        let pressedTabButton = tabButtonPress.handle(event)
        guard
            event.type == .leftMouseUp,
            !pressedTabButton,
            event.clickCount == 2,
            event.eventNumber != lastEventNumber,
            TitleBarManager.systemSettingDisabled,
            let action = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1),
            case let location = NSEvent.mouseLocation.screenFlipped,
            let element = AccessibilityElement(location)?.getSelfOrChildElementRecursively(location),
            let windowElement = element.windowElement,
            var titleBarFrame = windowElement.titleBarFrame
        else {
            return
        }
        lastEventNumber = event.eventNumber
        let isTitleBarSpacer = element.isTitleBarSpacer(in: titleBarFrame)
        
        var bundleIdentifier: String?
        if let pid = element.pid {
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
        guard
            titleBarFrame.contains(location),
            element.isWindow == true || element.isToolbar == true || element.isGroup == true || element.isTabGroup == true || element.isStaticText == true || isTitleBarSpacer
        else {
            return
        }
        if let bundleIdentifier,
            let ignoredApps = Defaults.doubleClickTitleBarIgnoredApps.typedValue,
            ignoredApps.contains(bundleIdentifier) {
            return
        }
        let historyAction = windowElement.windowId.flatMap { AppDelegate.windowHistory.lastRectangleActions[$0] }
        let resolvedAction = Self.resolveAction(action,
            restoreEnabled: Defaults.doubleClickTitleBarRestore.enabled != false,
            windowFrame: windowElement.frame,
            pendingFrame: WindowAnimator.shared.logicalFrame(for: windowElement),
            lastAction: historyAction)
        let clickedScreen = Self.screenForClick(at: location.screenFlipped, screens: NSScreen.screens)
        resolvedAction.postTitleBar(windowElement: windowElement, screen: clickedScreen)
    }

    static func screenForClick(at location: CGPoint, screens: [NSScreen]) -> NSScreen? {
        screens.first { $0.frame.contains(location) }
    }

    static func resolveAction(_ action: WindowAction, restoreEnabled: Bool,
                              windowFrame: CGRect, pendingFrame: CGRect?,
                              lastAction: RectangleAction?) -> WindowAction {
        // During an animation the real window may not have reached its target.
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

/// A tab button can disappear before mouse-up exposes the title-bar background.
/// Only a confirmed press vetoes the gesture; missing AX evidence leaves it unchanged.
private final class TitleBarTabButtonPress {
    private struct Click {
        let token = UUID()
        let window: CGWindowID
        let point: CGPoint
        let time: TimeInterval
    }

    private let worker = DispatchQueue(label: "com.knollsoft.Rectangle.titlebar-button", qos: .userInitiated)
    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var activation: NSObjectProtocol?
    private var generation = UUID()
    private var click: Click?
    private var held = false
    private var confirmed = false
    private var pendingReads = 0

    func start() {
        guard activation == nil else { return }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.observeApplication(app?.processIdentifier)
        }
        observeApplication(NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func stop() {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        removeObserver()
    }

    deinit { stop() }

    private func resetClick() {
        click = nil
        held = false
        confirmed = false
    }

    private func removeObserver() {
        generation = UUID()
        resetClick()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedApplication = nil
    }

    private func observeApplication(_ pid: pid_t?) {
        removeObserver()
        guard let pid,
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        register(pid: pid, generation: generation, attempt: 0)
    }

    private func register(pid: pid_t, generation: UUID, attempt: Int) {
        worker.async { [weak self] in
            guard let self else { return }
            var observer: AXObserver?
            let callback: AXObserverCallback = { observer, element, _, context in
                guard let context else { return }
                let owner = Unmanaged<TitleBarTabButtonPress>.fromOpaque(context).takeUnretainedValue()
                let received = ProcessInfo.processInfo.systemUptime
                // Mouse and AX notifications may arrive in the same run-loop iteration.
                DispatchQueue.main.async { [weak owner] in
                    owner?.received(element, from: observer, at: received)
                }
            }
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.03)
            let result = AXObserverAddNotification(observer, app, kAXValueChangedNotification as CFString,
                                                   Unmanaged.passUnretained(self).toOpaque())
            guard result == .success else {
                // Newly launched applications may not have an AX server ready yet.
                if result == .cannotComplete, attempt < 4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * pow(2, Double(attempt))) { [weak self] in
                        guard let self, self.generation == generation else { return }
                        self.register(pid: pid, generation: generation, attempt: attempt + 1)
                    }
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.observer = observer
                self.observedApplication = app
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown || event.type == .leftMouseUp,
              let cgEvent = event.cgEvent else { resetClick(); return false }
        let raw = cgEvent.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        let window = CGWindowID(exactly: raw > 0 ? raw : cgEvent.getIntegerValueField(.mouseEventWindowUnderMousePointer)) ?? 0
        if event.type == .leftMouseDown {
            if event.clickCount == 1 {
                resetClick()
                if window != 0 { click = Click(window: window, point: cgEvent.location, time: event.timestamp) }
            } else if event.clickCount != 2 || click?.window != window
                        || event.timestamp - (click?.time ?? 0) > NSEvent.doubleClickInterval {
                resetClick()
            }
            held = true
            return false
        }
        held = false
        guard event.clickCount == 2 else { return false }
        let veto = confirmed && click?.window == window
        resetClick()
        return veto
    }

    private func received(_ element: AXUIElement, from observer: AXObserver, at time: TimeInterval) {
        guard let current = self.observer, CFEqual(current, observer),
              let click, held, !confirmed, pendingReads < 4,
              time >= click.time, time - click.time <= NSEvent.doubleClickInterval else { return }
        pendingReads += 1
        worker.async { [weak self] in
            let positive = Self.isPressedTabButton(element, click: click)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingReads -= 1
                if positive, self.click?.token == click.token { self.confirmed = true }
            }
        }
    }

    private static func isPressedTabButton(_ element: AXUIElement, click: Click) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.04
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            AXUIElementSetMessagingTimeout(element, Float(min(0.01, remaining)))
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
        }
        guard value(element, kAXRoleAttribute) as? String == kAXButtonRole,
              let pressed = value(element, kAXValueAttribute) as? NSNumber, pressed.intValue == 1,
              let position = value(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return false }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              CGRect(origin: point, size: dimensions).contains(click.point) else { return false }
        var node = element, tab = false, tabGroup = false
        for _ in 0..<12 {
            guard let role = value(node, kAXRoleAttribute) as? String else { return false }
            tab = tab || role == kAXRadioButtonRole
            tabGroup = tabGroup || role == kAXTabGroupRole
            if role == kAXWindowRole { return tab && tabGroup && node.getWindowId() == click.window }
            guard let parent = value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            node = parent as! AXUIElement
        }
        return false
    }
}
