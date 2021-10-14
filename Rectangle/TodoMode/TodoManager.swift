//
//  TodoManager.swift
//  Rectangle
//
//  Created by Ryan Hanson on 1/18/21.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//

import Cocoa
import MASShortcut

class TodoManager {
    static var todoScreen : NSScreen?
    static let defaultsKey = "reflowTodo"
    
    static func registerReflowShortcut() {
        
        if UserDefaults.standard.dictionary(forKey: defaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let reflowShortcut = MASShortcut(keyCode: kVK_ANSI_N,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let reflowShortcutDict = dictTransformer.reverseTransformedValue(reflowShortcut)
            UserDefaults.standard.set(reflowShortcutDict, forKey: defaultsKey)
        }

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: defaultsKey, toAction: TodoManager.moveAll)
    }
    
    static func getReflowKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = MASShortcutBinder.shared()?.value(forKey: defaultsKey) as? MASShortcut else { return nil }
        return (masShortcut.keyCodeStringForKeyEquivalent, masShortcut.modifierFlags)
    }
    
    static func isTodoWindow(_ w: AccessibilityElement) -> Bool {
        guard let todoWindow = AccessibilityElement.todoWindow() else { return false }
        return isTodoWindow(w, todoWindow: todoWindow)
    }

    private static func isTodoWindow(_ w: AccessibilityElement, todoWindow: AccessibilityElement) -> Bool {
        return w.getIdentifier() == todoWindow.getIdentifier()
    }
    
    static func moveAll() {
        TodoManager.refreshTodoScreen()

        let windows = AccessibilityElement.allWindows()

        if let todoWindow = AccessibilityElement.todoWindow() {
            if let screen = TodoManager.todoScreen {
                let screenFrame = screen.frame as CGRect
                let sd = ScreenDetection()
                // Clear all windows from the todo app sidebar
                for w in windows {
                    let wScreen = sd.detectScreens(using: w)?.currentScreen
                    if w.getIdentifier() != todoWindow.getIdentifier() &&
                        wScreen == TodoManager.todoScreen {
                        shiftWindowOffSidebar(w, screenFrame: screenFrame)
                    }
                }

                var rect = todoWindow.rectOfElement()
                rect.origin.x = screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value)
                rect.origin.y = screenFrame.minY
                rect.size.height = screen.adjustedVisibleFrame.height
                rect.size.width = CGFloat(Defaults.todoSidebarWidth.value)
                todoWindow.setRectOf(rect)
            }

            todoWindow.bringToFront()
        }
    }
    
    private static func refreshTodoScreen() {
        let todoWindow = AccessibilityElement.todoWindow()
        let screens = ScreenDetection().detectScreens(using: todoWindow)
        TodoManager.todoScreen = screens?.currentScreen
    }
    
    private static func shiftWindowOffSidebar(_ w: AccessibilityElement, screenFrame: CGRect) {
        var rect = w.rectOfElement()

        if (rect.maxX > (screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value))) {
            // Shift it to the left
            rect.origin.x = max (0, rect.origin.x - (rect.maxX - (screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value))))

            // If it's still too wide, scale it down
            if (rect.origin.x == 0) {
                rect.size.width = min(rect.size.width, screenFrame.maxX - CGFloat(Defaults.todoSidebarWidth.value))
            }

            w.setRectOf(rect)
        }
    }
}
