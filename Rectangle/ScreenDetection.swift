//
//  ScreenDetection.swift
//  Rectangle
//
//  Created by Ryan Hanson on 6/12/19.
//  Copyright © 2019 Ryan Hanson. All rights reserved.
//

import Cocoa

class ScreenDetection {

    func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
        let screens = NSScreen.screens
        guard let firstScreen = screens.first else { return nil }
        
        if screens.count == 1 {
            let adjacentScreens = Defaults.traverseSingleScreen.enabled == true
            ? AdjacentScreens(prev: firstScreen, next: firstScreen)
            : nil
            
            return UsableScreens(currentScreen: firstScreen, adjacentScreens: adjacentScreens, numScreens: screens.count)
        }
        
        let screensOrdered = order(screens: screens)
        guard let sourceScreen: NSScreen = screenContaining(frontmostWindowElement?.rectOfElement() ?? CGRect.zero, screens: screensOrdered) else {
            let adjacentScreens = AdjacentScreens(prev: firstScreen, next: firstScreen)
            return UsableScreens(currentScreen: firstScreen, adjacentScreens: adjacentScreens, numScreens: screens.count)
        }
        
        let adjacentScreens = adjacent(toFrameOfScreen: sourceScreen.frame, screens: screensOrdered)
        
        return UsableScreens(currentScreen: sourceScreen, adjacentScreens: adjacentScreens, numScreens: screens.count)
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
        if screens.count == 2 {
            let otherScreen = screens.first(where: { screen in
                let frame = NSRectToCGRect(screen.frame)
                return !frame.equalTo(frameOfScreen)
            })
            if let otherScreen = otherScreen {
                return AdjacentScreens(prev: otherScreen, next: otherScreen)
            }
        } else if screens.count > 2 {
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

struct UsableScreens {
    let currentScreen: NSScreen
    let adjacentScreens: AdjacentScreens?
    let frameOfCurrentScreen: CGRect
    var visibleFrameOfCurrentScreen: CGRect
    let numScreens: Int
    
    init(currentScreen: NSScreen, adjacentScreens: AdjacentScreens? = nil, numScreens: Int) {
        self.currentScreen = currentScreen
        self.adjacentScreens = adjacentScreens
        self.frameOfCurrentScreen = currentScreen.frame
        self.visibleFrameOfCurrentScreen = currentScreen.adjustedVisibleFrame
        self.numScreens = numScreens
    }
}

struct AdjacentScreens {
    let prev: NSScreen
    let next: NSScreen
}

extension NSScreen {
    var adjustedVisibleFrame: CGRect {
        get {
            let topGap = CGFloat(Defaults.screenEdgeGapTop.value)
            let bottomGap = CGFloat(Defaults.screenEdgeGapBottom.value)
            let leftGap = CGFloat(Defaults.screenEdgeGapLeft.value)
            var rightGap = CGFloat(Defaults.screenEdgeGapRight.value)
            
            if Defaults.todoMode.enabled && (TodoManager.todoScreen == NSScreen.main) {
                rightGap += CGFloat(Defaults.todoSidebarWidth.value)
            }
            
            let origin = CGPoint(
                x: visibleFrame.origin.x + leftGap,
                y: visibleFrame.origin.y + bottomGap
            )
            let size = CGSize(
                width: visibleFrame.width - leftGap - rightGap,
                height: visibleFrame.height - topGap - bottomGap
            )
            
            return CGRect(origin: origin, size: size)
        }
    }
}
