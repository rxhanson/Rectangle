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
        case .cascadeActiveApp:
            cascadeActiveAppWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        default:
            return false
        }
    }

    private static func allWindowsOnScreen(windowElement: AccessibilityElement? = nil, sortByPID: Bool = false) -> (screens: UsableScreens, windows: [AccessibilityElement])? {
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
                w1.pid ?? pid_t(0) > w2.pid ?? pid_t(0)
            })
        }

        var actualWindows = [AccessibilityElement]()
        for w in windows {
            if Defaults.todo.userEnabled, TodoManager.isTodoWindow(w) { continue }
            let screen = screenDetection.detectScreens(using: w)?.currentScreen
            if screen == currentScreen,
               w.isWindow == true,
               w.isSheet != true,
               w.isMinimized != true,
               w.isHidden != true,
               w.isSystemDialog != true
            {
                actualWindows.append(w)
            }
        }

        return (screens, actualWindows)
    }

    static func tileAllWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true) else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped
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

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)

        for (ind, w) in windows.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind)
        }
    }

    private struct CascadeActiveAppWindows {
        var right = false
        var bottom = false
        var n = 0
        var size = CGSizeZero

        init(windowFrame: CGRect, screenFrame: CGRect, n: Int, size: CGSize, delta: CGFloat) {
            right = windowFrame.midX > screenFrame.midX
            bottom = windowFrame.midY > screenFrame.midY
            self.n = n
            let m = CGSize(width: screenFrame.width - CGFloat(n - 1) * delta, height: screenFrame.height - CGFloat(n - 1) * delta)
            self.size = CGSize(width: min(size.width, m.width), height: min(size.height, m.height))
        }
    }

    static func cascadeActiveAppWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true),
              let frontWindowElement = AccessibilityElement.getFrontWindowElement()
        else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)

        // keep windows with a pid equal to the front window's pid
        var filtered = windows.filter(hasFrontWindowPid(_:))

        // parameters for cascading active app windows
        var caaw: CascadeActiveAppWindows?

        if let first = filtered.first {
            // move the first to become the last (top)
            filtered.removeFirst()
            filtered.append(first)
            caaw = CascadeActiveAppWindows(windowFrame: first.frame, screenFrame: screenFrame, n: filtered.count, size: first.size!, delta: delta)
        }

        // cascade the filtered windows
        for (ind, w) in filtered.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind, caaw: caaw)
        }

        // func returning true for a pid equal to the front window's pid
        func hasFrontWindowPid(_ w: AccessibilityElement) -> Bool {
            return w.pid == frontWindowElement.pid
        }
    }

    private static func cascadeWindow(_ w: AccessibilityElement, screenFrame: CGRect, delta: CGFloat, index: Int, caaw: CascadeActiveAppWindows? = nil) {
        var rect = w.frame

        // TODO: save previous position in history

        rect.origin.x = screenFrame.origin.x + delta * CGFloat(index)
        rect.origin.y = screenFrame.origin.y + delta * CGFloat(index)

        if let caaw {
            rect.size.width = caaw.size.width
            rect.size.height = caaw.size.height

            if caaw.right {
                rect.origin.x = screenFrame.origin.x + screenFrame.size.width - caaw.size.width - delta * CGFloat(index)
            }
            if caaw.bottom {
                rect.origin.y = screenFrame.origin.y + screenFrame.size.height - caaw.size.height - delta * CGFloat(caaw.n - 1 - index)
            }
        }

        w.setFrame(rect)
        w.bringToFront()
    }
}
