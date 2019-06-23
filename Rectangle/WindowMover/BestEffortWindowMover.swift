//
//  BestEffortWindowMover.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class BestEffortWindowMover: WindowMover {
    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        guard var movedWindowRect: CGRect = frontmostWindowElement?.rectOfElement() else { return }
        
        let previouslyMovedWindowRect: CGRect = movedWindowRect
        if movedWindowRect.origin.x < visibleFrameOfScreen.origin.x {
            
            movedWindowRect.origin.x = visibleFrameOfScreen.origin.x
            
        } else if movedWindowRect.origin.x + movedWindowRect.size.width > visibleFrameOfScreen.origin.x + visibleFrameOfScreen.size.width {
            
            movedWindowRect.origin.x = visibleFrameOfScreen.origin.x + visibleFrameOfScreen.size.width - (movedWindowRect.size.width)
        }
        
        movedWindowRect = AccessibilityElement.normalizeCoordinatesOf(movedWindowRect , frameOfScreen: frameOfScreen)
        if movedWindowRect.origin.y < visibleFrameOfScreen.origin.y {
            
            movedWindowRect.origin.y = visibleFrameOfScreen.origin.y
            
        } else if movedWindowRect.origin.y + movedWindowRect.size.height > visibleFrameOfScreen.origin.y + visibleFrameOfScreen.size.height {
            
            movedWindowRect.origin.y = visibleFrameOfScreen.origin.y + visibleFrameOfScreen.size.height - (movedWindowRect.size.height)
        }
        
        movedWindowRect = AccessibilityElement.normalizeCoordinatesOf(movedWindowRect , frameOfScreen: frameOfScreen)
        if !movedWindowRect.equalTo(previouslyMovedWindowRect) {
            frontmostWindowElement?.setRectOf(movedWindowRect )
        }
    }
}
