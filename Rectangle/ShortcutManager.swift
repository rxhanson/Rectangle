//
//  ShortcutManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import MASShortcut
import Cocoa

class ShortcutManager {
    
    let windowManager: WindowManager
    
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        
        registerDefaults()

        bindShortcuts()
        
        subscribeAllWindowActions(selector: #selector(windowActionTriggered))
        subscribeAllToggleActions(selector: #selector(toggleActionTriggered))
    }
    
    public func bindShortcuts() {
        for action in WindowAction.active {
            MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: action.name, toAction: action.post)
        }
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: ToggleAction.disableForAllApps.name, toAction: ToggleAction.disableForAllApps.post)
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: ToggleAction.disableForCurrentApp.name, toAction: ToggleAction.disableForCurrentApp.post)
    }
    
    public func unbindShortcuts() {
        for action in WindowAction.active {
            MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: action.name)
        }
    }
    
    public func getKeyEquivalent(action: WindowAction) -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = MASShortcutBinder.shared()?.value(forKey: action.name) as? MASShortcut else { return nil }
        return (masShortcut.keyCodeStringForKeyEquivalent, masShortcut.modifierFlags)
    }
    
    deinit {
        unsubscribe()
    }
    
    private func registerDefaults() {
        
        var defaultShortcuts = WindowAction.active.reduce(into: [String: MASShortcut]()) { dict, windowAction in
            guard let defaultShortcut = Defaults.alternateDefaultShortcuts.enabled
                ? windowAction.alternateDefault
                : windowAction.spectacleDefault
            else { return }
            let shortcut = MASShortcut(keyCode: defaultShortcut.keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: defaultShortcut.modifierFlags))
            dict[windowAction.name] = shortcut
        }
        defaultShortcuts[ToggleAction.disableForAllApps.name] = MASShortcut(keyCode: ToggleAction.disableForAllApps.defaultShortcut!.keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: ToggleAction.disableForAllApps.defaultShortcut!.modifierFlags))
        defaultShortcuts[ToggleAction.disableForAllApps.name] = MASShortcut(keyCode: ToggleAction.disableForCurrentApp.defaultShortcut!.keyCode, modifierFlags: NSEvent.ModifierFlags(rawValue: ToggleAction.disableForCurrentApp.defaultShortcut!.modifierFlags))
        
        MASShortcutBinder.shared()?.registerDefaultShortcuts(defaultShortcuts)
    }
    
    @objc func windowActionTriggered(notification: NSNotification) {
        guard let parameters = notification.object as? ExecutionParameters else { return }
        windowManager.execute(parameters)
    }
    
    @objc func toggleActionTriggered(notification: NSNotification) {
        
        if Logger.logging {
            Logger.log("toggleActionTriggered - " + notification.name.rawValue)
        }
        if notification.name.rawValue == ToggleAction.disableForAllApps.name {
            AppDelegate.instance().applicationToggle.toggleDisableForAllApps()
        } else if notification.name.rawValue == ToggleAction.disableForCurrentApp.name {
            AppDelegate.instance().applicationToggle.toggleDisableForCurrentApp()
        }
    }
    
    private func subscribe(notification: WindowAction, selector: Selector) {
        NotificationCenter.default.addObserver(self, selector: selector, name: notification.notificationName, object: nil)
    }
    
    private func unsubscribe() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func subscribeAllWindowActions(selector: Selector) {
        for windowAction in WindowAction.active {
            subscribe(notification: windowAction, selector: selector)
        }
    }
    
    private func subscribeAllToggleActions(selector: Selector) {
        NotificationCenter.default.addObserver(self, selector: selector, name: ToggleAction.disableForAllApps.notficationName, object: nil)
        NotificationCenter.default.addObserver(self, selector: selector, name: ToggleAction.disableForCurrentApp.notficationName, object: nil)
    }
}
