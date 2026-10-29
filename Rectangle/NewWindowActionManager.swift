/// NewWindowActionManager.swift

import Cocoa

/// Applies one window action to every window an application opens, when the
/// hidden `newWindowAction` preference names that action (see TerminalCommands.md).
///
/// Nothing is observed while the preference is unset, so there is no cost for
/// anyone who has not opted in. Each regular application gets an observer for
/// window creation; applications that launch later are picked up through
/// NSWorkspace, and the windows they restore while launching count as new.
/// Windows that already exist when observation starts are left alone.
final class NewWindowActionManager {

    struct Application: Equatable {
        let pid: pid_t
        let bundleIdentifier: String?
        let isRegular: Bool
        let isFinishedLaunching: Bool

        init(pid: pid_t, bundleIdentifier: String?, isRegular: Bool = true, isFinishedLaunching: Bool = true) {
            self.pid = pid
            self.bundleIdentifier = bundleIdentifier
            self.isRegular = isRegular
            self.isFinishedLaunching = isFinishedLaunching
        }

        init(_ application: NSRunningApplication) {
            self.init(pid: application.processIdentifier,
                      bundleIdentifier: application.bundleIdentifier,
                      isRegular: application.activationPolicy == .regular,
                      isFinishedLaunching: application.isFinishedLaunching)
        }
    }

    /// Time between a window appearing and the action, so the application can
    /// finish its own initial placement first.
    static let defaultDelay: TimeInterval = 0.15

    /// Cap on each Accessibility read made while checking a new window. These
    /// run on the main thread against an application that may be busy, so a
    /// window that cannot answer in time is skipped rather than waited for.
    /// The placement itself runs with the default timeout, like a shortcut.
    static let probeTimeout: Float = 0.1

    private let ownPid: pid_t
    private let delay: TimeInterval
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let observers: WindowCreationObserving
    private let actionProvider: () -> WindowAction?
    private let runningApplications: () -> [Application]
    private let existingWindows: (pid_t) -> [AccessibilityElement]
    private let isIgnoredApp: (String) -> Bool
    private let execute: (ExecutionParameters) -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let isPrimaryMouseButtonDown: () -> Bool

    private(set) var action: WindowAction?
    private var observations = [pid_t: Observation]()
    private var handledWindowIds = HandledWindowIds()
    private var workspaceObservers = [NSObjectProtocol]()
    private var configObserver: NSObjectProtocol?

    init(
        ownPid: pid_t = ProcessInfo.processInfo.processIdentifier,
        delay: TimeInterval = NewWindowActionManager.defaultDelay,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        observers: WindowCreationObserving = AccessibilityWindowCreationObserver(),
        actionProvider: @escaping () -> WindowAction? = {
            NewWindowActionPolicy.action(named: Defaults.newWindowAction.value)
        },
        runningApplications: @escaping () -> [Application] = {
            NSWorkspace.shared.runningApplications.map(Application.init)
        },
        existingWindows: @escaping (pid_t) -> [AccessibilityElement] = { pid in
            let application = AccessibilityElement(pid)
            application.setMessagingTimeout(NewWindowActionManager.probeTimeout)
            return application.windowElements ?? []
        },
        isIgnoredApp: @escaping (String) -> Bool = { bundleId in
            Defaults.disabledApps.typedValue?.contains(bundleId) == true
                || (Defaults.todo.userEnabled && Defaults.todoMode.enabled && Defaults.todoApplication.value == bundleId)
        },
        execute: @escaping (ExecutionParameters) -> Void = { parameters in
            NotificationCenter.default.post(name: parameters.action.notificationName, object: parameters)
        },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, body in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: body)
        },
        isPrimaryMouseButtonDown: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    ) {
        self.ownPid = ownPid
        self.delay = delay
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.observers = observers
        self.actionProvider = actionProvider
        self.runningApplications = runningApplications
        self.existingWindows = existingWindows
        self.isIgnoredApp = isIgnoredApp
        self.execute = execute
        self.schedule = schedule
        self.isPrimaryMouseButtonDown = isPrimaryMouseButtonDown

        reloadFromDefaults()
        configObserver = notificationCenter.addObserver(forName: .configImported, object: nil, queue: .main) { [weak self] _ in
            self?.reloadFromDefaults()
        }
    }

    deinit {
        stop()
        if let configObserver {
            notificationCenter.removeObserver(configObserver)
        }
    }

    var observedProcessIdentifiers: Set<pid_t> {
        Set(observations.keys)
    }

    func reloadFromDefaults() {
        stop()
        action = actionProvider()
        guard action != nil else { return }

        // An application still launching is left to its launch notification, so
        // the windows it restores count as new and its retries start once it is up.
        for application in runningApplications() where application.isFinishedLaunching {
            observe(application, applyExistingWindows: false)
        }
        workspaceObservers = [
            workspaceNotificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.applicationDidLaunch(Application(application))
            },
            workspaceNotificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.applicationDidActivate(Application(application))
            },
            workspaceNotificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.applicationDidTerminate(pid: application.processIdentifier)
            }
        ]
    }

    /// The windows an application has when its launch notification arrives are
    /// the ones it restored or opened while starting up: they count as new. An
    /// application the user opens is usually activated before it finishes
    /// launching, so an observation that activation started is upgraded here.
    func applicationDidLaunch(_ application: Application) {
        if let observation = observations[application.pid] {
            if observation.isReady {
                applyExistingWindows(of: application)
            } else {
                observation.applyExistingWindows = true
            }
            return
        }
        observe(application, applyExistingWindows: true)
    }

    /// A no-op for an observed application. For one whose observer could not be
    /// attached, or that only now became a regular application, this is the
    /// second chance; its existing windows are the user's, so they stay put.
    func applicationDidActivate(_ application: Application) {
        observe(application, applyExistingWindows: false)
    }

    func applicationDidTerminate(pid: pid_t) {
        observations.removeValue(forKey: pid)
    }

    private func stop() {
        observations.removeAll()
        workspaceObservers.forEach(workspaceNotificationCenter.removeObserver)
        workspaceObservers.removeAll()
    }

    private func observe(_ application: Application, applyExistingWindows: Bool) {
        let pid = application.pid
        guard action != nil, application.isRegular, pid != ownPid, observations[pid] == nil else { return }

        // Registered before observing so a synchronous onReady finds it. The
        // callbacks check identity, so a replaced observation's late callbacks are ignored.
        let observation = Observation(applyExistingWindows: applyExistingWindows)
        observations[pid] = observation
        let token = observers.observeWindowCreation(pid: pid, onReady: { [weak self, weak observation] in
            guard let self, let observation, self.observations[pid] === observation else { return }
            observation.isReady = true
            if observation.applyExistingWindows {
                self.applyExistingWindows(of: application)
            }
        }, onWindowCreated: { [weak self, weak observation] window in
            guard let self, let observation, self.observations[pid] === observation else { return }
            self.windowAppeared(window, in: application)
        }, onFailed: { [weak self, weak observation] in
            guard let self, let observation, self.observations[pid] === observation else { return }
            self.observations.removeValue(forKey: pid)
        })
        if let token {
            observation.token = token
        } else {
            observations.removeValue(forKey: pid)
        }
    }

    private func applyExistingWindows(of application: Application) {
        for window in existingWindows(application.pid) {
            windowAppeared(window, in: application)
        }
    }

    private func windowAppeared(_ window: AccessibilityElement, in application: Application) {
        guard let action else { return }
        let pid = application.pid
        schedule(delay) { [weak self] in
            guard let self, self.action == action, self.observations[pid] != nil else { return }
            // A window that appears while the button is held, such as a tab torn
            // off into its own window, is being placed by the user's drag.
            guard !self.isPrimaryMouseButtonDown() else { return }
            window.setMessagingTimeout(Self.probeTimeout)
            let windowId = window.getWindowId()
            let candidate = NewWindowActionPolicy.Candidate(pid: pid,
                                                            bundleIdentifier: application.bundleIdentifier,
                                                            windowId: windowId,
                                                            isStandardWindow: window.isStandardWindow,
                                                            isSheet: window.isSheet,
                                                            isMinimized: window.isMinimized,
                                                            isFullScreen: window.isFullScreen,
                                                            hasFrame: !window.frame.isNull)
            // Back to the default timeout: placement behaves exactly as it does for a shortcut.
            window.setMessagingTimeout(0)
            if candidate.isStandardWindow == nil {
                Logger.log("A new window of \(application.bundleIdentifier ?? String(pid)) did not answer in time, leaving it alone")
            }
            guard NewWindowActionPolicy.shouldApply(candidate,
                                                    ownPid: self.ownPid,
                                                    isIgnoredApp: self.isIgnoredApp,
                                                    alreadyHandled: self.handledWindowIds.contains) else { return }
            self.handledWindowIds.insert(windowId)
            Logger.log("Applying \(action.name) to a new window of \(application.bundleIdentifier ?? String(pid))")
            self.execute(ExecutionParameters(action, windowElement: window, windowId: windowId,
                                             source: .newWindow, preservesFocus: true))
        }
    }

    /// One process being observed. `token` keeps the observer alive; until it
    /// is ready, the launch notification can still switch on `applyExistingWindows`.
    private final class Observation {
        var token: AnyObject?
        var applyExistingWindows: Bool
        var isReady = false

        init(applyExistingWindows: Bool) {
            self.applyExistingWindows = applyExistingWindows
        }
    }

    /// The window ids already acted on, bounded so a long session cannot grow it forever.
    private struct HandledWindowIds {
        private var ids = Set<CGWindowID>()
        private var order = [CGWindowID]()
        private let limit = 512

        func contains(_ id: CGWindowID) -> Bool {
            ids.contains(id)
        }

        mutating func insert(_ id: CGWindowID?) {
            guard let id, ids.insert(id).inserted else { return }
            order.append(id)
            if order.count > limit {
                ids.remove(order.removeFirst())
            }
        }
    }
}

enum NewWindowActionPolicy {

    struct Candidate {
        var pid: pid_t
        var bundleIdentifier: String?
        var windowId: CGWindowID?
        var isStandardWindow: Bool?
        var isSheet: Bool?
        var isMinimized: Bool?
        var isFullScreen: Bool?
        var hasFrame: Bool
    }

    /// Actions that arrange other windows rather than place this one, or that
    /// have nothing to do on a window that just opened.
    static let notForNewWindows: Set<WindowAction> = [
        .reverseAll, .tileAll, .tileRows, .tileColumns, .cascadeAll, .cascadeActiveApp, .tileActiveApp,
        .cycleStackedWindows, .cycleStackedWindowsBackward, .leftTodo, .rightTodo, .restore
    ]

    /// The single-window action a `newWindowAction` value names: the URL-scheme form
    /// (`left-half`), the shortcut name (`leftHalf`) or an alias (`leftSide`).
    /// Display moves are rejected by classification: with one display, or a window
    /// already on the target display, they would answer every new window with a beep.
    /// Nil disables the feature.
    static func action(named value: String?) -> WindowAction? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        return WindowAction.active.first { action in
            !notForNewWindows.contains(action)
                && action.classification != .display
                && [action.name, action.aliasName].compactMap { $0 }.contains { name in
                    name.lowercased() == value || urlName(name) == value
                }
        }
    }

    /// `leftHalf` becomes `left-half`, the form the URL scheme uses.
    static func urlName(_ name: String) -> String {
        name.map { $0.isUppercase ? "-" + $0.lowercased() : String($0) }.joined()
    }

    /// Ordinary windows of other applications, once each. Dialogs, sheets, palettes,
    /// minimized and full-screen windows, windows that have gone away and apps on
    /// the ignore list are left alone. A window without an id cannot be deduplicated,
    /// so it is still handled.
    static func shouldApply(_ candidate: Candidate,
                            ownPid: pid_t,
                            isIgnoredApp: (String) -> Bool,
                            alreadyHandled: (CGWindowID) -> Bool) -> Bool {
        guard candidate.pid != ownPid,
              candidate.hasFrame,
              candidate.isStandardWindow == true,
              candidate.isSheet != true,
              candidate.isMinimized != true,
              candidate.isFullScreen != true
        else { return false }
        if let bundleIdentifier = candidate.bundleIdentifier, isIgnoredApp(bundleIdentifier) {
            return false
        }
        if let windowId = candidate.windowId, alreadyHandled(windowId) {
            return false
        }
        return true
    }
}

protocol WindowCreationObserving: AnyObject {
    /// Delivers the windows `pid` creates to `onWindowCreated` on the main thread and
    /// calls `onReady` once observation is in place (a launching application needs a
    /// moment), or `onFailed` once it has given up. The returned token keeps the
    /// observation alive; nil means the process could not be observed at all.
    func observeWindowCreation(pid: pid_t,
                               onReady: @escaping () -> Void,
                               onWindowCreated: @escaping (AccessibilityElement) -> Void,
                               onFailed: @escaping () -> Void) -> AnyObject?
}

/// AXObserver-backed window creation source. Attaching can block on a process
/// whose accessibility server is not up yet, so it happens on a worker queue
/// with a few retries, the way TitleBarManager attaches its observer.
final class AccessibilityWindowCreationObserver: WindowCreationObserving {

    private final class Token {
        var observer: AXObserver?
        var onWindowCreated: ((AccessibilityElement) -> Void)?

        deinit {
            if let observer {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
    }

    /// Registration runs on the worker queue, so this cap costs the main thread nothing.
    private static let attachTimeout: Float = 0.25
    /// Retries at 0.2, 0.4, 0.8, 1.6, 3.2 and 6.4 s: a heavy application can take
    /// a while after launching before its accessibility server answers.
    private static let attachAttempts = 6

    private let worker = DispatchQueue(label: "com.knollsoft.Rectangle.new-window-action", qos: .utility)

    func observeWindowCreation(pid: pid_t,
                               onReady: @escaping () -> Void,
                               onWindowCreated: @escaping (AccessibilityElement) -> Void,
                               onFailed: @escaping () -> Void) -> AnyObject? {
        let token = Token()
        token.onWindowCreated = onWindowCreated
        attach(pid: pid, token: token, attempt: 0, onReady: onReady, onFailed: onFailed)
        return token
    }

    /// Every step holds the token weakly: once the manager drops it, the
    /// observation is abandoned wherever it was.
    private func attach(pid: pid_t, token: Token, attempt: Int,
                        onReady: @escaping () -> Void, onFailed: @escaping () -> Void) {
        worker.async { [weak self, weak token] in
            guard let self, let token else { return }
            func giveUp(_ error: AXError) {
                DispatchQueue.main.async { [weak token] in
                    guard token != nil else { return }
                    Logger.log("Unable to observe new windows of pid \(pid) (AXError \(error.rawValue))")
                    onFailed()
                }
            }
            var observer: AXObserver?
            let callback: AXObserverCallback = { _, element, _, context in
                guard let context else { return }
                let token = Unmanaged<Token>.fromOpaque(context).takeUnretainedValue()
                token.onWindowCreated?(AccessibilityElement(element))
            }
            let created = AXObserverCreate(pid, callback, &observer)
            guard created == .success, let observer else { return giveUp(created) }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, Self.attachTimeout)
            let result = AXObserverAddNotification(observer, application, kAXWindowCreatedNotification as CFString,
                                                   Unmanaged.passUnretained(token).toOpaque())
            guard result == .success else {
                // A newly launched application may not have an accessibility server yet.
                if result == .cannotComplete, attempt < Self.attachAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * pow(2, Double(attempt))) { [weak self, weak token] in
                        guard let self, let token else { return }
                        self.attach(pid: pid, token: token, attempt: attempt + 1, onReady: onReady, onFailed: onFailed)
                    }
                } else {
                    giveUp(result)
                }
                return
            }
            DispatchQueue.main.async { [weak token] in
                guard let token else { return }
                token.observer = observer
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                onReady()
            }
        }
    }
}
