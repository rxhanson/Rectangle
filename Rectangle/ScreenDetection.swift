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
            return ScreenDetectionResult(sourceScreen: screens.first, destinationScreen: screens.first, adjacentScreens: nil)
        }
        
        let screensOrdered = order(screens: screens)
        guard let sourceScreen: NSScreen = screenContaining(frontmostWindowElement?.rectOfElement() ?? CGRect.zero, screens: screensOrdered) else {
            return ScreenDetectionResult(sourceScreen: screens.first, destinationScreen: screens.first, adjacentScreens: nil)
        }
        
        let adjacentScreens = adjacent(toFrameOfScreen: sourceScreen.frame, screens: screensOrdered)

        var destinationScreen: NSScreen? = sourceScreen
        if action.isMoveToDisplay {
            destinationScreen = nextOrPreviousScreen(toFrameOfScreen: NSRectToCGRect(sourceScreen.frame), inDirectionOf: action, screens: screensOrdered)
        }
        
        return ScreenDetectionResult(sourceScreen: sourceScreen, destinationScreen: destinationScreen, adjacentScreens: adjacentScreens)
    }

    private func screenContaining(_ rect: CGRect, screens: [NSScreen]) -> NSScreen? {
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
    
    func adjacent(toFrameOfScreen frameOfScreen: CGRect, screens: [NSScreen]) -> AdjacentScreens? {
        if screens.count == 1 {
//            if let onlyScreen = screens.first {
//                return AdjacentScreens(prev: onlyScreen, next: onlyScreen)
//            }
            return nil
        }
        else if screens.count == 2 {
            let otherScreen = screens.first(where: { screen in
                let frame = NSRectToCGRect(screen.frame)
                return !frame.equalTo(frameOfScreen)
            })
            if let otherScreen = otherScreen {
                return AdjacentScreens(prev: otherScreen, next: otherScreen)
            }
        } else {
            let currentScreenIndex = screens.firstIndex(where: { screen in
                let frame = NSRectToCGRect(screen.frame)
                return frame.equalTo(frameOfScreen)
            })
            if let currentScreenIndex = currentScreenIndex {
                let nextIndex = currentScreenIndex == screens.count - 1
                    ? 0
                    : currentScreenIndex + 1
                let prevIndex = currentScreenIndex == 0
                    ? screens.count - 1
                    : currentScreenIndex - 1
                return AdjacentScreens(prev: screens[prevIndex], next: screens[nextIndex])
            }
        }
        
        return nil
    }

    func nextOrPreviousScreen(toFrameOfScreen frameOfScreen: CGRect, inDirectionOf action: WindowAction, screens: [NSScreen]) -> NSScreen? {
        
        guard let adjacentScreens = adjacent(toFrameOfScreen: frameOfScreen, screens: screens) else { return nil }
        switch action {
        case .previousDisplay:
            return adjacentScreens.prev
        case .nextDisplay:
            return adjacentScreens.next
        default: return nil
        }
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
    let adjacentScreens: AdjacentScreens?
}

struct AdjacentScreens {
    let prev: NSScreen
    let next: NSScreen
}
