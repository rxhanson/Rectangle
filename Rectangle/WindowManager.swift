//
//  WindowManager.swift
//  Rectangle, Ported from Spectacle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Foundation
import Cocoa

class WindowManager {
    private var applicationPrevRects = [String : PreviousRect?]()
    private let screenDetection = ScreenDetection()
    private let windowMoverChain: [WindowMover]
    private let windowCalculationFactory = WindowCalculationFactory()
    
    init() {
        windowMoverChain = [StandardWindowMover(), QuantizedWindowMover(), BestEffortWindowMover()]
    }
    
    func execute(_ action: WindowAction) {
        guard let frontmostWindowElement = AccessibilityElement.frontmostWindow()
            else {
                NSSound.beep()
                return
        }

        let screenDetectionResult: ScreenDetectionResult = screenDetection.screen(with: action, frontmostWindowElement: frontmostWindowElement)
        
        if action == .undo {
            undoLastWindowAction()
            return
        }
        
        var frameOfDestinationScreen = CGRect.null
        var visibleFrameOfDestinationScreen = CGRect.null
        var visibleFrameOfSourceScreen = CGRect.null
        
        if let destinationScreen = screenDetectionResult.destinationScreen,
            let sourceScreen = screenDetectionResult.sourceScreen {
            frameOfDestinationScreen = NSRectToCGRect(destinationScreen.frame)
            visibleFrameOfDestinationScreen = NSRectToCGRect(destinationScreen.visibleFrame)
            visibleFrameOfSourceScreen = NSRectToCGRect(sourceScreen.visibleFrame)
        }

        let currentWindowRect: CGRect = frontmostWindowElement.rectOfElement()

        if frontmostWindowElement.isSheet()
            || frontmostWindowElement.isSystemDialog()
            || currentWindowRect.isNull
            || frameOfDestinationScreen.isNull
            || visibleFrameOfDestinationScreen.isNull
            || visibleFrameOfSourceScreen.isNull {
            NSSound.beep()
            return
        }

        let currentNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(currentWindowRect, frameOfScreen: frameOfDestinationScreen)
        
        let windowCalculation = windowCalculationFactory.calculation(for: action)

        guard let newRect = windowCalculation.calculate(currentNormalizedRect, visibleFrameOfSourceScreen: visibleFrameOfSourceScreen, visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen, action: action) else {
            NSSound.beep()
            return
        }
        
        let newNormalizedRect = AccessibilityElement.normalizeCoordinatesOf(newRect, frameOfScreen: frameOfDestinationScreen)
        
        if currentNormalizedRect.equalTo(newNormalizedRect) {
            NSSound.beep()
            return
        }
        
        for windowMover in windowMoverChain {
            windowMover.moveWindowRect(newNormalizedRect, frameOfScreen: frameOfDestinationScreen, visibleFrameOfScreen: visibleFrameOfDestinationScreen, frontmostWindowElement: frontmostWindowElement, action: action)
        }
        
    }
    
    func undoLastWindowAction() {
        // TODO add this in... also add in saving the last window rect
        print("not yet supported")
    }
    
    private func getFrontMostAppIdentifier() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

struct PreviousRect {
    let accessibilityElement: AccessibilityElement
    let windowRect: CGRect
}
