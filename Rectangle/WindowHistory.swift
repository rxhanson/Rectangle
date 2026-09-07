/// WindowHistory.swift

import Foundation

class WindowHistory {
    
    var restoreRects = [CGWindowID: CGRect]() // the last window frame that the user positioned
    
    var lastRectangleActions = [CGWindowID: RectangleAction]() // the last window frame that this app positioned
    
    var preMaximizeRects = [CGWindowID: CGRect]() // the normalized window frame right before this app last maximized / almost maximized it
    
}
