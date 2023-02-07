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
    static let toggleDefaultsKey = "toggleTodo"
    static let reflowDefaultsKey = "reflowTodo"
    static let defaultsKeys = [toggleDefaultsKey, reflowDefaultsKey]
    
    static func registerToggleShortcut() {
        
        if UserDefaults.standard.dictionary(forKey: toggleDefaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let toggleShortcut = MASShortcut(keyCode: kVK_ANSI_B,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let toggleShortcutDict = dictTransformer.reverseTransformedValue(toggleShortcut)
            UserDefaults.standard.set(toggleShortcutDict, forKey: toggleDefaultsKey)
        }

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: toggleDefaultsKey, toAction: {
            guard Defaults.todo.userEnabled else { return }
            Defaults.todoMode.enabled.toggle()
            if Defaults.todoMode.enabled {
                TodoManager.moveAll()
            }
        })
    }
    
    static func registerReflowShortcut() {
        
        if UserDefaults.standard.dictionary(forKey: reflowDefaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let reflowShortcut = MASShortcut(keyCode: kVK_ANSI_N,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let reflowShortcutDict = dictTransformer.reverseTransformedValue(reflowShortcut)
            UserDefaults.standard.set(reflowShortcutDict, forKey: reflowDefaultsKey)
        }

        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: reflowDefaultsKey, toAction: {
            guard Defaults.todo.userEnabled && Defaults.todoMode.enabled else { return }
            TodoManager.moveAll()
        })
    }
    
    static func getToggleKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = MASShortcutBinder.shared()?.value(forKey: toggleDefaultsKey) as? MASShortcut else { return nil }
        return (masShortcut.keyCodeStringForKeyEquivalent, masShortcut.modifierFlags)
    }
    
    static func getReflowKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard let masShortcut = MASShortcutBinder.shared()?.value(forKey: reflowDefaultsKey) as? MASShortcut else { return nil }
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
    
    static func moveAll(_ bringToFront: Bool = true) {
        TodoManager.refreshTodoScreen()

        let pid = ProcessInfo.processInfo.processIdentifier
        // Avoid footprint window
        let windows = AccessibilityElement.getAllWindowElements().filter { $0.pid != pid }

        if let todoWindow = AccessibilityElement.getTodoWindowElement() {
            if let screen = TodoManager.todoScreen {
                let sd = ScreenDetection()
                var adjustedVisibleFrame = screen.adjustedVisibleFrame()
                // Clear all windows from the todo app sidebar
                for w in windows {
                    let wScreen = sd.detectScreens(using: w)?.currentScreen
                    if w.getWindowId() != todoWindow.getWindowId() &&
                        wScreen == TodoManager.todoScreen {
                        shiftWindowOffSidebar(w, screenVisibleFrame: adjustedVisibleFrame)
                    }
                }

                adjustedVisibleFrame = screen.adjustedVisibleFrame(true)
                var sharedEdge: Edge
                var rect = adjustedVisibleFrame
                switch Defaults.todoSidebarSide.value {
                case .left:
                    sharedEdge = .right
                case .right:
                    sharedEdge = .left
                    rect.origin.x = adjustedVisibleFrame.maxX - Defaults.todoSidebarWidth.cgFloat
                }
                rect.size.width = Defaults.todoSidebarWidth.cgFloat
                rect = rect.screenFlipped
                
                if Defaults.gapSize.value > 0 {
                    rect = GapCalculation.applyGaps(rect, sharedEdges: sharedEdge, gapSize: Defaults.gapSize.value)
                }
                todoWindow.setFrame(rect)
            }

            if bringToFront {
                todoWindow.bringToFront()
            }
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
        let screenVisibleFrameMinX = screenVisibleFrame.minX + halfGapWidth
        let screenVisibleFrameMaxX = screenVisibleFrame.maxX - halfGapWidth

        if Defaults.todoSidebarSide.value == .left && rect.minX < screenVisibleFrameMinX {
            // Shift it to the right
            rect.origin.x = min(screenVisibleFrame.maxX - rect.width, rect.origin.x + (screenVisibleFrameMinX - rect.minX))
            
            // If it's still too wide, scale it down
            if rect.minX < screenVisibleFrameMinX {
                let widthDiff = screenVisibleFrameMinX - rect.minX
                rect.origin.x += widthDiff
                rect.size.width -= widthDiff
            }
            
            w.setFrame(rect)
        } else if Defaults.todoSidebarSide.value == .right && rect.maxX > screenVisibleFrameMaxX {
            // Shift it to the left
            rect.origin.x = min(rect.origin.x, max(screenVisibleFrame.minX, rect.origin.x - (rect.maxX - screenVisibleFrameMaxX)))
            
            // If it's still too wide, scale it down
            if rect.maxX > screenVisibleFrameMaxX {
                rect.size.width -= rect.maxX - screenVisibleFrameMaxX
            }
            
            w.setFrame(rect)
        }
    }
    
    static func execute(parameters: ExecutionParameters) -> Bool {
        if [.leftTodo, .rightTodo].contains(parameters.action) {
            moveAll()
            return true
        }
        return false
    }
}

enum TodoSidebarSide: Int {
    case left = 0
    case right = 1
}
