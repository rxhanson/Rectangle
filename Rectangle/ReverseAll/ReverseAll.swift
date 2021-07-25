//
//  TodoManager.swift
//  Rectangle
//
//  Created by Charlie Harding on 7/25/21.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//

import Cocoa
import MASShortcut

class ReverseAllManager {
    static let defaultsKey = "reverseAllShortcut"
    
    static func registerReverseAllShortcut() {
        
        if UserDefaults.standard.dictionary(forKey: defaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let reverseAllShortcut = MASShortcut(keyCode: kVK_Tab,
                                                 modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option, NSEvent.ModifierFlags.command])
            let reverseAllShortcutDict = dictTransformer.reverseTransformedValue(reverseAllShortcut)
            UserDefaults.standard.set(reverseAllShortcutDict, forKey: defaultsKey)
        }
        
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: defaultsKey, toAction: reverseAll)
    }
    
    static func getReverseAllKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = MASShortcutBinder.shared()?.value(forKey: defaultsKey) as? MASShortcut else { return nil }
        return (masShortcut.keyCodeStringForKeyEquivalent, masShortcut.modifierFlags)
    }
    
    static func reverseAll() {
        let sd = ScreenDetection()
        
        let currentWindow = AccessibilityElement.frontmostWindow()
        guard let currentScreen = sd.detectScreens(using: currentWindow)?.currentScreen else { return }
        
        let windows = AccessibilityElement.allWindows()
        
        let screenFrame = currentScreen.frame as CGRect
        
        for w in windows {
            let wScreen = sd.detectScreens(using: w)?.currentScreen
            if wScreen == currentScreen {
                reverseWindowPosition(w, screenFrame: screenFrame)
            }
        }
    }
    
    private static func reverseWindowPosition(_ w: AccessibilityElement, screenFrame: CGRect) {
        var rect = w.rectOfElement()
        
        let offsetFromLeft = rect.minX - screenFrame.minX
        
        rect.origin.x = screenFrame.maxX - offsetFromLeft - rect.width
        
        w.setRectOf(rect)
    }
}
