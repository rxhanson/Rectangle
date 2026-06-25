/// TodoManager.swift

import Cocoa
import MASShortcut

class TodoManager {
    private static var todoWindowId: CGWindowID?
    private static let shortcutMonitor = MASShortcutMonitor.shared()!
    private static var registeredToggleShortcut: MASShortcut?
    private static var registeredReflowShortcut: MASShortcut?

    static var todoScreen: NSScreen?
    static let toggleDefaultsKey = "toggleTodo"
    static let reflowDefaultsKey = "reflowTodo"
    static let defaultsKeys = [toggleDefaultsKey, reflowDefaultsKey]

    static func setTodoMode(_ enabled: Bool, _ bringToFront: Bool = true) {
        Defaults.todoMode.enabled = enabled
        registerUnregisterReflowShortcut()
        moveAllIfNeeded(bringToFront)
    }

    // MARK: Shortcut initialisation

    static func initToggleShortcut() {
        // Write the default only when the key is genuinely absent so that an
        // explicit user clearance (sentinel string) is not overwritten.
        if ShortcutStore.shortcut(forKey: toggleDefaultsKey) == nil,
           PreferencesStore.shared.string(forKey: toggleDefaultsKey) == nil {
            ShortcutStore.setShortcut(defaultToggleShortcut(), forKey: toggleDefaultsKey)
        }
    }

    static func initReflowShortcut() {
        if ShortcutStore.shortcut(forKey: reflowDefaultsKey) == nil,
           PreferencesStore.shared.string(forKey: reflowDefaultsKey) == nil {
            ShortcutStore.setShortcut(defaultReflowShortcut(), forKey: reflowDefaultsKey)
        }
    }

    // MARK: Registration

    private static func bindTodoShortcut(key: String,
                                         fallback: MASShortcut,
                                         registered: inout MASShortcut?,
                                         enabled: Bool,
                                         action: @escaping () -> Void) {
        if let current = registered {
            shortcutMonitor.unregisterShortcut(current)
            registered = nil
        }
        
        guard enabled,
              isTodoShortcutBindable(key),
              let shortcut = ShortcutStore.shortcut(forKey: key, fallback: fallback)
        else { return }
        
        if shortcutMonitor.register(shortcut, withAction: action) {
            registered = shortcut
        }
    }

    static func registerUnregisterToggleShortcut() {
        bindTodoShortcut(
            key: toggleDefaultsKey,
            fallback: defaultToggleShortcut(),
            registered: &registeredToggleShortcut,
            enabled: Defaults.todo.userEnabled
        ) {
            setTodoMode(!Defaults.todoMode.enabled)
        }
    }

    static func registerUnregisterReflowShortcut() {
        bindTodoShortcut(
            key: reflowDefaultsKey,
            fallback: defaultReflowShortcut(),
            registered: &registeredReflowShortcut,
            enabled: Defaults.todo.userEnabled && Defaults.todoMode.enabled
        ) {
            moveAll()
        }
    }

    // MARK: Conflict detection

    private static func isTodoShortcutBindable(_ defaultsKey: String) -> Bool {
        guard let shortcut = ShortcutStore.shortcut(forKey: defaultsKey) else { return true }
        return TodoShortcutConflict.conflict(for: shortcut, ignoringTodoDefaultsKey: defaultsKey) == nil
    }

    // MARK: Key display (for menu item labels)

    static func toggleKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let shortcut = ShortcutStore.shortcut(forKey: toggleDefaultsKey,
                                                    fallback: defaultToggleShortcut()) else { return nil }
        return (shortcut.keyCodeStringForKeyEquivalent, shortcut.modifierFlags)
    }

    static func reflowKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let shortcut = ShortcutStore.shortcut(forKey: reflowDefaultsKey,
                                                    fallback: defaultReflowShortcut()) else { return nil }
        return (shortcut.keyCodeStringForKeyEquivalent, shortcut.modifierFlags)
    }

    // MARK: Defaults

    private static func defaultToggleShortcut() -> MASShortcut {
        MASShortcut(keyCode: kVK_ANSI_B, modifierFlags: [.control, .option])
    }

    private static func defaultReflowShortcut() -> MASShortcut {
        MASShortcut(keyCode: kVK_ANSI_N, modifierFlags: [.control, .option])
    }

    // MARK: Window management

    private static func getTodoWindowElement() -> AccessibilityElement? {
        guard let bundleId = Defaults.todoApplication.value, let windowElements = AccessibilityElement(bundleId)?.windowElements else {
            todoWindowId = nil
            return nil
        }
        if let windowId = todoWindowId, !(windowElements.contains { $0.windowId == windowId }) {
            todoWindowId = nil
        }
        if todoWindowId == nil {
            todoWindowId = windowElements.first?.windowId
        }
        if let windowId = todoWindowId, let windowElement = (windowElements.first { $0.windowId == windowId }) {
            return windowElement
        }
        todoWindowId = nil
        return nil
    }

    static func hasTodoWindow() -> Bool {
        getTodoWindowElement() != nil
    }

    static func isTodoWindowFront() -> Bool {
        guard let windowElement = AccessibilityElement.getFrontWindowElement() else { return false }
        return isTodoWindow(windowElement)
    }

    static func isTodoWindow(_ windowElement: AccessibilityElement) -> Bool {
        guard let windowId = windowElement.windowId else { return false }
        return isTodoWindow(windowId)
    }

    static func isTodoWindow(_ windowId: CGWindowID) -> Bool {
        getTodoWindowElement()?.windowId == windowId
    }

    static func resetTodoWindow() {
        todoWindowId = nil
        // Re-probe the window list so todoWindowId is repopulated with the
        // first available window for the configured todo app.
        _ = getTodoWindowElement()
    }

    static func moveAll(_ bringToFront: Bool = true) {
        refreshTodoScreen()

        let pid = ProcessInfo.processInfo.processIdentifier
        // Exclude the footprint window (which runs in-process).
        let windows = AccessibilityElement.getAllWindowElements().filter { $0.pid != pid }

        if let todoWindow = getTodoWindowElement() {
            if let screen = todoScreen {
                let sd = ScreenDetection()
                var adjustedVisibleFrame = screen.adjustedVisibleFrame()
                // Clear all windows from the todo app sidebar area.
                for w in windows {
                    let wScreen = sd.detectScreens(using: w)?.currentScreen
                    if w.getWindowId() != todoWindow.getWindowId() &&
                        wScreen == todoScreen {
                        shiftWindowOffSidebar(w, screenVisibleFrame: adjustedVisibleFrame)
                    }
                }

                adjustedVisibleFrame = screen.adjustedVisibleFrame(true)
                let sidebarWidth = getSidebarWidth(visibleFrameWidth: adjustedVisibleFrame.width)

                let isRightSide = Defaults.todoSidebarSide.value == .right
                let sharedEdge: Edge = isRightSide ? .left : .right
                var rect = adjustedVisibleFrame

                if isRightSide {
                    rect.origin.x = adjustedVisibleFrame.maxX - sidebarWidth
                }
                rect.size.width = sidebarWidth
                rect = rect.screenFlipped

                if Defaults.gapSize.value > 0 {
                    rect = GapCalculation.applyGaps(rect, sharedEdges: sharedEdge, gapSize: Defaults.gapSize.value)
                }
                todoWindow.setFrame(rect)
            }

            if bringToFront {
                todoWindow.bringToFront()
            }
        }
    }

    static func getSidebarWidth(visibleFrameWidth: CGFloat) -> CGFloat {
        var sidebarWidth = Defaults.todoSidebarWidth.cgFloat

        if sidebarWidth > 0 && sidebarWidth <= 1 {
            sidebarWidth = sidebarWidth * visibleFrameWidth
        } else if Defaults.todoSidebarWidthUnit.value == .pct {
            sidebarWidth = convert(width: sidebarWidth, toUnit: .pixels, visibleFrameWidth: visibleFrameWidth)
        }

        return sidebarWidth
    }

    static func changeSidebarWidthUnit(to unit: TodoSidebarWidthUnit) {
        if let visibleFrameWidth = todoScreen?.adjustedVisibleFrame(true).width {
            let newValue = TodoManager.convert(width: Defaults.todoSidebarWidth.cgFloat, toUnit: unit, visibleFrameWidth: visibleFrameWidth)
            Defaults.todoSidebarWidth.value = Float(newValue)
        }
    }

    static func convert(width: CGFloat, toUnit unit: TodoSidebarWidthUnit, visibleFrameWidth: CGFloat) -> CGFloat {
        unit == .pixels
        ? ((width * 0.01) * visibleFrameWidth).rounded()
        : ((width / visibleFrameWidth) * 100).rounded()
    }

    static func moveAllIfNeeded(_ bringToFront: Bool = true) {
        guard Defaults.todo.userEnabled && Defaults.todoMode.enabled else { return }
        moveAll(bringToFront)
    }

    static func refreshTodoScreen() {
        let todoWindow = getTodoWindowElement()
        let screens = ScreenDetection().detectScreens(using: todoWindow)
        todoScreen = screens?.currentScreen
    }

    private static func shiftWindowOffSidebar(_ w: AccessibilityElement, screenVisibleFrame: CGRect) {
        var rect = w.frame
        let halfGapWidth = CGFloat(Defaults.gapSize.value) / 2
        let screenVisibleFrameMinX = screenVisibleFrame.minX + halfGapWidth
        let screenVisibleFrameMaxX = screenVisibleFrame.maxX - halfGapWidth

        if Defaults.todoSidebarSide.value == .left && rect.minX < screenVisibleFrameMinX {
            // Shift it to the right
            rect.origin.x = min(screenVisibleFrameMaxX - rect.width, screenVisibleFrameMinX)

            // If it's still too wide, scale it down
            if rect.minX < screenVisibleFrameMinX {
                let widthDiff = screenVisibleFrameMinX - rect.minX
                rect.origin.x += widthDiff
                rect.size.width -= widthDiff
            }

            w.setFrame(rect)
        } else if Defaults.todoSidebarSide.value == .right && rect.maxX > screenVisibleFrameMaxX {
            // Shift it to the left
            rect.origin.x = min(rect.minX, max(screenVisibleFrameMinX, screenVisibleFrameMaxX - rect.width))

            // If it's still too wide, scale it down
            if rect.maxX > screenVisibleFrameMaxX {
                rect.size.width -= rect.maxX - screenVisibleFrameMaxX
            }

            w.setFrame(rect)
        }
    }

    static func execute(parameters: ExecutionParameters) -> Bool {
        if [.leftTodo, .rightTodo].contains(parameters.action) {
            moveAll()
            return true
        }
        return false
    }
}

// MARK: - TodoShortcutConflict

struct TodoShortcutConflict {

    let shortcutName: String

    /// Checks whether `shortcut` conflicts with any existing window-action or
    /// todo shortcut, ignoring `ignoredDefaultsKey`.
    ///
    /// Pass `userDefaults` only in tests; the live path uses `ShortcutStore`.
    static func conflict(for shortcut: MASShortcut,
                         ignoringTodoDefaultsKey ignoredDefaultsKey: String,
                         userDefaults: UserDefaults? = nil) -> TodoShortcutConflict? {
        let identity = ShortcutCycle.ShortcutIdentity(shortcut)

        for action in WindowAction.active {
            let actionShortcut = userDefaults.map { ShortcutCycle.shortcut(for: action, userDefaults: $0) }
                               ?? ShortcutCycle.shortcut(for: action)
            guard let actionShortcut, ShortcutCycle.ShortcutIdentity(actionShortcut) == identity
            else { continue }
            return TodoShortcutConflict(shortcutName: action.displayName ?? action.name)
        }

        for defaultsKey in TodoManager.defaultsKeys where defaultsKey != ignoredDefaultsKey {
            let todoShortcut = userDefaults.map { ShortcutCycle.shortcut(forDefaultsKey: defaultsKey, userDefaults: $0) }
                             ?? ShortcutCycle.shortcut(forDefaultsKey: defaultsKey)
            guard let todoShortcut, ShortcutCycle.ShortcutIdentity(todoShortcut) == identity
            else { continue }
            return TodoShortcutConflict(shortcutName: displayName(forTodoDefaultsKey: defaultsKey))
        }

        return nil
    }

    private static func displayName(forTodoDefaultsKey defaultsKey: String) -> String {
        switch defaultsKey {
        case TodoManager.toggleDefaultsKey:
            return NSLocalizedString("Toggle Todo", tableName: "Main", value: "Toggle Todo", comment: "")
        case TodoManager.reflowDefaultsKey:
            return NSLocalizedString("Reflow Todo", tableName: "Main", value: "Reflow Todo", comment: "")
        default:
            return defaultsKey
        }
    }
}

// MARK: - TodoShortcutValidator

class TodoShortcutValidator: MASShortcutValidator {

    private let defaultsKey: String
    private let userDefaults: UserDefaults?

    init(defaultsKey: String, userDefaults: UserDefaults? = nil) {
        self.defaultsKey = defaultsKey
        self.userDefaults = userDefaults
        super.init()
    }

    override func isShortcutValid(_ shortcut: MASShortcut!) -> Bool {
        guard super.isShortcutValid(shortcut) else { return false }

        // Preserve previous behavior by rejecting Rectangle-internal conflicts quietly,
        // without routing them through MASShortcut's "already used" alert.
        return TodoShortcutConflict.conflict(for: shortcut,
                                             ignoringTodoDefaultsKey: defaultsKey,
                                             userDefaults: userDefaults) == nil
    }

    override func isShortcutAlreadyTaken(bySystem shortcut: MASShortcut!,
                                         explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        return super.isShortcutAlreadyTaken(bySystem: shortcut, explanation: explanation)
    }
}

// MARK: - Enums

enum TodoSidebarSide: Int {
    case right = 1
    case left = 2
}

enum TodoSidebarWidthUnit: Int, CustomStringConvertible {
    case pixels = 1
    case pct = 2

    var description: String {
        switch self {
        case .pixels: return "px"
        case .pct:    return "%"
        }
    }
}
