//
//  StandardWindowMover.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/13/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation

class StandardWindowMover: WindowMover {
    func moveWindowRect(_ windowRect: CGRect, frameOfScreen: CGRect, visibleFrameOfScreen: CGRect, frontmostWindowElement: AccessibilityElement?, action: WindowAction?) {
        let previousWindowRect: CGRect? = frontmostWindowElement?.frame
        if previousWindowRect?.isNull == true {
            return
        }
        frontmostWindowElement?.setFrame(windowRect)
    }
}
