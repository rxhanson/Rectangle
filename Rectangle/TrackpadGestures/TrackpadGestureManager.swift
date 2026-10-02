import AppKit
import Observation

@Observable
final class TrackpadGestureManager {
    static let shared = TrackpadGestureManager()
    var settings: TrackpadGestureSettings {
        didSet {
            guard settings != oldValue else { return }
            Defaults.trackpadGestures.typedValue = settings.validated
            refresh(force: true, checkSystemSettings: settings.enabled != oldValue.enabled || settings.fingers != oldValue.fingers)
        }
    }
    private(set) var status: String?
    private(set) var systemConflict = false
    private var runtime: TrackpadGestureRuntime?
    private var deviceMonitor: TrackpadDeviceMonitor?
    private var cachedSystemFingers: Set<Int>?
    private var macTouchRunning = false
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var suspended = false
    private var activeSettings: TrackpadGestureSettings?
    private var occupiedFingers = Set<Int>()
    private var actionGeneration: UInt = 0

    private init() {
        settings = (Defaults.trackpadGestures.typedValue ?? TrackpadGestureSettings()).validated
    }

    func start() {
        guard !started else { return }
        started = true
        macTouchRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.bozhenpeng.mac-touch")
            .contains { !$0.isTerminated }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspended = true
                self?.refresh(force: true)
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.suspended = false
                self?.refresh(force: true)
            })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.bozhenpeng.mac-touch" else { return }
                self?.macTouchRunning = name == NSWorkspace.didLaunchApplicationNotification
                self?.refresh(checkSystemSettings: false)
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == ProcessInfo.processInfo.processIdentifier ||
                    app.bundleIdentifier == "com.apple.systempreferences" else { return }
            self?.refresh()
        })
        observers.append(center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.systempreferences" else { return }
            self?.refresh()
        })
        Notification.Name.windowActionWillExecute.onPost { [weak self] _ in
            self?.actionGeneration &+= 1
        }
        Notification.Name.configImported.onPost { [weak self] _ in
            self?.settings = (Defaults.trackpadGestures.typedValue ?? TrackpadGestureSettings()).validated
        }
        refresh(force: true)
    }

    func stop() {
        started = false
        deviceMonitor?.stop()
        cachedSystemFingers = nil
        runtime?.stop()
        activeSettings = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    /// Only the explicit off-to-on UI action chooses a finger count.
    func setEnabledByUser(_ enabled: Bool) {
        guard enabled != settings.enabled else { return }
        var updated = settings
        if enabled {
            let occupied = TrackpadSystemGestures.occupiedFingerCounts()
            updated.fingers = occupied.contains(4) && !occupied.contains(3) ? 3 : 4
        }
        updated.enabled = enabled
        settings = updated
    }

    func refreshStatus() {
        refresh(force: true)
    }

    private func refresh(force: Bool = false, checkSystemSettings: Bool = true) {
        guard started else { return }
        if settings.enabled && !suspended {
            if deviceMonitor == nil {
                deviceMonitor = TrackpadDeviceMonitor { [weak self] in
                    self?.refresh(force: true, checkSystemSettings: false)
                }
            }
            deviceMonitor?.start()
            if checkSystemSettings || cachedSystemFingers == nil {
                cachedSystemFingers = TrackpadSystemGestures.occupiedFingerCounts()
            }
        } else {
            deviceMonitor?.stop()
            cachedSystemFingers = nil
        }
        let conflicts = cachedSystemFingers ?? []
        systemConflict = conflicts.contains(settings.fingers)
        var blocked: String?
        if !settings.enabled || suspended {
            blocked = ""
        } else if !AXIsProcessTrusted() {
            blocked = String(localized: "Accessibility access is required.")
        } else if macTouchRunning {
            blocked = String(localized: "Quit MacTouch to use gestures in Rectangle.")
        } else if systemConflict {
            blocked = settings.fingers == 3
                ? String(localized: "macOS is using three-finger gestures. Choose another finger count or change Trackpad settings.")
                : String(localized: "macOS is using four-finger gestures. Choose another finger count or change Trackpad settings.")
        } else if TrackpadMultitouchAPI.shared == nil {
            blocked = String(localized: "Trackpad gestures are unavailable on this system.")
        } else if TrackpadDirection.allCases.allSatisfy({ settings[$0] == TrackpadGestureAction.none }) {
            blocked = String(localized: "Choose an action for at least one direction.")
        }
        if let blocked {
            if activeSettings != nil { runtime?.stop(); activeSettings = nil }
            status = blocked.isEmpty ? nil : blocked
            return
        }
        if runtime == nil {
            let runtime = TrackpadGestureRuntime()
            runtime.onAction = { [weak self] action, target, generation, epoch in
                self?.execute(action, target: target, generation: generation, epoch: epoch)
            }
            runtime.onHealthChange = { [weak self] in
                guard let self, self.activeSettings != nil else { return }
                if self.runtime?.healthy == false { self.runtime?.recheck() }
                self.updateRuntimeStatus()
            }
            self.runtime = runtime
        }
        guard let runtime else { return }
        if force || activeSettings != settings || conflicts != occupiedFingers {
            occupiedFingers = conflicts
            activeSettings = settings
            runtime.start(settings: settings, systemFingers: conflicts)
        } else { runtime.recheck() }
        updateRuntimeStatus()
    }

    private func updateRuntimeStatus() {
        guard activeSettings != nil, let runtime else { return }
        if runtime.deviceCount == 0 { status = String(localized: "No trackpad connected.") }
        else if !runtime.healthy { status = String(localized: "Gesture capture is unavailable. Gestures are paused.") }
        else { status = nil }
    }

    private func execute(_ action: Int, target: TrackpadCursorWindowShortcutTargeter.Target,
                         generation: UInt, epoch: UInt) {
        guard runtime?.accepts(generation: generation, epoch: epoch) == true,
              let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if let bundle = app.bundleIdentifier,
           Defaults.disabledApps.typedValue?.contains(bundle) == true || Defaults.fullIgnoreBundleIds.typedValue?.contains(bundle) == true { return }
        let element = AccessibilityElement(target.window, messagingTimeout: 0.1)
        guard let windowID = element.getWindowId(), element.isMinimized != true,
              element.pid == target.pid else { return }
        let isCurrent = beginAction(action) { [weak self] in
            self?.runtime?.accepts(generation: generation, epoch: epoch) == true
        }
        if action == TrackpadGestureAction.minimize {
            WindowAnimator.shared.cancel(for: element)
            guard isCurrent(), element.getWindowId() == windowID else { return }
            AXUIElementSetAttributeValue(target.window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            return
        }
        guard let windowAction = WindowAction(rawValue: action), TrackpadGestureAction.isValid(action) else { return }
        element.activateAndRaiseWindow(isCurrent: isCurrent) { _, _, raise in
            guard raise == .success, isCurrent(), element.getWindowId() == windowID else { return }
            NotificationCenter.default.post(name: windowAction.notificationName,
                object: ExecutionParameters(windowAction, windowElement: element, windowId: windowID, source: .trackpadGesture))
        }
    }

    // Announce minimization before taking its token: our notification observer
    // invalidates older work, and must not invalidate this new minimize itself.
    func beginAction(_ action: Int, runtimeIsCurrent: @escaping () -> Bool) -> () -> Bool {
        if action == TrackpadGestureAction.minimize {
            Notification.Name.windowActionWillExecute.post()
        }
        actionGeneration &+= 1
        let actionToken = actionGeneration
        return { [weak self] in
            self?.actionGeneration == actionToken && runtimeIsCurrent()
        }
    }
}
