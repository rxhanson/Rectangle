/// WindowHistory.swift

import Foundation

class WindowHistory {
    
    var restoreRects = [CGWindowID: CGRect]() // the last window frame that the user positioned
    
    var lastRectangleActions = [CGWindowID: RectangleAction]() // the last window frame that this app positioned
    
    var preMaximizeRects = [CGWindowID: CGRect]() // the normalized window frame right before this app last maximized / almost maximized it

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
