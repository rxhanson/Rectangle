//
//  ShortcutManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import MASShortcut

class ShortcutManager {
    
    let windowManager = WindowManager()
    let applicationToggle: ApplicationToggle
    
    init(applicationToggle: ApplicationToggle) {
        self.applicationToggle = applicationToggle
        
        registerDefaults()

        for action in WindowAction.active {
            MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: action.name, toAction: action.post)
        }
        
        subscribeAll(selector: #selector(windowActionTriggered))
    }
    
    deinit {
        unsubscribe()
    }
    
    private func registerDefaults() {
        
        let defaultShortcuts = WindowAction.active.reduce(into: [String: MASShortcut]()) { dict, windowAction in
            guard let defaultShortcut = Defaults.alternateDefaultShortcuts.enabled
                ? windowAction.alternateDefault
                : windowAction.spectacleDefault
            else { return }
            let shortcut = MASShortcut(keyCode: UInt(defaultShortcut.keyCode), modifierFlags: defaultShortcut.modifierFlags)
            dict[windowAction.name] = shortcut
        }
        
        MASShortcutBinder.shared()?.registerDefaultShortcuts(defaultShortcuts)
    }
    
    @objc func windowActionTriggered(notification: NSNotification) {
        guard let windowAction = notification.object as? WindowAction else { return }
        if !applicationToggle.disabledForApp {
            windowManager.execute(windowAction)            
        }
    }
    
    private func subscribe(notification: WindowAction, selector: Selector) {
        NotificationCenter.default.addObserver(self, selector: selector, name: notification.notificationName, object: nil)
    }
    
    private func unsubscribe() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func subscribeAll(selector: Selector) {
        for windowAction in WindowAction.active {
            subscribe(notification: windowAction, selector: selector)
        }
    }
}
