/// TodoManager.swift

import Cocoa
import MASShortcut

class TodoManager {
    private static var todoWindowId: CGWindowID?
    private static var shortcutBindingsSessionActive = true

    static var todoScreen : NSScreen?
    static let toggleDefaultsKey = "toggleTodo"
    static let reflowDefaultsKey = "reflowTodo"
    static let defaultsKeys = [toggleDefaultsKey, reflowDefaultsKey]
    private static var shortcutBindingsSuspended = false
    
    static func setTodoMode(_ enabled: Bool, _ bringToFront: Bool = true) {
        Defaults.todoMode.enabled = enabled
        registerUnregisterReflowShortcut()
        moveAllIfNeeded(bringToFront)
    }

    static func initToggleShortcut() {
        if UserDefaults.standard.dictionary(forKey: toggleDefaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let toggleShortcut = MASShortcut(keyCode: kVK_ANSI_B,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let toggleShortcutDict = dictTransformer.reverseTransformedValue(toggleShortcut)
            UserDefaults.standard.set(toggleShortcutDict, forKey: toggleDefaultsKey)
        }
    }
    
    static func initReflowShortcut() {
        if UserDefaults.standard.dictionary(forKey: reflowDefaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let reflowShortcut = MASShortcut(keyCode: kVK_ANSI_N,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let reflowShortcutDict = dictTransformer.reverseTransformedValue(reflowShortcut)
            UserDefaults.standard.set(reflowShortcutDict, forKey: reflowDefaultsKey)
        }
    }
    
    private static func registerToggleShortcut() {
        guard isTodoShortcutBindable(toggleDefaultsKey) else {
            unregisterToggleShortcut()
            return
        }

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: toggleDefaultsKey, toAction: {
            let enabled = !Defaults.todoMode.enabled
            setTodoMode(enabled)
        })
    }
    
    private static func registerReflowShortcut() {
        guard isTodoShortcutBindable(reflowDefaultsKey) else {
            unregisterReflowShortcut()
            return
        }

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: reflowDefaultsKey, toAction: {
            moveAll()
        })
    }
    
    private static func unregisterToggleShortcut() {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: toggleDefaultsKey)
    }
    
    private static func unregisterReflowShortcut() {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: reflowDefaultsKey)
    }
    
    static func registerUnregisterToggleShortcut() {
        if Defaults.todo.userEnabled && shortcutBindingsSessionActive && !shortcutBindingsSuspended {
            registerToggleShortcut()
        } else {
            unregisterToggleShortcut()
        }
    }
    
    static func registerUnregisterReflowShortcut() {
        if Defaults.todo.userEnabled && Defaults.todoMode.enabled && shortcutBindingsSessionActive && !shortcutBindingsSuspended {
            registerReflowShortcut()
        } else {
            unregisterReflowShortcut()
        }
    }

    static func setShortcutBindingsSessionActive(_ isActive: Bool) {
        guard shortcutBindingsSessionActive != isActive else { return }

        shortcutBindingsSessionActive = isActive
        unregisterToggleShortcut()
        unregisterReflowShortcut()

        if isActive {
            registerUnregisterToggleShortcut()
            registerUnregisterReflowShortcut()
        }
    }

    static func setShortcutBindingsSuspended(_ suspended: Bool) {
        guard shortcutBindingsSuspended != suspended else { return }
        shortcutBindingsSuspended = suspended
        registerUnregisterToggleShortcut()
        registerUnregisterReflowShortcut()
    }

    private static func isTodoShortcutBindable(_ defaultsKey: String) -> Bool {
        guard let shortcut = shortcut(for: defaultsKey) else { return true }
        return AppShortcutConflict.conflict(for: shortcut, ignoringDefaultsKey: defaultsKey) == nil
    }

    private static func shortcut(for defaultsKey: String, userDefaults: UserDefaults = .standard) -> MASShortcut? {
        guard
            let shortcutDict = userDefaults.dictionary(forKey: defaultsKey),
            let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)),
            let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
        else {
            return nil
        }
        return shortcut
    }

    static func getToggleKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let shortcut = shortcut(for: toggleDefaultsKey) else { return nil }
        return (shortcut.keyCodeStringForKeyEquivalent, shortcut.modifierFlags)
    }
    
    static func getReflowKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let shortcut = shortcut(for: reflowDefaultsKey) else { return nil }
        return (shortcut.keyCodeStringForKeyEquivalent, shortcut.modifierFlags)
    }
    
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
    
    static func isTodoWindowFront() -> Bool {
        guard let windowElement = AccessibilityElement.getFrontWindowElement() else { return false }
        return isTodoWindow(windowElement)
    }
    
    static func isTodoWindow(_ windowElement: AccessibilityElement) -> Bool {
        guard let windowId = windowElement.windowId else { return false }
        return isTodoWindow(windowId)
    }
    
    static func isTodoWindow(_ windowId: CGWindowID) -> Bool {
        return getTodoWindowElement()?.windowId == windowId
    }

    private static func sidebarLayout(visibleFrame: CGRect) -> (workArea: CGRect, windowFrame: CGRect, width: CGFloat) {
        let sidebarWidth = getSidebarWidth(visibleFrameWidth: visibleFrame.width)
        let isRightSide = Defaults.todoSidebarSide.value == .right

        let workArea = workAreaForPinnedSidebar(visibleFrame: visibleFrame,
                                                sidebarWidth: sidebarWidth,
                                                isRightSide: isRightSide)

        var windowFrame = visibleFrame
        windowFrame.size.width = sidebarWidth
        if isRightSide {
            windowFrame.origin.x = visibleFrame.maxX - sidebarWidth
        }
        windowFrame = windowFrame.screenFlipped
        if Defaults.gapSize.value > 0 {
            windowFrame = GapCalculation.applyGaps(windowFrame,
                                                    sharedEdges: isRightSide ? .left : .right,
                                                    gapSize: Defaults.gapSize.value)
        }
        return (workArea, windowFrame, sidebarWidth)
    }

    static func workAreaForPinnedSidebar(visibleFrame: CGRect, sidebarWidth: CGFloat, isRightSide: Bool) -> CGRect {
        var workArea = visibleFrame
        workArea.size.width -= sidebarWidth
        if !isRightSide {
            workArea.origin.x += sidebarWidth
        }
        return workArea
    }

    static func isPinnedSidebarFrame(_ actual: CGRect, expected: CGRect, backingScale: CGFloat) -> Bool {
        let tolerance = 1 / max(1, backingScale)
        return !actual.isNull
            && abs(actual.minX - expected.minX) <= tolerance
            && abs(actual.minY - expected.minY) <= tolerance
            && abs(actual.maxX - expected.maxX) <= tolerance
            && abs(actual.maxY - expected.maxY) <= tolerance
    }

    static func pinnedSidebarWidth(on screen: NSScreen, visibleFrame: CGRect) -> CGFloat? {
        guard let todoWindow = getTodoWindowElement(),
              todoWindow.isMinimized != true,
              todoWindow.isHidden != true,
              let windowId = todoWindow.windowId else { return nil }
        let layout = sidebarLayout(visibleFrame: visibleFrame)
        guard isPinnedSidebarFrame(todoWindow.frame,
                                   expected: layout.windowFrame,
                                   backingScale: screen.backingScaleFactor) else { return nil }
        return WindowUtil.getWindowList(forceRefresh: true).contains { $0.id == windowId }
            ? layout.width : nil
    }
    
    static func resetTodoWindow() {
        todoWindowId = nil
        _ = getTodoWindowElement()
    }
    
    static func moveAll(_ bringToFront: Bool = true) {
        TodoManager.refreshTodoScreen()

        let pid = ProcessInfo.processInfo.processIdentifier
        // Avoid footprint window
        let windows = AccessibilityElement.getAllWindowElements().filter { $0.pid != pid }

        if let todoWindow = getTodoWindowElement() {
            if let screen = TodoManager.todoScreen {
                let sd = ScreenDetection()
                let layout = sidebarLayout(visibleFrame: screen.adjustedVisibleFrame(true))
                // Clear all windows from the todo app sidebar
                for w in windows {
                    let wScreen = sd.detectScreens(using: w)?.currentScreen
                    if w.getWindowId() != todoWindow.getWindowId() &&
                        wScreen == TodoManager.todoScreen {
                        shiftWindowOffSidebar(w, screenVisibleFrame: layout.workArea)
                    }
                }
                todoWindow.setFrame(layout.windowFrame)
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
        if let visibleFrameWidth = TodoManager.todoScreen?.adjustedVisibleFrame(true).width {
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
        TodoManager.todoScreen = screens?.currentScreen
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

struct AppShortcutConflict {

    let shortcutName: String

    static func conflict(for shortcut: MASShortcut,
                         ignoringDefaultsKey ignoredDefaultsKey: String,
                         userDefaults: UserDefaults = .standard) -> AppShortcutConflict? {
        let identity = ShortcutCycle.ShortcutIdentity(shortcut)

        for action in WindowAction.active {
            guard let actionShortcut = ShortcutCycle.shortcut(for: action, userDefaults: userDefaults),
                  ShortcutCycle.ShortcutIdentity(actionShortcut) == identity
            else { continue }

            return AppShortcutConflict(shortcutName: action.displayName ?? action.name)
        }

        let appShortcutDefaultsKeys = TodoManager.defaultsKeys + StackBadgeManager.defaultsKeys
        for defaultsKey in appShortcutDefaultsKeys where defaultsKey != ignoredDefaultsKey {
            guard let appShortcut = ShortcutCycle.shortcut(forDefaultsKey: defaultsKey, userDefaults: userDefaults),
                  ShortcutCycle.ShortcutIdentity(appShortcut) == identity
            else { continue }

            return AppShortcutConflict(shortcutName: displayName(forDefaultsKey: defaultsKey))
        }

        return nil
    }

    private static func displayName(forDefaultsKey defaultsKey: String) -> String {
        switch defaultsKey {
        case TodoManager.toggleDefaultsKey:
            return NSLocalizedString("Toggle Todo", tableName: "Main", value: "Toggle Todo", comment: "")
        case TodoManager.reflowDefaultsKey:
            return NSLocalizedString("Reflow Todo", tableName: "Main", value: "Reflow Todo", comment: "")
        case StackBadgeManager.toggleDefaultsKey:
            return NSLocalizedString("Toggle stacked window badge", tableName: "Main", value: "Toggle stacked window badge", comment: "")
        default:
            return defaultsKey
        }
    }
}

class AppShortcutValidator: MASShortcutValidator {

    private let defaultsKey: String
    private let userDefaults: UserDefaults

    init(defaultsKey: String, userDefaults: UserDefaults = .standard) {
        self.defaultsKey = defaultsKey
        self.userDefaults = userDefaults
        super.init()
    }

    override func isShortcutValid(_ shortcut: MASShortcut!) -> Bool {
        guard super.isShortcutValid(shortcut) else { return false }

        // Preserve previous behavior by rejecting Rectangle-internal conflicts quietly,
        // without routing them through MASShortcut's "already used" alert.
        return AppShortcutConflict.conflict(for: shortcut,
                                            ignoringDefaultsKey: defaultsKey,
                                            userDefaults: userDefaults) == nil
    }

    override func isShortcutAlreadyTaken(bySystem shortcut: MASShortcut!,
                                         explanation: AutoreleasingUnsafeMutablePointer<NSString?>!) -> Bool {
        return super.isShortcutAlreadyTaken(bySystem: shortcut, explanation: explanation)
    }
}

typealias TodoShortcutConflict = AppShortcutConflict
typealias TodoShortcutValidator = AppShortcutValidator

enum TodoSidebarSide: Int {
    case right = 1
    case left = 2
}

enum TodoSidebarWidthUnit: Int, CustomStringConvertible {
    case pixels = 1
    case pct = 2
    
    var description: String {
        switch self {
        case .pixels:
            return "px"
        case .pct:
            return "%"
        }
    }
}
