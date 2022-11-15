//
//  MultiWindowManager.swift
//  Rectangle
//
//  Created by Mikhail (Dirondin) Polubisok on 2/20/22.
//  Copyright © 2021 Ryan Hanson. All rights reserved.
//
import Cocoa
import MASShortcut

class MultiWindowManager {
    
    static func execute(parameters: ExecutionParameters) -> Bool {
        // TODO: Protocol and factory for all multi-window positioning algorithms
        switch parameters.action {
        case .reverseAll:
            ReverseAllManager.reverseAll(windowElement: parameters.windowElement)
            return true
        case .tileAll:
            tileAllWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .cascadeAll:
            cascadeAllWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        default:
            return false
        }
    }

    static private func allWindowsOnScreen(windowElement: AccessibilityElement? = nil, sortByPID: Bool = false) -> (screens: UsableScreens, windows: [AccessibilityElement])? {
        let screenDetection = ScreenDetection()
        
        guard let windowElement = windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let screens = screenDetection.detectScreens(using: windowElement)
        else {
            NSSound.beep()
            Logger.log("Can't detect screen for multiple windows")
            return nil
        }

        let currentScreen = screens.currentScreen

        var windows = AccessibilityElement.getAllWindowElements()
        if sortByPID {
            windows.sort(by: { (w1: AccessibilityElement, w2: AccessibilityElement) -> Bool in
                return w1.pid ?? pid_t(0) > w2.pid ?? pid_t(0)
            })
        }

        var actualWindows = [AccessibilityElement]()
        for w in windows {
            if Defaults.todo.userEnabled && TodoManager.isTodoWindow(w) { continue }
            let screen = screenDetection.detectScreens(using: w)?.currentScreen
            if screen == currentScreen
                && w.isWindow == true
                && w.isSheet != true
                && w.isMinimized != true
                && w.isHidden != true
                && w.isSystemDialog != true {
                actualWindows.append(w)
            }
        }
        
        return (screens, actualWindows)
    }
    
    static func tileAllWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true) else {
            return
        }
        
        let screenFrame = screens.visibleFrameOfCurrentScreen.screenFlipped
        let count = windows.count
        
        let colums = Int(ceil(sqrt(CGFloat(count))))
        let rows = Int(ceil(CGFloat(count) / CGFloat(colums)))
        let size = CGSize(width: (screenFrame.maxX - screenFrame.minX) / CGFloat(colums), height: (screenFrame.maxY - screenFrame.minY) / CGFloat(rows))

        for (ind, w) in windows.enumerated() {
            let column = ind % Int(colums)
            let row = ind / Int(colums)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
    }

    private static func tileWindow(_ w: AccessibilityElement, screenFrame: CGRect, size: CGSize, column: Int, row: Int) {
        var rect = w.frame
        
        // TODO: save previous position in history
      
        rect.origin.x = screenFrame.origin.x + size.width * CGFloat(column)
        rect.origin.y = screenFrame.origin.y + size.height * CGFloat(row)
        rect.size = size
        
        w.setFrame(rect)
    }
    
    static func cascadeAllWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true) else {
            return
        }
        
        let screenFrame = screens.visibleFrameOfCurrentScreen.screenFlipped
        
        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)
        
        for (ind, w) in windows.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind)
        }
    }

    private static func cascadeWindow(_ w: AccessibilityElement, screenFrame: CGRect, delta: CGFloat, index: Int) {
        var rect = w.frame
        
        // TODO: save previous position in history
      
        rect.origin.x = screenFrame.origin.x + delta * CGFloat(index)
        rect.origin.y = screenFrame.origin.y + delta * CGFloat(index)
        
        w.setFrame(rect)
        w.bringToFront()
    }
}
