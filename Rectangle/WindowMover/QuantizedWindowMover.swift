//
//  QuantizedWindowMover.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class QuantizedWindowMover: WindowMover {
    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        guard var movedWindowRect: CGRect = frontmostWindowElement?.frame else { return }
        if !movedWindowRect.equalTo(windowRect) {
            var adjustedWindowRect: CGRect = windowRect
            while movedWindowRect.width > windowRect.width || movedWindowRect.height > windowRect.height {
                
                if movedWindowRect.width > windowRect.width {
                    adjustedWindowRect.size.width -= 2
                }
                if movedWindowRect.height > windowRect.height {
                    adjustedWindowRect.size.height -= 2
                }
                if adjustedWindowRect.width < windowRect.width * 0.85 || adjustedWindowRect.height < windowRect.height * 0.85 {
                    break
                }
                frontmostWindowElement?.setFrame(adjustedWindowRect)
                if let frontMostRect = frontmostWindowElement?.frame {
                    movedWindowRect = frontMostRect
                }
            }
            adjustedWindowRect.origin.x += floor((windowRect.size.width - (movedWindowRect.size.width)) / 2.0)
            adjustedWindowRect.origin.y += floor((windowRect.size.height - (movedWindowRect.size.height)) / 2.0)
            frontmostWindowElement?.setFrame(adjustedWindowRect)
        }
    }
}
