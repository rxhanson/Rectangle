//
//  PrefsViewController.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/18/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa
import MASShortcut
import ServiceManagement

class PrefsViewController: NSViewController {
    
    var actionsToViews = [WindowAction: MASShortcutView]()
    lazy var messagePopover = MessagePopover()
    
    @IBOutlet weak var leftHalfShortcutView: MASShortcutView!
    @IBOutlet weak var rightHalfShortcutView: MASShortcutView!
    @IBOutlet weak var topHalfShortcutView: MASShortcutView!
    @IBOutlet weak var bottomHalfShortcutView: MASShortcutView!
    
    @IBOutlet weak var topLeftShortcutView: MASShortcutView!
    @IBOutlet weak var topRightShortcutView: MASShortcutView!
    @IBOutlet weak var bottomLeftShortcutView: MASShortcutView!
    @IBOutlet weak var bottomRightShortcutView: MASShortcutView!
    
    @IBOutlet weak var nextDisplayShortcutView: MASShortcutView!
    @IBOutlet weak var previousDisplayShortcutView: MASShortcutView!
    
    @IBOutlet weak var maximizeShortcutView: MASShortcutView!
    @IBOutlet weak var maximizeHeightShortcutView: MASShortcutView!
    @IBOutlet weak var centerShortcutView: MASShortcutView!
    
    @IBOutlet weak var makeLargerShortcutView: MASShortcutView!
    @IBOutlet weak var makeSmallerShortcutView: MASShortcutView!
    
    @IBOutlet weak var launchOnLoginCheckbox: NSButton!
    @IBOutlet weak var hideMenuBarIconCheckbox: NSButton!

    @IBAction func toggleLaunchOnLogin(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        SMLoginItemSetEnabled(AppDelegate.launcherAppId as CFString, newSetting)
        Defaults.launchOnLogin.enabled = newSetting
    }
    
    @IBAction func toggleHideMenuBarIcon(_ sender: NSButton) {
        let newSetting: Bool = sender.state == .on
        Defaults.hideMenuBarIcon.enabled = newSetting
        RectangleStatusItem.instance.refreshVisibility()
    }

    @IBAction func showInfoForHideMenuBarIcon(_ sender: NSButton) {
        messagePopover.show(message: "When the menu bar icon is hidden, relaunch Rectangle from Finder to open the menu.", sender: sender)
    }
    
    @IBAction func restoreDefaults(_ sender: Any) {
        WindowAction.active.forEach { UserDefaults.standard.removeObject(forKey: $0.name) }
    }
    
    override func awakeFromNib() {
        if Defaults.launchOnLogin.enabled {
            launchOnLoginCheckbox.state = .on
        }
        
        if Defaults.hideMenuBarIcon.enabled {
            hideMenuBarIconCheckbox.state = .on
        }
        
        actionsToViews = [
            .leftHalf: leftHalfShortcutView,
            .rightHalf: rightHalfShortcutView,
            .topHalf: topHalfShortcutView,
            .bottomHalf: bottomHalfShortcutView,
            .upperLeft: topLeftShortcutView,
            .upperRight: topRightShortcutView,
            .lowerLeft: bottomLeftShortcutView,
            .lowerRight: bottomRightShortcutView,
            .nextDisplay: nextDisplayShortcutView,
            .previousDisplay: previousDisplayShortcutView,
            .maximize: maximizeShortcutView,
            .maximizeHeight: maximizeHeightShortcutView,
            .center: centerShortcutView,
            .larger: makeLargerShortcutView,
            .smaller: makeSmallerShortcutView
        ]
        
        for (action, view) in actionsToViews {
            view.associatedUserDefaultsKey = action.name
        }
    }
}
