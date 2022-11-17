//
//  AppDelegate.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import Sparkle
import ServiceManagement
import os.log

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    static let launcherAppId = "com.knollsoft.RectangleLauncher"

    private let accessibilityAuthorization = AccessibilityAuthorization()
    private let statusItem = RectangleStatusItem.instance
    static let windowHistory = WindowHistory()
    static let updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)

    private var shortcutManager: ShortcutManager!
    private var windowManager: WindowManager!
    private var applicationToggle: ApplicationToggle!
    private var windowCalculationFactory: WindowCalculationFactory!
    private var snappingManager: SnappingManager!
    
    private var prefsWindowController: NSWindowController?
    
    @IBOutlet weak var mainStatusMenu: NSMenu!
    @IBOutlet weak var unauthorizedMenu: NSMenu!
    @IBOutlet weak var ignoreMenuItem: NSMenuItem!
    @IBOutlet weak var viewLoggingMenuItem: NSMenuItem!
    @IBOutlet weak var quitMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Defaults.loadFromSupportDir()
        if let lastVersion = Defaults.lastVersion.value,
           let intLastVersion = Int(lastVersion) {
            if intLastVersion < 46 {
                MASShortcutMigration.migrate()
            }
            if intLastVersion < 64 {
                SnapAreaModel.instance.migrate()
            }
        }
        
        Defaults.lastVersion.value = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        mainStatusMenu.delegate = self
        statusItem.refreshVisibility()
        checkLaunchOnLogin()
        
        let alreadyTrusted = accessibilityAuthorization.checkAccessibility {
            self.showWelcomeWindow()
            self.checkForConflictingApps()
            self.openPreferences(self)
            self.statusItem.statusMenu = self.mainStatusMenu
            self.accessibilityTrusted()
        }
        
        if alreadyTrusted {
            accessibilityTrusted()
        }
        
        statusItem.statusMenu = alreadyTrusted
            ? mainStatusMenu
            : unauthorizedMenu
        
        mainStatusMenu.autoenablesItems = false
        addWindowActionMenuItems()
 
        checkAutoCheckForUpdates()
        
        Notification.Name.configImported.onPost(using: { _ in
            self.checkAutoCheckForUpdates()
            self.statusItem.refreshVisibility()
            self.applicationToggle.reloadFromDefaults()
            self.shortcutManager.reloadFromDefaults()
            self.snappingManager.reloadFromDefaults()
            self.initializeTodo()
        })
        
        Notification.Name.todoMenuToggled.onPost(using: { _ in
            self.showHideTodoMenuItems()
            if Defaults.todo.userEnabled {
                TodoManager.registerReflowShortcut()
            }
        })
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        Notification.Name.appWillBecomeActive.post()
    }
    
    func checkAutoCheckForUpdates() {
        Self.updaterController.updater.automaticallyChecksForUpdates = Defaults.SUEnableAutomaticChecks.enabled
    }
    
    func accessibilityTrusted() {
        self.windowCalculationFactory = WindowCalculationFactory()
        self.windowManager = WindowManager()
        self.shortcutManager = ShortcutManager(windowManager: windowManager)
        self.applicationToggle = ApplicationToggle(shortcutManager: shortcutManager)
        self.snappingManager = SnappingManager(applicationToggle: applicationToggle)
        self.initializeTodo()
        checkForProblematicApps()
    }
    
    func checkForConflictingApps() {
        let conflictingAppsIds: [String: String] = [
            "com.divisiblebyzero.Spectacle": "Spectacle",
            "com.crowdcafe.windowmagnet": "Magnet",
            "com.hegenberg.BetterSnapTool": "BetterSnapTool",
            "com.manytricks.Moom": "Moom"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }
            if let conflictingAppName = conflictingAppsIds[bundleId] {
                AlertUtil.oneButtonAlert(question: "Potential window manager conflict: \(conflictingAppName)", text: "Since \(conflictingAppName) might have some overlapping behavior with Rectangle, it's recommended that you either disable or quit \(conflictingAppName).")
                break
            }
        }
        
    }
    
    /// certain applications have issues with the click listening done by the drag to snap feature
    func checkForProblematicApps() {
        guard !Defaults.windowSnapping.userDisabled, !Defaults.notifiedOfProblemApps.enabled else { return }
        
        let problemBundleIds: [String] = [
            "com.mathworks.matlab", "com.live2d.cubism.CECubismEditorApp", "com.aquafold.datastudio.DataStudio"
        ]
        
        // these apps are java based with dynamic bundleIds
        let problemJavaAppNames: [String] = [
            "thinkorswim",
            "Trader Workstation"
        ]

        var problemBundles: [Bundle] = problemBundleIds.compactMap { bundleId in
            if applicationToggle.isDisabled(bundleId: bundleId) { return nil }
            
            // Directly instantiating the Bundle from the bundle id didn't work for matlab for some reason
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return Bundle(url: url)
            }
            return nil
        }
        
        for name in problemJavaAppNames {
            if let path = NSWorkspace.shared.fullPath(forApplication: name) {
                if let bundle = Bundle(path: path),
                   let bundleId = bundle.bundleIdentifier {
                    
                    if !applicationToggle.isDisabled(bundleId: bundleId),
                       bundleId.starts(with: "com.install4j") {
                        problemBundles.append(bundle)
                    }
                }
            }
        }
        
        let displayNames = problemBundles.compactMap { $0.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String }
        let displayNameString = displayNames.joined(separator: "\n")
        
        if !problemBundles.isEmpty {
            AlertUtil.oneButtonAlert(question: "Known issues with installed applications", text: "\(displayNameString)\n\nThese applications have issues with the drag to screen edge to snap functionality in Rectangle.\n\nYou can either ignore the applications using the menu item in Rectangle, or disable drag to screen edge snapping in Rectangle preferences.")
            Defaults.notifiedOfProblemApps.enabled = true
        }
    }
    
    private func showWelcomeWindow() {
        let welcomeWindowController = NSStoryboard(name: "Main", bundle: nil)
            .instantiateController(withIdentifier: "WelcomeWindowController") as? NSWindowController
        guard let welcomeWindow = welcomeWindowController?.window else { return }
        welcomeWindow.delegate = self
        
        NSApp.activate(ignoringOtherApps: true)
        
        let response = NSApp.runModal(for: welcomeWindow)
        
        let usingRecommended = response == .alertFirstButtonReturn || response == .abort
        
        Defaults.alternateDefaultShortcuts.enabled = usingRecommended
        
        Defaults.subsequentExecutionMode.value = usingRecommended ? .acrossMonitor : .resize
        
        welcomeWindowController?.close()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Defaults.relaunchOpensMenu.enabled {
            statusItem.openMenu()
        } else {
            openPreferences(sender)
        }
        return true
    }
    
    @IBAction func openPreferences(_ sender: Any) {
        if prefsWindowController == nil {
            prefsWindowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "PrefsWindowController") as? NSWindowController
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindowController?.showWindow(self)
    }
    
    @IBAction func showAbout(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }
    
    @IBAction func viewLogging(_ sender: Any) {
        Logger.showLogging(sender: sender)
    }
    
    @IBAction func ignoreFrontMostApp(_ sender: NSMenuItem) {
        if sender.state == .on {
            applicationToggle.enableFrontApp()
        } else {
            applicationToggle.disableFrontApp()
        }
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        Self.updaterController.checkForUpdates(sender)
    }
    
    @IBAction func authorizeAccessibility(_ sender: Any) {
        accessibilityAuthorization.showAuthorizationWindow()
    }

    private func checkLaunchOnLogin() {
        let running = NSWorkspace.shared.runningApplications
        let isRunning = !running.filter({$0.bundleIdentifier == AppDelegate.launcherAppId}).isEmpty
        if isRunning {
            let killNotification = Notification.Name("killLauncher")
            DistributedNotificationCenter.default().post(name: killNotification, object: Bundle.main.bundleIdentifier!)
        }
        if !Defaults.SUHasLaunchedBefore {
            Defaults.launchOnLogin.enabled = true
        }
        
        // Even if we are already set up to launch on login, setting it again since macOS can be buggy with this type of launch on login.
        if Defaults.launchOnLogin.enabled {
            let smLoginSuccess = SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, true)
            if !smLoginSuccess {
                if #available(OSX 10.12, *) {
                    os_log("Unable to enable launch at login. Attempting one more time.", type: .info)
                }
                SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, true)
            }
        }
    }
    
}

extension AppDelegate: NSMenuDelegate {
    
    func menuWillOpen(_ menu: NSMenu) {
        if menu != mainStatusMenu {
            updateWindowActionMenuItems(menu: menu)
            updateTodoModeMenuItems(menu: menu)
            return
        }
        
        if let frontAppName = applicationToggle.frontAppName {
            let ignoreString = NSLocalizedString("D99-0O-MB6.title", tableName: "Main", value: "Ignore frontmost.app", comment: "")
            ignoreMenuItem.title = ignoreString.replacingOccurrences(of: "frontmost.app", with: frontAppName)
            ignoreMenuItem.state = applicationToggle.shortcutsDisabled ? .on : .off
            ignoreMenuItem.isHidden = false
        } else {
            ignoreMenuItem.isHidden = true
        }
        
        updateWindowActionMenuItems(menu: menu)
        updateTodoModeMenuItems(menu: menu)

        viewLoggingMenuItem.keyEquivalentModifierMask = .option
        quitMenuItem.keyEquivalent = "q"
        quitMenuItem.keyEquivalentModifierMask = .command
    }
    
    private func updateWindowActionMenuItems(menu: NSMenu) {
        let frontmostWindow = AccessibilityElement.getFrontWindowElement()
        let screenCount = NSScreen.screens.count
        let isPortrait = NSScreen.main?.frame.isLandscape == false

        for menuItem in menu.items {
            guard let windowAction = menuItem.representedObject as? WindowAction else { continue }

            menuItem.image = windowAction.image.copy() as? NSImage
            menuItem.image?.size = NSSize(width: 18, height: 12)
            
            if isPortrait && windowAction.classification == .thirds {
                menuItem.image = menuItem.image?.rotated(by: 270)
                menuItem.image?.isTemplate = true
            }

            if !applicationToggle.shortcutsDisabled {
                if let fullKeyEquivalent = shortcutManager.getKeyEquivalent(action: windowAction),
                    let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
                    menuItem.keyEquivalent = keyEquivalent
                    menuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
                }
            }
            if frontmostWindow == nil {
                menuItem.isEnabled = false
            }
            if screenCount == 1
                && (windowAction == .nextDisplay || windowAction == .previousDisplay) {
                menuItem.isEnabled = false
            }
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        for menuItem in menu.items {
            
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags()
            
            menuItem.isEnabled = true
        }
    }
    
    @objc func executeMenuWindowAction(sender: NSMenuItem) {
        guard let windowAction = sender.representedObject as? WindowAction else { return }
        windowAction.postMenu()
    }
    
    func addWindowActionMenuItems() {
        var menuIndex = 0
        var categoryMenus: [CategoryMenu] = []
        for action in WindowAction.active {
            guard let displayName = action.displayName else { continue }
            let newMenuItem = NSMenuItem(title: displayName, action: #selector(executeMenuWindowAction), keyEquivalent: "")
            newMenuItem.representedObject = action

            if !Defaults.showAllActionsInMenu.userEnabled, let category = action.category {
                if menuIndex != 0 && action.firstInGroup {
                    let menu = NSMenu(title: category.displayName)
                    menu.autoenablesItems = false
                    categoryMenus.append(CategoryMenu(menu: menu, category: category))
                }
                categoryMenus.last?.menu.addItem(newMenuItem)
                continue
            }
            
            if menuIndex != 0 && action.firstInGroup {
                mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
                menuIndex += 1
            }
            mainStatusMenu.insertItem(newMenuItem, at: menuIndex)
            menuIndex += 1
        }

        if !categoryMenus.isEmpty {
            mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
            menuIndex += 1
            
            for categoryMenu in categoryMenus {
                categoryMenu.menu.delegate = self
                let menuMenuItem = NSMenuItem(title: categoryMenu.category.displayName, action: nil, keyEquivalent: "")
                mainStatusMenu.insertItem(menuMenuItem, at: menuIndex)
                mainStatusMenu.setSubmenu(categoryMenu.menu, for: menuMenuItem)
                menuIndex += 1
            }
        }
        
        mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)

        menuIndex += 1
        addTodoModeMenuItems(startingIndex: menuIndex)
    }
    
    struct CategoryMenu {
        let menu: NSMenu
        let category: WindowActionCategory
    }
    
}

// todo mode
extension AppDelegate {
    func initializeTodo() {
        self.showHideTodoMenuItems()
        guard Defaults.todo.userEnabled else { return }
        TodoManager.registerReflowShortcut()
        if Defaults.todoMode.enabled {
            TodoManager.moveAll()
        }
    }

    enum TodoItem {
        case mode, app, reflow, separator

        var tag: Int {
            switch self {
            case .mode: return 101
            case .app: return 102
            case .reflow: return 103
            case .separator: return 104
            }
        }
        
        static let tags = [101, 102, 103, 104]
    }

    private func addTodoModeMenuItems(startingIndex: Int) {
        var menuIndex = startingIndex

        let todoModeItemTitle = NSLocalizedString("Enable Todo Mode", tableName: "Main", value: "", comment: "")
        let todoModeMenuItem = NSMenuItem(title: todoModeItemTitle, action: #selector(toggleTodoMode), keyEquivalent: "")
        todoModeMenuItem.tag = TodoItem.mode.tag
        mainStatusMenu.insertItem(todoModeMenuItem, at: menuIndex)
        menuIndex += 1

        let todoAppItemTitle = NSLocalizedString("Use frontmost.app as Todo App", tableName: "Main", value: "", comment: "")
        let todoAppMenuItem = NSMenuItem(title: todoAppItemTitle, action: #selector(setTodoApp), keyEquivalent: "")
        todoAppMenuItem.tag = TodoItem.app.tag
        mainStatusMenu.insertItem(todoAppMenuItem, at: menuIndex)
        menuIndex += 1

        let todoReflowItemTitle = NSLocalizedString("Reflow Todo", tableName: "Main", value: "", comment: "")
        let todoReflowItem = NSMenuItem(title: todoReflowItemTitle, action: #selector(todoReflow), keyEquivalent: "")
        todoReflowItem.tag = TodoItem.reflow.tag
        mainStatusMenu.insertItem(todoReflowItem, at: menuIndex)
        menuIndex += 1
        
        let separator = NSMenuItem.separator()
        separator.tag = TodoItem.separator.tag
        mainStatusMenu.insertItem(separator, at: menuIndex)
        
        showHideTodoMenuItems()
    }
    
    private func showHideTodoMenuItems() {
        for item in mainStatusMenu.items {
            if TodoItem.tags.contains(item.tag) {
                item.isHidden = !Defaults.todo.userEnabled
            }
        }
    }

    @objc func toggleTodoMode(_ sender: NSMenuItem) {
        if sender.state == .off {
            Defaults.todoMode.enabled = true
            TodoManager.moveAll()
        } else {
            Defaults.todoMode.enabled = false
        }
    }

    @objc func setTodoApp(_ sender: NSMenuItem) {
        applicationToggle.setTodoApp()
    }

    @objc func todoReflow(_ sender: NSMenuItem) {
        TodoManager.moveAll()
    }

    private func updateTodoModeMenuItems(menu: NSMenu) {
        guard Defaults.todo.userEnabled,
              let todoAppMenuItem = menu.item(withTag: TodoItem.app.tag),
              let todoModeMenuItem = menu.item(withTag: TodoItem.mode.tag),
              let todoReflowMenuItem = menu.item(withTag: TodoItem.reflow.tag)
        else {
            return
        }

        if let frontAppName = applicationToggle.frontAppName {
            let appString = NSLocalizedString("Use frontmost.app as Todo App", tableName: "Main", value: "", comment: "")
            todoAppMenuItem.title = appString.replacingOccurrences(
                of: "frontmost.app", with: frontAppName)
            todoAppMenuItem.isEnabled = !applicationToggle.todoAppIsActive()
            todoAppMenuItem.state = applicationToggle.todoAppIsActive() ? .on : .off
            todoAppMenuItem.isHidden = false
        } else {
            todoAppMenuItem.isHidden = true
        }

        todoModeMenuItem.state = Defaults.todoMode.enabled ? .on : .off

        if let fullKeyEquivalent = TodoManager.getReflowKeyDisplay(),
            let keyEquivalent = fullKeyEquivalent.0?.lowercased() {
            todoReflowMenuItem.keyEquivalent = keyEquivalent
            todoReflowMenuItem.keyEquivalentModifierMask = fullKeyEquivalent.1
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    
    func windowWillClose(_ notification: Notification) {
        NSApp.abortModal()
    }
    
}

extension AppDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { continue }
            if components.host == "execute-action" && components.path.isEmpty {
                guard let name = (components.queryItems?.first { $0.name == "name" })?.value else { continue }
                if let action = (WindowAction.active.first { urlName($0.name) == name }) { action.postUrl() }
            }
        }
    }
    
    private func urlName(_ name: String) -> String {
        return name.map { $0.isUppercase ? "-" + $0.lowercased() : String($0) }.joined()
    }
}
