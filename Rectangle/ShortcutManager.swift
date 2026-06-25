/// ShortcutManager.swift

import Foundation
import MASShortcut

class ShortcutManager {

    let windowManager: WindowManager
    private let shortcutMonitor = MASShortcutMonitor.shared()!
    private var registeredShortcuts = [String: MASShortcut]()
    private var shortcutIdentities = [WindowAction: ShortcutCycle.ShortcutIdentity]()
    private var isUpdatingShortcutBindings = false
    private var shortcutsSuspendedForRecording = false

    init(windowManager: WindowManager) {
        self.windowManager = windowManager

        bindShortcuts()

        subscribeAll(selector: #selector(windowActionTriggered))

        NotificationCenter.default.addObserver(self, selector: #selector(defaultShortcutsChanged), name: .changeDefaults, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutRecordingChanged), name: .shortcutRecording, object: nil)
        Notification.Name.shortcutsChanged.onPost { _ in
            self.reloadShortcutBindingsIfNeeded()
        }
    }

    public func reloadFromDefaults() {
        unbindShortcuts()
        bindShortcuts()
    }

    public func bindShortcuts() {
        guard !shortcutsSuspendedForRecording else { return }

        let shortcutsByAction = ShortcutCycle.shortcutsByAction()
        let groups = ShortcutCycle.groups(shortcutsByAction: shortcutsByAction)

        shortcutIdentities = ShortcutCycle.shortcutIdentities(shortcutsByAction: shortcutsByAction)

        for group in groups {
            let representativeAction = group.representativeAction
            let action: () -> Void = group.isCycle
                ? { [weak self] in self?.executeCycle(group) }
                : representativeAction.post
            if shortcutMonitor.register(group.shortcut, withAction: action) {
                registeredShortcuts[representativeAction.name] = group.shortcut
            } else {
                Logger.log("Unable to register shortcut for \(representativeAction.name)")
            }
        }
    }

    public func unbindShortcuts() {
        isUpdatingShortcutBindings = true
        defer { isUpdatingShortcutBindings = false }

        for shortcut in registeredShortcuts.values {
            shortcutMonitor.unregisterShortcut(shortcut)
        }
        registeredShortcuts.removeAll()
    }

    public func getKeyEquivalent(action: WindowAction) -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = ShortcutStore.shortcut(for: action) else { return nil }
        return (masShortcut.keyCodeStringForKeyEquivalent, masShortcut.modifierFlags)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
        reloadShortcutBindingsIfNeeded()
    }

    private func reloadShortcutBindingsIfNeeded() {
        guard !isUpdatingShortcutBindings && !shortcutsSuspendedForRecording else { return }

        MASShortcutMigration.syncRenamedSideShortcutAliases()
        let currentShortcuts = ShortcutCycle.shortcutsByAction()
        let currentIdentities = ShortcutCycle.shortcutIdentities(shortcutsByAction: currentShortcuts)
        guard currentIdentities != shortcutIdentities else { return }

        unbindShortcuts()
        if !ApplicationToggle.shortcutsDisabled {
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
            if !ApplicationToggle.shortcutsDisabled {
                bindShortcuts()
            } else {
                let currentShortcuts = ShortcutCycle.shortcutsByAction()
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
        NotificationCenter.default.addObserver(self, selector: selector, name: notification.notificationName, object: nil)
    }

    private func unsubscribeWindowActions() {
        for windowAction in WindowAction.active {
            NotificationCenter.default.removeObserver(self, name: windowAction.notificationName, object: nil)
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

    static func shortcut(for action: WindowAction) -> MASShortcut? {
        ShortcutStore.shortcut(for: action)
    }

    // For test injection via custom UserDefaults
    static func shortcut(for action: WindowAction, userDefaults: UserDefaults) -> MASShortcut? {
        shortcut(forDefaultsKey: action.name, userDefaults: userDefaults)
    }

    static func shortcut(forDefaultsKey defaultsKey: String) -> MASShortcut? {
        ShortcutStore.shortcut(forKey: defaultsKey)
    }

    // For test injection via custom UserDefaults
    static func shortcut(forDefaultsKey defaultsKey: String, userDefaults: UserDefaults) -> MASShortcut? {
        guard let shortcutDict = userDefaults.dictionary(forKey: defaultsKey),
              let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)),
              let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
        else {
            return nil
        }
        return shortcut
    }

    static func shortcutsByAction(actions: [WindowAction] = WindowAction.active) -> [WindowAction: MASShortcut] {
        actions.reduce(into: [WindowAction: MASShortcut]()) { dict, action in
            if let shortcut = shortcut(for: action) {
                dict[action] = shortcut
            }
        }
    }

    // For test injection via custom UserDefaults
    static func shortcutsByAction(actions: [WindowAction] = WindowAction.active, userDefaults: UserDefaults) -> [WindowAction: MASShortcut] {
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

/// Configures a `MASShortcutView` to read from and write to `ShortcutStore`.
///
/// All shortcut views in the app use this single function so that the
/// read/write path is consistent and changes in one place propagate everywhere.
///
/// - Parameters:
///   - view:     The shortcut view to configure.
///   - key:      The defaults key (action name or todo key) backing this view.
///   - fallback: The shortcut to display when the key is absent (first-run default).
///   - onChange: Called after every write, for callers that need to re-register a
///               system shortcut (e.g. `TodoManager`).
func configureShortcutView(
    _ view: MASShortcutView,
    key: String,
    fallback: MASShortcut?,
    onChange: (() -> Void)? = nil
) {
    view.shortcutValue = ShortcutStore.shortcut(forKey: key, fallback: fallback)
    view.shortcutValueChange = { sender in
        ShortcutStore.setShortcut(sender.shortcutValue, forKey: key)
        Notification.Name.shortcutsChanged.post()
        onChange?()
    }
}

extension MASShortcutView {
    func bind(to action: WindowAction) {
        configureShortcutView(self, key: action.name, fallback: ShortcutStore.defaultShortcut(for: action))
    }
    
    func bind(toTodoKey key: String, onChange: (() -> Void)? = nil) {
        configureShortcutView(self, key: key, fallback: nil, onChange: onChange)
    }
}


