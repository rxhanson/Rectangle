//
//  ScreenDetection.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class ScreenDetection {

    func screen(with action: WindowAction, frontmostWindowElement: AccessibilityElement?) -> ScreenDetectionResult {
        let screens = NSScreen.screens
        
        if screens.count == 1 {
            return ScreenDetectionResult(sourceScreen: screens.first, destinationScreen: screens.first)
        }
        
        let screensOrdered = order(screens: screens)
        guard let sourceScreen: NSScreen = screenContaining(frontmostWindowElement?.rectOfElement() ?? CGRect.zero, screens: screensOrdered) else {
            return ScreenDetectionResult(sourceScreen: screens.first, destinationScreen: screens.first)
        }
        var destinationScreen: NSScreen? = sourceScreen
        if action.isMoveToDisplay {
            destinationScreen = nextOrPreviousScreen(toFrameOfScreen: NSRectToCGRect(sourceScreen.frame), inDirectionOf: action, screens: screensOrdered)
            
        }
        return ScreenDetectionResult(sourceScreen: sourceScreen, destinationScreen: destinationScreen)
    }

    func screenContaining(_ rect: CGRect, screens: [NSScreen]) -> NSScreen? {
        var result: NSScreen? = NSScreen.main
        var largestPercentageOfRectWithinFrameOfScreen: CGFloat = 0.0
        for currentScreen in screens {
            let currentFrameOfScreen = NSRectToCGRect(currentScreen.frame)
            let normalizedRect: CGRect = AccessibilityElement.normalizeCoordinatesOf(rect, frameOfScreen: currentFrameOfScreen)
            if currentFrameOfScreen.contains(normalizedRect) {
                result = currentScreen
                break
            }
            let percentageOfRectWithinCurrentFrameOfScreen: CGFloat = percentageOf(normalizedRect, withinFrameOfScreen: currentFrameOfScreen)
            if percentageOfRectWithinCurrentFrameOfScreen > largestPercentageOfRectWithinFrameOfScreen {
                largestPercentageOfRectWithinFrameOfScreen = percentageOfRectWithinCurrentFrameOfScreen
                result = currentScreen
            }
        }
        return result
    }

    func percentageOf(_ rect: CGRect, withinFrameOfScreen frameOfScreen: CGRect) -> CGFloat {
        let intersectionOfRectAndFrameOfScreen: CGRect = rect.intersection(frameOfScreen)
        var result: CGFloat = 0.0
        if !intersectionOfRectAndFrameOfScreen.isNull {
            result = computeAreaOfRect(rect: intersectionOfRectAndFrameOfScreen) / computeAreaOfRect(rect: rect)
        }
        return result
    }

    func nextOrPreviousScreen(toFrameOfScreen frameOfScreen: CGRect, inDirectionOf action: WindowAction, screens: [NSScreen]?) -> NSScreen? {
        guard let screens = screens, screens.count > 1 else { return nil }
        var result: NSScreen? = nil
        for i in 0..<screens.count {
            let currentScreen: NSScreen = screens[i]
            let currentFrameOfScreen = NSRectToCGRect(currentScreen.frame)
            var nextOrPreviousIndex: Int = i
            if !currentFrameOfScreen.equalTo(frameOfScreen) {
                continue
            }
            if action == .nextDisplay {
                nextOrPreviousIndex += 1
            } else if action == .previousDisplay {
                nextOrPreviousIndex -= 1
            }
            if nextOrPreviousIndex < 0 {
                nextOrPreviousIndex = screens.count - 1
            } else if nextOrPreviousIndex >= screens.count {
                nextOrPreviousIndex = 0
            }
            result = screens[nextOrPreviousIndex]
            break
        }
        return result
    }

    func order(screens: [NSScreen]) -> [NSScreen] {
        let sortedByY = screens.sorted(by: { screen1, screen2 in
            return screen1.frame.origin.y < screen2.frame.origin.y
        })
        let alsoSortedByX = sortedByY.sorted(by: { screen1, screen2 in
            return screen1.frame.origin.x < screen2.frame.origin.x
        })
        return alsoSortedByX
    }
    
    private func computeAreaOfRect(rect: CGRect) -> CGFloat {
        return rect.size.width * rect.size.height
    }

}

struct ScreenDetectionResult {
    let sourceScreen: NSScreen?
    let destinationScreen: NSScreen?
}
