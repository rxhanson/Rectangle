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
    private let windowHistory = WindowHistory()
    
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
    @IBOutlet weak var todoModeMenuItem: NSMenuItem!
    @IBOutlet weak var todoAppMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if let lastVersion = Defaults.lastVersion.value,
           let intLastVersion = Int(lastVersion) {
            if intLastVersion < 46 {
                MASShortcutMigration.migrate()
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
        })
    }
    
    func checkAutoCheckForUpdates() {
        SUUpdater.shared()?.automaticallyChecksForUpdates = Defaults.SUEnableAutomaticChecks.enabled
    }
    
    func accessibilityTrusted() {
        self.windowCalculationFactory = WindowCalculationFactory()
        self.windowManager = WindowManager(windowHistory: windowHistory)
        self.shortcutManager = ShortcutManager(windowManager: windowManager)
        self.applicationToggle = ApplicationToggle(shortcutManager: shortcutManager)
        self.snappingManager = SnappingManager(windowHistory: windowHistory)
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
        prefsWindowController?.window?.makeKey()
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

    @IBAction func setTodoApp(_ sender: NSMenuItem) {
        applicationToggle.setTodoApp()
    }

    @IBAction func toggleTodoMode(_ sender: NSMenuItem) {
        if sender.state == .off {
            Defaults.todoMode.enabled = true
            windowManager.activateTodoMode()
        } else {
            Defaults.todoMode.enabled = false
        }
    }

    @IBAction func checkForUpdates(_ sender: Any) {
        SUUpdater.shared()?.checkForUpdates(sender)
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
            return
        }
        
        if let frontAppName = applicationToggle.frontAppName {
            let ignoreString = NSLocalizedString("D99-0O-MB6.title", tableName: "Main", value: "Ignore frontmost.app", comment: "")
            ignoreMenuItem.title = ignoreString.replacingOccurrences(
                of: "frontmost.app", with: frontAppName)
            ignoreMenuItem.state = applicationToggle.shortcutsDisabled ? .on : .off
            ignoreMenuItem.isHidden = false

            let appString = NSLocalizedString("2aA-39-aUi.title", tableName: "Main", value: "Use frontmost.app as Todo App", comment: "")
            todoAppMenuItem.title = appString.replacingOccurrences(
                of: "frontmost.app", with: frontAppName)
            todoAppMenuItem.isEnabled = !applicationToggle.todoAppIsActive()
            todoAppMenuItem.state = applicationToggle.todoAppIsActive() ? .on : .off
            todoAppMenuItem.isHidden = false
        } else {
            ignoreMenuItem.isHidden = true
            todoAppMenuItem.isHidden = true
        }
        
        todoModeMenuItem.state = Defaults.todoMode.enabled ? .on : .off

        updateWindowActionMenuItems(menu: menu)
        
        viewLoggingMenuItem.keyEquivalentModifierMask = .option
        quitMenuItem.keyEquivalent = "q"
        quitMenuItem.keyEquivalentModifierMask = .command
    }
    
    private func updateWindowActionMenuItems(menu: NSMenu) {
        let frontmostWindow = AccessibilityElement.frontmostWindow()
        let screenCount = NSScreen.screens.count

        for menuItem in menu.items {
            guard let windowAction = menuItem.representedObject as? WindowAction else { continue }

            menuItem.image = windowAction.image.copy() as? NSImage
            menuItem.image?.size = NSSize(width: 18, height: 12)

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
            if windowAction == .reflowTodo && Defaults.todoMode.enabled == false {
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
        windowAction.post()
    }
    
    func addWindowActionMenuItems() {
        var menuIndex = 0
        var categoryMenus: [CategoryMenu] = []
        for action in WindowAction.active {
            let newMenuItem = NSMenuItem(title: action.displayName, action: #selector(executeMenuWindowAction), keyEquivalent: "")
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
    }
    
    struct CategoryMenu {
        let menu: NSMenu
        let category: WindowActionCategory
    }
    
}

extension AppDelegate: NSWindowDelegate {
    
    func windowWillClose(_ notification: Notification) {
        NSApp.abortModal()
    }
    
}
