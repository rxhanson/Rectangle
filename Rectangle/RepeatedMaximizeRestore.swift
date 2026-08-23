//
//  RepeatedMaximizeRestore.swift
//  Rectangle
//

import Foundation

/// Opt-in (`repeatedMaximizeRestoresPrevious`): executing Maximize or Almost Maximize on a window that
/// Rectangle has just put in that state restores the frame the window had right before, instead of
/// doing nothing.
///
/// Consulted by `MaximizeCalculation` and `AlmostMaximizeCalculation` before they calculate their own
/// rect. The restore is reported as `.restore`, so the next execution of the action maximizes the
/// window again, calculated from scratch.
enum RepeatedMaximizeRestore {
    
    static func applies(to action: WindowAction) -> Bool {
        action == .maximize || action == .almostMaximize
    }
    
    /// The result to use instead of maximizing, or nil to let the calculation proceed as usual.
    /// Records the frame to come back to whenever the window is about to be maximized.
    static func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        guard Defaults.repeatedMaximizeRestoresPrevious.enabled,
              applies(to: params.action),
              let windowId = params.window.id
        else { return nil }
        
        if let previousRect = restoreRect(for: params.action,
                                          windowRect: params.window.rect,
                                          lastAction: params.lastAction,
                                          preMaximizeRect: AppDelegate.windowHistory.preMaximizeRects[windowId]) {
            return WindowCalculationResult(rect: previousRect,
                                           screen: params.usableScreens.currentScreen,
                                           resultingAction: .restore)
        }
        
        AppDelegate.windowHistory.preMaximizeRects[windowId] = params.window.rect
        return nil
    }
    
    /// The frame to restore instead of executing `action`, or nil to execute it normally.
    ///
    /// Restores only when `action` is the action that last positioned the window, the window has not
    /// been moved since, and a frame from before was recorded for it. `windowRect` and the result are
    /// normalized (screen flipped) rects, `lastAction` holds the accessibility rect it resulted in.
    static func restoreRect(for action: WindowAction,
                            windowRect: CGRect,
                            lastAction: RectangleAction?,
                            preMaximizeRect: CGRect?) -> CGRect? {
        guard Defaults.repeatedMaximizeRestoresPrevious.enabled,
              applies(to: action),
              let lastAction,
              lastAction.action == action,
              lastAction.rect.screenFlipped == windowRect,
              let preMaximizeRect
        else { return nil }
        return preMaximizeRect
    }
    
    static func restoreRect(for action: WindowAction, windowId: CGWindowID, windowRect: CGRect) -> CGRect? {
        restoreRect(for: action,
                    windowRect: windowRect.screenFlipped,
                    lastAction: AppDelegate.windowHistory.lastRectangleActions[windowId],
                    preMaximizeRect: AppDelegate.windowHistory.preMaximizeRects[windowId])
    }
}
