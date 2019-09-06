//
//  WindowHistory.swift
//  Rectangle
//
//  Created by Ryan Hanson on 9/6/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class WindowHistory {
    
    typealias WindowId = Int
    
    var restoreRects = [WindowId: CGRect]() // the last window frame that the user positioned
    
    var lastRectangleActions = [WindowId: RectangleAction]() // the last window frame that this app positioned
    
}
