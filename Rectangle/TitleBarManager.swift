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
        let location = event.cgEvent?.location ?? NSEvent.mouseLocation.screenFlipped
        tabButtonPress.handle(event) { [weak self] in
            self?.handleDoubleClick(event, at: location)
        }
    }

    private func handleDoubleClick(_ event: NSEvent, at location: CGPoint) {
        guard
            event.type == .leftMouseUp,
            event.clickCount == 2,
            event.eventNumber != lastEventNumber,
            TitleBarManager.systemSettingDisabled,
            let action = WindowAction(rawValue: Defaults.doubleClickTitleBar.value - 1),
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

/// Closing a tab can expose the title bar before mouse-up. Remember a confirmed
/// tab-button press so that closing two tabs cannot trigger a title-bar double-click.
private final class TitleBarTabButtonPress {
    private let worker = DispatchQueue(label: "com.knollsoft.Rectangle.titlebar-button", qos: .userInitiated)
    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var activation: NSObjectProtocol?
    private var generation = UUID()
    private let sequence = TitleBarClickSequence()
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
        sequence.reset()
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
                // The matching mouse-down may still be queued on the main run loop.
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

    func handle(_ event: NSEvent, completion: @escaping () -> Void) {
        guard event.type == .leftMouseDown || event.type == .leftMouseUp,
              let cgEvent = event.cgEvent else { resetClick(); return }
        let raw = cgEvent.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        let window = CGWindowID(exactly: raw > 0 ? raw : cgEvent.getIntegerValueField(.mouseEventWindowUnderMousePointer)) ?? 0
        if event.type == .leftMouseDown {
            sequence.mouseDown(window: window, point: cgEvent.location, time: event.timestamp,
                               count: event.clickCount, interval: NSEvent.doubleClickInterval)
            read(at: event.timestamp) { click in
                let system = AXUIElementCreateSystemWide()
                AXUIElementSetMessagingTimeout(system, 0.01)
                var element: AXUIElement?
                guard AXUIElementCopyElementAtPosition(system, Float(click.point.x), Float(click.point.y), &element) == .success,
                      let element else { return false }
                return Self.isTabButton(element, click: click)
            }
        } else if event.clickCount == 2 {
            guard let click = sequence.finish(window: window, completion: { veto in
                if !veto { completion() }
            }) else { completion(); return }
            // Let queued AX notifications join the decision, without blocking input.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.sequence.settle(click)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.sequence.settle(click, timedOut: true)
            }
        }
    }

    private func received(_ element: AXUIElement, from observer: AXObserver, at time: TimeInterval) {
        guard let current = self.observer, CFEqual(current, observer) else { return }
        read(at: time) { Self.isTabButton(element, click: $0) }
    }

    private func read(at time: TimeInterval, classify: @escaping (TitleBarClickSequence.Click) -> Bool) {
        guard pendingReads < 4, let click = sequence.beginRead(at: time, interval: NSEvent.doubleClickInterval) else { return }
        pendingReads += 1
        worker.async { [weak self] in
            let positive = classify(click)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingReads -= 1
                self.sequence.endRead(click, positive: positive)
            }
        }
    }

    private static func isTabButton(_ element: AXUIElement, click: TitleBarClickSequence.Click) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.04
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            AXUIElementSetMessagingTimeout(element, Float(min(0.01, remaining)))
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
        }
        guard value(element, kAXRoleAttribute) as? String == kAXButtonRole,
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

// Classification belongs to the click sequence, even when AX replies after mouse-up.
final class TitleBarClickSequence {
    final class Click {
        let window: CGWindowID
        let point: CGPoint
        let time: TimeInterval
        var pendingReads = 0
        var confirmed = false
        var settled = false
        var completion: ((Bool) -> Void)?

        init(window: CGWindowID, point: CGPoint, time: TimeInterval) {
            self.window = window
            self.point = point
            self.time = time
        }
    }

    private var click: Click?

    func reset() { click = nil }

    func mouseDown(window: CGWindowID, point: CGPoint, time: TimeInterval, count: Int, interval: TimeInterval) {
        if count == 1 {
            click = window == 0 ? nil : Click(window: window, point: point, time: time)
        } else if count != 2 || click?.window != window || time - (click?.time ?? 0) > interval {
            reset()
        }
    }

    func beginRead(at time: TimeInterval, interval: TimeInterval) -> Click? {
        guard let click, !click.confirmed, time >= click.time, time - click.time <= interval else { return nil }
        click.pendingReads += 1
        return click
    }

    func endRead(_ click: Click, positive: Bool) {
        guard self.click === click else { return }
        click.pendingReads -= 1
        click.confirmed = click.confirmed || positive
        completeIfReady(click)
    }

    func finish(window: CGWindowID, completion: @escaping (Bool) -> Void) -> Click? {
        guard let click, click.window == window else { reset(); return nil }
        click.completion = completion
        return click
    }

    func settle(_ click: Click, timedOut: Bool = false) {
        guard self.click === click else { return }
        click.settled = true
        completeIfReady(click, timedOut: timedOut)
    }

    private func completeIfReady(_ click: Click, timedOut: Bool = false) {
        guard click.settled, click.confirmed || click.pendingReads == 0 || timedOut,
              let completion = click.completion else { return }
        self.click = nil
        completion(click.confirmed)
    }
}
