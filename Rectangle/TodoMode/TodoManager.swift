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
    private static var todoWindowId: CGWindowID?
    
    static var todoScreen : NSScreen?
    static let toggleDefaultsKey = "toggleTodo"
    static let reflowDefaultsKey = "reflowTodo"
    static let defaultsKeys = [toggleDefaultsKey, reflowDefaultsKey]
    
    static func setTodoMode(_ enabled: Bool, _ bringToFront: Bool = true) {
        Defaults.todoMode.enabled = enabled
        registerUnregisterReflowShortcut()
        moveAllIfNeeded(bringToFront)
    }
    
    static func initToggleShortcut() {
        if UserDefaults.standard.dictionary(forKey: toggleDefaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let toggleShortcut = MASShortcut(keyCode: kVK_ANSI_B,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let toggleShortcutDict = dictTransformer.reverseTransformedValue(toggleShortcut)
            UserDefaults.standard.set(toggleShortcutDict, forKey: toggleDefaultsKey)
        }
    }
    
    static func initReflowShortcut() {
        if UserDefaults.standard.dictionary(forKey: reflowDefaultsKey) == nil {
            guard let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)) else { return }
            
            let reflowShortcut = MASShortcut(keyCode: kVK_ANSI_N,
                                             modifierFlags: [NSEvent.ModifierFlags.control, NSEvent.ModifierFlags.option])
            let reflowShortcutDict = dictTransformer.reverseTransformedValue(reflowShortcut)
            UserDefaults.standard.set(reflowShortcutDict, forKey: reflowDefaultsKey)
        }
    }
    
    private static func registerToggleShortcut() {
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: toggleDefaultsKey, toAction: {
            let enabled = !Defaults.todoMode.enabled
            setTodoMode(enabled)
        })
    }
    
    private static func registerReflowShortcut() {
        MASShortcutBinder.shared()?.bindShortcut(withDefaultsKey: reflowDefaultsKey, toAction: {
            moveAll()
        })
    }
    
    private static func unregisterToggleShortcut() {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: toggleDefaultsKey)
    }
    
    private static func unregisterReflowShortcut() {
        MASShortcutBinder.shared()?.breakBinding(withDefaultsKey: reflowDefaultsKey)
    }
    
    static func registerUnregisterToggleShortcut() {
        if Defaults.todo.userEnabled {
            registerToggleShortcut()
        } else {
            unregisterToggleShortcut()
        }
    }
    
    static func registerUnregisterReflowShortcut() {
        if Defaults.todo.userEnabled && Defaults.todoMode.enabled {
            registerReflowShortcut()
        } else {
            unregisterReflowShortcut()
        }
    }
    
    static func getToggleKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard
            let shortcutDict = UserDefaults.standard.dictionary(forKey: toggleDefaultsKey),
            let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)),
            let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
        else {
            return nil
        }
        return (shortcut.keyCodeStringForKeyEquivalent, shortcut.modifierFlags)
    }
    
    static func getReflowKeyDisplay() -> (String?, NSEvent.ModifierFlags)? {
        guard
            let shortcutDict = UserDefaults.standard.dictionary(forKey: reflowDefaultsKey),
            let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName)),
            let shortcut = dictTransformer.transformedValue(shortcutDict) as? MASShortcut
        else {
            return nil
        }
        return (shortcut.keyCodeStringForKeyEquivalent, shortcut.modifierFlags)
    }
    
    private static func getTodoWindowElement() -> AccessibilityElement? {
        guard let bundleId = Defaults.todoApplication.value, let windowElements = AccessibilityElement(bundleId)?.windowElements else {
            todoWindowId = nil
            return nil
        }
        if let windowId = todoWindowId, !(windowElements.contains { $0.windowId == windowId }) {
            todoWindowId = nil
        }
        if todoWindowId == nil {
            todoWindowId = windowElements.first?.windowId
        }
        if let windowId = todoWindowId, let windowElement = (windowElements.first { $0.windowId == windowId }) {
            return windowElement
        }
        todoWindowId = nil
        return nil
    }
    
    static func hasTodoWindow() -> Bool {
        return getTodoWindowElement() != nil
    }
    
    static func isTodoWindowFront() -> Bool {
        guard let windowElement = AccessibilityElement.getFrontWindowElement() else { return false }
        return isTodoWindow(windowElement)
    }
    
    static func isTodoWindow(_ windowElement: AccessibilityElement) -> Bool {
        guard let windowId = windowElement.windowId else { return false }
        return isTodoWindow(windowId)
    }
    
    static func isTodoWindow(_ windowId: CGWindowID) -> Bool {
        return getTodoWindowElement()?.windowId == windowId
    }
    
    static func resetTodoWindow() {
        todoWindowId = nil
        _ = getTodoWindowElement()
    }
    
    static func moveAll(_ bringToFront: Bool = true) {
        TodoManager.refreshTodoScreen()

        let pid = ProcessInfo.processInfo.processIdentifier
        // Avoid footprint window
        let windows = AccessibilityElement.getAllWindowElements().filter { $0.pid != pid }

        if let todoWindow = getTodoWindowElement() {
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
    
    static func moveAllIfNeeded(_ bringToFront: Bool = true) {
        guard Defaults.todo.userEnabled && Defaults.todoMode.enabled else { return }
        moveAll(bringToFront)
    }
    
    private static func refreshTodoScreen() {
        let todoWindow = getTodoWindowElement()
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
    case right = 1
    case left = 2
}
