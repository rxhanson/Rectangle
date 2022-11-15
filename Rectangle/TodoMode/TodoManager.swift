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
        guard let todoWindow = AccessibilityElement.getTodoWindowElement() else { return false }
        return isTodoWindow(w, todoWindow: todoWindow)
    }
    
    static func isTodoWindow(id: CGWindowID) -> Bool {
        AccessibilityElement.getTodoWindowElement()?.getWindowId() == id
    }

    private static func isTodoWindow(_ w: AccessibilityElement, todoWindow: AccessibilityElement) -> Bool {
        return w.getWindowId() == todoWindow.getWindowId()
    }
    
    static func moveAll() {
        TodoManager.refreshTodoScreen()

        let windows = AccessibilityElement.getAllWindowElements()

        if let todoWindow = AccessibilityElement.getTodoWindowElement() {
            if let screen = TodoManager.todoScreen {
                let sd = ScreenDetection()
                // Clear all windows from the todo app sidebar
                for w in windows {
                    let wScreen = sd.detectScreens(using: w)?.currentScreen
                    if w.getWindowId() != todoWindow.getWindowId() &&
                        wScreen == TodoManager.todoScreen {
                        shiftWindowOffSidebar(w, screenVisibleFrame: screen.adjustedVisibleFrame)
                    }
                }

                var rect = todoWindow.frame
                rect.origin.x = Defaults.todoMode.enabled && Defaults.todo.userEnabled
                    ? screen.adjustedVisibleFrame.maxX
                    : screen.adjustedVisibleFrame.maxX - Defaults.todoSidebarWidth.cgFloat
                rect.origin.y = screen.adjustedVisibleFrame.minY
                rect.size.height = screen.adjustedVisibleFrame.height
                rect.size.width = Defaults.todoSidebarWidth.cgFloat
                rect = rect.screenFlipped
                
                if Defaults.gapSize.value > 0 {
                    rect = GapCalculation.applyGaps(rect, sharedEdges: .left, gapSize: Defaults.gapSize.value)
                }
                todoWindow.setFrame(rect)
            }

            todoWindow.bringToFront()
        }
    }
    
    private static func refreshTodoScreen() {
        let todoWindow = AccessibilityElement.getTodoWindowElement()
        let screens = ScreenDetection().detectScreens(using: todoWindow)
        TodoManager.todoScreen = screens?.currentScreen
    }
    
    private static func shiftWindowOffSidebar(_ w: AccessibilityElement, screenVisibleFrame: CGRect) {
        var rect = w.frame
        let halfGapWidth = CGFloat(Defaults.gapSize.value) / 2

        if (rect.maxX > screenVisibleFrame.maxX - halfGapWidth) {
            // Shift it to the left
            rect.origin.x = min(rect.origin.x, max(screenVisibleFrame.minX, (rect.origin.x - (rect.maxX - screenVisibleFrame.maxX)))) + halfGapWidth
            
            // If it's still too wide, scale it down
            if(rect.maxX > screenVisibleFrame.maxX){
                rect.size.width = rect.size.width - (rect.maxX - screenVisibleFrame.maxX) - halfGapWidth
            }
            
            w.setFrame(rect)
        }
    }
}
