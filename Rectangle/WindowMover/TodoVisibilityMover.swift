//
//  TodoVisibilityMover.swift
//  Rectangle
//
//  Created by Patrick Collison on 12/30/20.
//  Copyright © 2020 Ryan Hanson. All rights reserved.
//

import Foundation
import os.log

class TodoVisibilityWindowMover: WindowMover {
    private let kTodoWidth = CGFloat(300)

    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        if(Defaults.todoMode.enabled) {
            guard var movedWindowRect: CGRect = frontmostWindowElement?.rectOfElement() else { return }
            let todoAccommodatingMaxX = visibleFrameOfScreen.maxX - kTodoWidth

            if movedWindowRect.maxX > todoAccommodatingMaxX {
                var adjustedWindowRect: CGRect = windowRect

                adjustedWindowRect.size.width -= (movedWindowRect.maxX - todoAccommodatingMaxX)
                frontmostWindowElement?.setRectOf(adjustedWindowRect)
            }
        }
    }
}
