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
    
    // Basic
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
    
    @IBOutlet weak var makeLargerShortcutView: MASShortcutView!
    @IBOutlet weak var makeSmallerShortcutView: MASShortcutView!
    
    @IBOutlet weak var maximizeShortcutView: MASShortcutView!
    @IBOutlet weak var maximizeHeightShortcutView: MASShortcutView!
    @IBOutlet weak var centerShortcutView: MASShortcutView!
    @IBOutlet weak var restoreShortcutView: MASShortcutView!
    
    // Additional
    @IBOutlet weak var leftThirdShortcutView: MASShortcutView!
    @IBOutlet weak var leftTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var horizCenterThirdShortcutView: MASShortcutView!
    @IBOutlet weak var rightTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var rightThirdShortcutView: MASShortcutView!
    
    @IBOutlet weak var topThirdShortcutView: MASShortcutView!
    @IBOutlet weak var topTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var vertCenterThirdShortcutView: MASShortcutView!
    @IBOutlet weak var bottomTwoThirdsShortcutView: MASShortcutView!
    @IBOutlet weak var bottomThirdShortcutView: MASShortcutView!
    
    @IBOutlet weak var moveLeftShortcutView: MASShortcutView!
    @IBOutlet weak var moveRightShortcutView: MASShortcutView!
    @IBOutlet weak var moveUpShortcutView: MASShortcutView!
    @IBOutlet weak var moveDownShortcutView: MASShortcutView!
    
    @IBOutlet weak var almostMaximizeShortcutView: MASShortcutView!
    
    // Settings
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
            .smaller: makeSmallerShortcutView,
            .restore: restoreShortcutView,
            .leftThird: leftThirdShortcutView,
            .leftTwoThirds: leftTwoThirdsShortcutView,
            .horizCenterThird: horizCenterThirdShortcutView,
            .rightTwoThirds: rightTwoThirdsShortcutView,
            .rightThird: rightThirdShortcutView,
            .topThird: topThirdShortcutView,
            .topTwoThirds: topTwoThirdsShortcutView,
            .vertCenterThird: vertCenterThirdShortcutView,
            .bottomTwoThirds: bottomTwoThirdsShortcutView,
            .bottomThird: bottomThirdShortcutView,
            .moveLeft: moveLeftShortcutView,
            .moveRight: moveRightShortcutView,
            .moveUp: moveUpShortcutView,
            .moveDown: moveDownShortcutView,
            .almostMaximize: almostMaximizeShortcutView
        ]
        
        for (action, view) in actionsToViews {
            view.associatedUserDefaultsKey = action.name
        }
    }
}

class CustomTabView: NSTabView {
    
    override var acceptsFirstResponder: Bool {
        return false
    }
    
}
