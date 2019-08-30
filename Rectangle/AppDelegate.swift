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
    private let shortcutManager: ShortcutManager
    
    private let sparkleUpdater = SUUpdater()
    
    private var prefsWindowController: NSWindowController?
    
    @IBOutlet weak var mainStatusMenu: NSMenu!
    @IBOutlet weak var unauthorizedMenu: NSMenu!
    @IBOutlet weak var ignoreMenuItem: NSMenuItem!
    
    override init() {
        self.shortcutManager = ShortcutManager(applicationToggle: applicationToggle)
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
            ignoreMenuItem.title = "Ignore \(frontAppName)"
            ignoreMenuItem.state = applicationToggle.disabledForApp ? .on : .off
        } else {
            ignoreMenuItem.isHidden = true
        }
    }
    
}
