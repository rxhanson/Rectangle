//
//  WindowHistory.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/6/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class WindowHistory {
    
    var restoreRects = [CGWindowID: CGRect]() // the last window frame that the user positioned
    
    var lastRectangleActions = [CGWindowID: RectangleAction]() // the last window frame that this app positioned
    
}
