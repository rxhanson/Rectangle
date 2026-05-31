//
//  QuantizedWindowMover.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class QuantizedWindowMover: WindowMover {
    func moveWindow(toRect rect: CGRect, resultParameters: ResultParameters) {
        let windowElement = resultParameters.windowElement
        var movedWindowRect: CGRect = windowElement.frame
        if !movedWindowRect.equalTo(rect) {
            var adjustedWindowRect: CGRect = rect
            while movedWindowRect.width > rect.width || movedWindowRect.height > rect.height {
                
                if movedWindowRect.width > rect.width {
                    adjustedWindowRect.size.width -= 2
                }
                if movedWindowRect.height > rect.height {
                    adjustedWindowRect.size.height -= 2
                }
                if adjustedWindowRect.width < rect.width * 0.85 || adjustedWindowRect.height < rect.height * 0.85 {
                    break
                }
                windowElement.setFrame(adjustedWindowRect)
                movedWindowRect = windowElement.frame
            }
            adjustedWindowRect.origin.x += floor((rect.size.width - (movedWindowRect.size.width)) / 2.0)
            adjustedWindowRect.origin.y += floor((rect.size.height - (movedWindowRect.size.height)) / 2.0)
            resultParameters.windowElement.setFrame(adjustedWindowRect)
        }
    }
}
