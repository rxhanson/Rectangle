//
//  AppDelegate.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/11/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import Sparkle

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    static let launcherAppId = "com.knollsoft.RectangleLauncher"

    private let accessibilityAuthorization = AccessibilityAuthorization()
    private let statusItem = RectangleStatusItem.instance
    private let applicationToggle = ApplicationToggle()
    private let windowHistory = WindowHistory()
    
    private let shortcutManager: ShortcutManager
    private let windowManager: WindowManager
    private let windowCalculationFactory: WindowCalculationFactory
    private let snappingManager: SnappingManager
    
    private let sparkleUpdater = SUUpdater()
    
    private var prefsWindowController: NSWindowController?
    
    @IBOutlet weak var mainStatusMenu: NSMenu!
    @IBOutlet weak var unauthorizedMenu: NSMenu!
    @IBOutlet weak var ignoreMenuItem: NSMenuItem!
    
    override init() {
        self.windowCalculationFactory = WindowCalculationFactory()
        self.windowManager = WindowManager(windowCalculationFactory: windowCalculationFactory, windowHistory: windowHistory)
        self.shortcutManager = ShortcutManager(applicationToggle: applicationToggle, windowManager: windowManager)
        self.snappingManager = SnappingManager(windowCalculationFactory: windowCalculationFactory, windowHistory: windowHistory)
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        mainStatusMenu.delegate = self
        statusItem.refreshVisibility()
        checkLaunchOnLogin()
        
        let alreadyTrusted = accessibilityAuthorization.checkAccessibility {
            self.openPreferences(self)
            self.statusItem.statusMenu = self.mainStatusMenu
        }
        
        statusItem.statusMenu = alreadyTrusted
            ? mainStatusMenu
            : unauthorizedMenu
        
        addWindowActionMenuItems()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.openMenu()
        print(ProcessInfo.processInfo.arguments)
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
    
    @IBAction func ignoreFrontMostApp(_ sender: NSMenuItem) {
        if sender.state == .on {
            applicationToggle.enableFrontApp()
        } else {
            applicationToggle.disableFrontApp()
        }
    }
    
    @IBAction func checkForUpdates(_ sender: Any) {
        self.sparkleUpdater.checkForUpdates(sender)
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
    }
    
}

extension AppDelegate: NSMenuDelegate {
    
    func menuWillOpen(_ menu: NSMenu) {
        if let frontAppName = applicationToggle.frontAppName {
            let ignoreString = NSLocalizedString("D99-0O-MB6.title", tableName: "Main", value: "Ignore \"App\"", comment: "")
            ignoreMenuItem.title = ignoreString.replacingOccurrences(of: "App", with: frontAppName)
            ignoreMenuItem.state = applicationToggle.disabledForApp ? .on : .off
        } else {
            ignoreMenuItem.isHidden = true
        }
        
        for menuItem in menu.items {
            guard let windowAction = menuItem.representedObject as? WindowAction else { continue }
            if let fullKeyEquivalent = shortcutManager.getKeyEquivalent(action: windowAction) {
                menuItem.keyEquivalent = fullKeyEquivalent.0.lowercased()
                menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: fullKeyEquivalent.1)
            }
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        for menuItem in menu.items {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags()
        }
    }
    
    func addWindowActionMenuItems() {
        var menuIndex = 0
        for action in WindowAction.active {
            if menuIndex != 0 && action.firstInGroup {
                mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
                menuIndex += 1
            }
            
            let newMenuItem = NSMenuItem(title: action.displayName, action: #selector(executeMenuWindowAction), keyEquivalent: "")
            newMenuItem.representedObject = action
            mainStatusMenu.insertItem(newMenuItem, at: menuIndex)
            menuIndex += 1
        }
        mainStatusMenu.insertItem(NSMenuItem.separator(), at: menuIndex)
    }
    
    @objc func executeMenuWindowAction(sender: NSMenuItem) {
        guard let windowAction = sender.representedObject as? WindowAction else { return }
        windowAction.post()
    }
    
}
