//
//  CenteringFixedSizedWindowMover.swift
//  Rectangle
//
//  Created by Ryan Hanson on 1/14/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation

/**
    If the window is fixed size, center it in the proposed window area
 */

class CenteringFixedSizedWindowMover: WindowMover {
    
    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        guard let currentWindowRect: CGRect = frontmostWindowElement?.frame else { return }

        var adjustedWindowRect: CGRect = currentWindowRect

        if currentWindowRect.size.width != windowRect.width {
            adjustedWindowRect.origin.x = round((windowRect.width - currentWindowRect.width) / 2.0) + windowRect.minX
        }
        
        if currentWindowRect.size.height != windowRect.height {
            adjustedWindowRect.origin.y = round((windowRect.height - currentWindowRect.height) / 2.0) + windowRect.minY
        }
        
        if !adjustedWindowRect.equalTo(currentWindowRect) {
            frontmostWindowElement?.setFrame(adjustedWindowRect)
        }
    }
}
