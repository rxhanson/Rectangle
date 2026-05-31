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
        let flippedRect = rect.screenFlipped
        let windowElement = resultParameters.windowElement
        var movedWindowRect: CGRect = windowElement.frame
        if !movedWindowRect.equalTo(flippedRect) {
            var adjustedWindowRect: CGRect = flippedRect
            while movedWindowRect.width > flippedRect.width || movedWindowRect.height > flippedRect.height {
                
                if movedWindowRect.width > flippedRect.width {
                    adjustedWindowRect.size.width -= 2
                }
                if movedWindowRect.height > flippedRect.height {
                    adjustedWindowRect.size.height -= 2
                }
                if adjustedWindowRect.width < flippedRect.width * 0.85 || adjustedWindowRect.height < flippedRect.height * 0.85 {
                    break
                }
                windowElement.setFrame(adjustedWindowRect)
                movedWindowRect = windowElement.frame
            }
            adjustedWindowRect.origin.x += floor((flippedRect.size.width - (movedWindowRect.size.width)) / 2.0)
            adjustedWindowRect.origin.y += floor((flippedRect.size.height - (movedWindowRect.size.height)) / 2.0)
            resultParameters.windowElement.setFrame(adjustedWindowRect)
        }
    }
}
