/// WindowHistory.swift

import Foundation

class WindowHistory {
    
    var restoreRects = [CGWindowID: CGRect]() // the last window frame that the user positioned
    
    var lastRectangleActions = [CGWindowID: RectangleAction]() // the last window frame that this app positioned
    
    var preMaximizeRects = [CGWindowID: CGRect]() // the normalized window frame right before this app last maximized / almost maximized it

    var cursorScreenFrames = [CGWindowID: CGRect]() // the frame of the display under the cursor when this app last acted on the window with cursor screen detection

    var cursorActions = [CGWindowID: WindowAction]() // the command pressed when this app last acted on the window with cursor screen detection, which can differ from the action it resulted in

    /// With cursor screen detection, a command is a fresh one on the cursor's
    /// display unless the cursor stayed on the display it was on last time.
    func cursorChangedDisplay(for windowId: CGWindowID?, cursorScreenFrame: CGRect) -> Bool {
        guard let windowId, let lastFrame = cursorScreenFrames[windowId] else { return true }
        return lastFrame != cursorScreenFrame
    }

    func recordAction(windowId: CGWindowID?,
                      resultingRect: CGRect,
                      action: WindowAction,
                      subAction: SubWindowAction?,
                      incrementCount: Bool = true) {
        guard let windowId else { return }
        let newCount: Int
        if let lastRectangleAction = lastRectangleActions[windowId],
           lastRectangleAction.action == action {
            newCount = incrementCount ? lastRectangleAction.count + 1 : lastRectangleAction.count
        } else {
            newCount = 1
        }

        lastRectangleActions[windowId] = RectangleAction(
            action: action,
            subAction: subAction,
            rect: resultingRect,
            count: newCount
        )
    }
}
