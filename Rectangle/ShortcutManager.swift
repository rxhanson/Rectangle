/// ShortcutManager.swift

import Cocoa
import CoreGraphics
import MASShortcut

protocol ShortcutBindingStore {
    func configure()
    func registerDefaultShortcuts(_ shortcuts: [String: MASShortcut])
    func bindShortcut(withDefaultsKey defaultsKey: String, toAction action: @escaping () -> Void)
    func breakBinding(withDefaultsKey defaultsKey: String)
}

struct MASShortcutBindingStore: ShortcutBindingStore {
    func configure() {
        MASShortcutBinder.shared()?.bindingOptions = [NSBindingOption.valueTransformerName: MASDictionaryTransformerName]
    }

    func registerDefaultShortcuts(_ shortcuts: [String: MASShortcut]) {
        MASShortcutBinder.shared()?.registerDefaultShortcuts(shortcuts)
    }

    func bindShortcut(withDefaultsKey defaultsKey: String, toAction action: @escaping () -> Void) {
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: defaultsKey, toAction: action)
    }

    func breakBinding(withDefaultsKey defaultsKey: String) {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: defaultsKey)
    }
}

typealias ShortcutRebindScheduler = (@escaping () -> Void) -> Void

class ShortcutManager {

    let windowManager: WindowManager
    private let bindingStore: ShortcutBindingStore
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let shortcutsProvider: () -> [WindowAction: MASShortcut]
    private let appDisabledProvider: () -> Bool
    private let scheduler: ShortcutRebindScheduler
    private let todoSessionStateChanged: (Bool) -> Void
    private var boundShortcutActions = Set<WindowAction>()
    private var shortcutIdentities = [WindowAction: ShortcutCycle.ShortcutIdentity]()
    private var isUpdatingShortcutBindings = false
    private var shortcutsSuspendedForRecording = false
    private var sessionIsActive: Bool
    private var sessionRebindPending = false
    private var sessionGeneration = 0

    init(
        windowManager: WindowManager,
        bindingStore: ShortcutBindingStore = MASShortcutBindingStore(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        shortcutsProvider: @escaping () -> [WindowAction: MASShortcut] = { ShortcutCycle.shortcutsByAction() },
        activeStateProvider: () -> Bool = {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            return session?[kCGSessionOnConsoleKey] as? Bool ?? true
        },
        appDisabledProvider: @escaping () -> Bool = { ApplicationToggle.shortcutsDisabled },
        scheduler: @escaping ShortcutRebindScheduler = { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: action)
        },
        todoSessionStateChanged: @escaping (Bool) -> Void = { isActive in
            TodoManager.setShortcutBindingsSessionActive(isActive)
        }
    ) {
        self.windowManager = windowManager
        self.bindingStore = bindingStore
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.shortcutsProvider = shortcutsProvider
        self.appDisabledProvider = appDisabledProvider
        self.scheduler = scheduler
        self.todoSessionStateChanged = todoSessionStateChanged
        self.sessionIsActive = activeStateProvider()

        bindingStore.configure()
        todoSessionStateChanged(sessionIsActive)

        registerDefaults()

        bindShortcuts()

        subscribeAll(selector: #selector(windowActionTriggered))

        notificationCenter.addObserver(self, selector: #selector(defaultShortcutsChanged), name: .changeDefaults, object: nil)
        notificationCenter.addObserver(self, selector: #selector(userDefaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(shortcutRecordingChanged), name: .shortcutRecording, object: nil)
        workspaceNotificationCenter.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceNotificationCenter.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    public func reloadFromDefaults() {
        unsubscribeWindowActions()
        unbindShortcuts()
        registerDefaults()
        bindShortcuts()
        subscribeAll(selector: #selector(windowActionTriggered))
    }

    public func bindShortcuts() {
        guard sessionIsActive,
              !sessionRebindPending,
              !shortcutsSuspendedForRecording,
              !appDisabledProvider()
        else { return }

        let shortcutsByAction = shortcutsProvider()
        let groups = ShortcutCycle.groups(shortcutsByAction: shortcutsByAction)

        shortcutIdentities = ShortcutCycle.shortcutIdentities(shortcutsByAction: shortcutsByAction)

        for group in groups {
            let representativeAction = group.representativeAction
            boundShortcutActions.insert(representativeAction)

            if group.isCycle {
                bindingStore.bindShortcut(withDefaultsKey: representativeAction.name, toAction: { [weak self] in
                    self?.executeCycle(group)
                })
            } else {
                bindingStore.bindShortcut(withDefaultsKey: representativeAction.name, toAction: representativeAction.post)
            }
        }
    }

    public func unbindShortcuts() {
        isUpdatingShortcutBindings = true
        defer { isUpdatingShortcutBindings = false }

        for action in Set(WindowAction.active).union(boundShortcutActions) {
            bindingStore.breakBinding(withDefaultsKey: action.name)
        }

        boundShortcutActions.removeAll()
    }

    public func getKeyEquivalent(action: WindowAction) -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = ShortcutCycle.shortcut(for: action) else { return nil }
        return (masShortcut.keyCodeStringForKeyEquivalent, masShortcut.modifierFlags)
    }

    deinit {
        notificationCenter.removeObserver(self)
        workspaceNotificationCenter.removeObserver(self)
    }

    private func registerDefaults() {

        let defaultShortcuts = WindowAction.active.reduce(into: [String: MASShortcut]()) { dict, windowAction in
            guard let defaultShortcut = Defaults.alternateDefaultShortcuts.enabled
                ? windowAction.alternateDefault
                : windowAction.spectacleDefault
            else { return }
            let shortcut = MASShortcut(keyCode: defaultShortcut.keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: defaultShortcut.modifierFlags))
            dict[windowAction.name] = shortcut
        }

        bindingStore.registerDefaultShortcuts(defaultShortcuts)
    }

    @objc private func sessionDidResignActive(_ notification: Notification) {
        guard sessionIsActive else { return }

        sessionIsActive = false
        sessionRebindPending = false
        sessionGeneration &+= 1
        unbindShortcuts()
        todoSessionStateChanged(false)
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        guard !sessionIsActive else { return }

        sessionIsActive = true
        sessionRebindPending = true
        sessionGeneration &+= 1
        let generation = sessionGeneration

        scheduler { [weak self] in
            guard let self,
                  self.sessionIsActive,
                  self.sessionRebindPending,
                  self.sessionGeneration == generation
            else { return }

            self.sessionRebindPending = false
            self.unbindShortcuts()
            self.bindShortcuts()
            self.todoSessionStateChanged(true)
        }
    }

    @objc func windowActionTriggered(notification: NSNotification) {
        guard let parameters = notification.object as? ExecutionParameters else { return }
        execute(parameters)
    }

    private func execute(_ originalParameters: ExecutionParameters) {
        var parameters = originalParameters

        if MultiWindowManager.execute(parameters: parameters) {
            return
        }

        if TodoManager.execute(parameters: parameters) {
            return
        }

        // Check if repeat cycles displays
        if Defaults.subsequentExecutionMode.value == .cycleMonitor,
           parameters.action.classification != .size,
           parameters.action.classification != .display {
            guard let windowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement(),
                  let windowId = parameters.windowId ?? windowElement.getWindowId()
            else {
                NSSound.beep()
                return
            }

            if isRepeatAction(parameters: parameters, windowElement: windowElement, windowId: windowId) {
                if let screen = ScreenDetection().detectScreens(using: windowElement)?.adjacentScreens?.next{
                    parameters = ExecutionParameters(parameters.action, updateRestoreRect: parameters.updateRestoreRect, screen: screen, windowElement: windowElement, windowId: windowId)
                    // Bypass any other subsequent action by removing the last action
                    AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
                }
            }
        }

        windowManager.execute(parameters)
    }

    private func executeCycle(_ group: ShortcutCycle.Group) {
        guard let windowElement = AccessibilityElement.getFrontWindowElement(),
              let windowId = windowElement.getWindowId()
        else {
            NSSound.beep()
            return
        }

        let lastAction = AppDelegate.windowHistory.lastRectangleActions[windowId]
        if ShortcutCycle.isStale(lastAction: lastAction, currentWindowRect: windowElement.frame) {
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        }

        let selectedAction = ShortcutCycle.action(
            in: group,
            lastAction: AppDelegate.windowHistory.lastRectangleActions[windowId],
            currentWindowRect: windowElement.frame
        )
        execute(ExecutionParameters(selectedAction, windowElement: windowElement, windowId: windowId))
    }

    @objc private func defaultShortcutsChanged() {
        registerDefaults()
        reloadShortcutBindingsIfNeeded()
    }

    @objc private func userDefaultsChanged(_ notification: Notification) {
        reloadShortcutBindingsIfNeeded()
    }

    private func reloadShortcutBindingsIfNeeded() {
        guard !isUpdatingShortcutBindings && !shortcutsSuspendedForRecording else { return }

        MASShortcutMigration.syncRenamedSideShortcutAliases()
        let currentShortcuts = shortcutsProvider()
        let currentIdentities = ShortcutCycle.shortcutIdentities(shortcutsByAction: currentShortcuts)
        guard currentIdentities != shortcutIdentities else { return }

        unbindShortcuts()
        if !appDisabledProvider() {
            bindShortcuts()
        } else {
            shortcutIdentities = currentIdentities
        }
    }

    @objc private func shortcutRecordingChanged(_ notification: Notification) {
        guard let isRecording = notification.object as? Bool else { return }

        if isRecording {
            guard !shortcutsSuspendedForRecording else { return }
            shortcutsSuspendedForRecording = true
            unbindShortcuts()
        } else {
            guard shortcutsSuspendedForRecording else { return }
            shortcutsSuspendedForRecording = false
            if !appDisabledProvider() {
                bindShortcuts()
            } else {
                let currentShortcuts = shortcutsProvider()
                shortcutIdentities = ShortcutCycle.shortcutIdentities(shortcutsByAction: currentShortcuts)
            }
        }
    }

    private func isRepeatAction(parameters: ExecutionParameters, windowElement: AccessibilityElement, windowId: CGWindowID) -> Bool {

        if parameters.action == .maximize {
            if ScreenDetection().detectScreens(using: windowElement)?.currentScreen.visibleFrame.size == windowElement.frame.size {
                return true
            }
        }
        if parameters.action == AppDelegate.windowHistory.lastRectangleActions[windowId]?.action {
            return true
        }
        return false
    }

    private func subscribe(notification: WindowAction, selector: Selector) {
        notificationCenter.addObserver(self, selector: selector, name: notification.notificationName, object: nil)
    }

    private func unsubscribeWindowActions() {
        for windowAction in WindowAction.active {
            notificationCenter.removeObserver(self, name: windowAction.notificationName, object: nil)
        }
    }

    private func subscribeAll(selector: Selector) {
        for windowAction in WindowAction.active {
            subscribe(notification: windowAction, selector: selector)
        }
    }
}

struct ShortcutCycle {

    struct ShortcutIdentity: Hashable {
        let keyCode: Int
        let modifierFlags: UInt

        init(_ shortcut: MASShortcut) {
            keyCode = shortcut.keyCode
            modifierFlags = shortcut.modifierFlags.rawValue
        }
    }

    struct Group {
        let shortcut: MASShortcut
        let actions: [WindowAction]

        var representativeAction: WindowAction { actions[0] }
        var isCycle: Bool { actions.count > 1 }

        func action(after previousAction: WindowAction?) -> WindowAction {
            guard let previousAction,
                  let index = actions.firstIndex(of: previousAction)
            else {
                return representativeAction
            }

            return actions[(index + 1) % actions.count]
        }
    }

    static func shortcut(for action: WindowAction, userDefaults: UserDefaults = .standard) -> MASShortcut? {
        return shortcut(forDefaultsKey: action.name, userDefaults: userDefaults)
    }

    static func shortcut(forDefaultsKey defaultsKey: String, userDefaults: UserDefaults = .standard) -> MASShortcut? {
        guard let shortcutDict = userDefaults.dictionary(forKey: defaultsKey),
              let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)),
              let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
        else {
            return nil
        }

        return shortcut
    }

    static func shortcutsByAction(actions: [WindowAction] = WindowAction.active, userDefaults: UserDefaults = .standard) -> [WindowAction: MASShortcut] {
        actions.reduce(into: [WindowAction: MASShortcut]()) { dict, action in
            if let shortcut = shortcut(for: action, userDefaults: userDefaults) {
                dict[action] = shortcut
            }
        }
    }

    static func shortcutIdentities(shortcutsByAction: [WindowAction: MASShortcut]) -> [WindowAction: ShortcutIdentity] {
        shortcutsByAction.reduce(into: [WindowAction: ShortcutIdentity]()) { dict, item in
            dict[item.key] = ShortcutIdentity(item.value)
        }
    }

    static func groups(actions: [WindowAction] = WindowAction.active,
                       shortcutsByAction: [WindowAction: MASShortcut]) -> [Group] {
        var groups = [Group]()
        var groupIndexesByShortcut = [ShortcutIdentity: Int]()

        for action in actions {
            guard let shortcut = shortcutsByAction[action] else { continue }

            let identity = ShortcutIdentity(shortcut)
            if let groupIndex = groupIndexesByShortcut[identity] {
                let group = groups[groupIndex]
                groups[groupIndex] = Group(shortcut: group.shortcut, actions: group.actions + [action])
            } else {
                groupIndexesByShortcut[identity] = groups.count
                groups.append(Group(shortcut: shortcut, actions: [action]))
            }
        }

        return groups
    }

    static func action(in group: Group, lastAction: RectangleAction?, currentWindowRect: CGRect?) -> WindowAction {
        guard !isStale(lastAction: lastAction, currentWindowRect: currentWindowRect) else {
            return group.representativeAction
        }

        return group.action(after: lastAction?.action)
    }

    static func isStale(lastAction: RectangleAction?, currentWindowRect: CGRect?) -> Bool {
        guard let lastAction, let currentWindowRect else { return false }
        return currentWindowRect != lastAction.rect
    }
}
