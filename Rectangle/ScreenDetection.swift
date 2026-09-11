/// ScreenDetection.swift

import Cocoa

class ScreenDetection {

    func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
        let screens = NSScreen.screens
        guard let firstScreen = screens.first else { return nil }
        
        if screens.count == 1 {
            let adjacentScreens = Defaults.traverseSingleScreen.enabled == true
            ? AdjacentScreens(prev: firstScreen, next: firstScreen)
            : nil
            
            return UsableScreens(currentScreen: firstScreen, adjacentScreens: adjacentScreens, numScreens: screens.count, screensOrdered: [firstScreen])
        }
        
        let screensOrdered = order(screens: screens)
        guard let sourceScreen: NSScreen = screenContaining(frontmostWindowElement?.frame ?? CGRect.zero, screens: screensOrdered) else {
            let adjacentScreens = AdjacentScreens(prev: firstScreen, next: firstScreen)
            return UsableScreens(currentScreen: firstScreen, adjacentScreens: adjacentScreens, numScreens: screens.count, screensOrdered: screensOrdered)
        }
        
        let adjacentScreens = adjacent(toFrameOfScreen: sourceScreen.frame, screens: screensOrdered)
        
        return UsableScreens(currentScreen: sourceScreen, adjacentScreens: adjacentScreens, numScreens: screens.count, screensOrdered: screensOrdered)
    }

    func detectScreensAtCursor() -> UsableScreens? {
        let screens = NSScreen.screens
        if screens.count == 1 {
            return detectScreens(using: nil)
        }

        let screensOrdered = order(screens: screens)

        guard let cursorScreen = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation)})
        else {
            return detectScreens(using: nil)
        }

        let adjacentScreens = adjacent(toFrameOfScreen: cursorScreen.frame, screens: screensOrdered)

        return UsableScreens(currentScreen: cursorScreen, adjacentScreens: adjacentScreens, numScreens: screens.count, screensOrdered: screensOrdered)
    }

    func screenContaining(_ rect: CGRect, screens: [NSScreen]) -> NSScreen? {
        var result: NSScreen? = NSScreen.main
        var largestPercentageOfRectWithinFrameOfScreen: CGFloat = 0.0
        for currentScreen in screens {
            let currentFrameOfScreen = NSRectToCGRect(currentScreen.frame)
            let normalizedRect: CGRect = rect.screenFlipped
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
        switch Defaults.screensOrderedByX.value {
            
        case .midX:
            return screens.sorted(by: { $0.frame.midX < $1.frame.midX })
        case .minX:
            return screens.sorted(by: { $0.frame.minX < $1.frame.minX })
        case .yThenMinX:
            let sortedScreens = screens.sorted(by: { screen1, screen2 in
                if screen2.frame.maxY <= screen1.frame.minY {
                    return true
                }
                if screen1.frame.maxY <= screen2.frame.minY {
                    return false
                }
                return screen1.frame.minX < screen2.frame.minX
            })
            return sortedScreens
        }
    }
    
    private func computeAreaOfRect(rect: CGRect) -> CGFloat {
        return rect.size.width * rect.size.height
    }

}

struct UsableScreens {
    let currentScreen: NSScreen
    let adjacentScreens: AdjacentScreens?
    let frameOfCurrentScreen: CGRect
    let numScreens: Int
    let screensOrdered: [NSScreen]

    init(currentScreen: NSScreen, adjacentScreens: AdjacentScreens? = nil, numScreens: Int, screensOrdered: [NSScreen]? = nil) {
        self.currentScreen = currentScreen
        self.adjacentScreens = adjacentScreens
        self.frameOfCurrentScreen = currentScreen.frame
        self.numScreens = numScreens
        self.screensOrdered = screensOrdered ?? [currentScreen]
    }
}

struct AdjacentScreens {
    let prev: NSScreen
    let next: NSScreen
}

enum ScreenOrdering: Int {
    case midX = 1
    case minX = 2
    case yThenMinX = 3
}

enum DockUtil {
    // macOS can leave NSScreen.visibleFrame stale after Dock changes (#467).
    // The Dock's AX list provides a live, fail-closed signal for its current screen and edge.
    private static let bundleIdentifier = "com.apple.dock"
    private static let edgeTolerance: CGFloat = 24
    private static let minimumReliableInset: CGFloat = 8
    private static let maximumInsetRatio: CGFloat = 0.33
    private static var cachedSnapshot: Snapshot?
    private static var snapshotInvalidationPending = false

    private enum Edge: Equatable {
        case left
        case right
        case bottom
    }

    struct Snapshot {
        let screenFrames: [CGRect]
        let dockFrame: CGRect?
        let dockAutoHideEnabled: Bool
    }

    static func snapshot(for screens: [NSScreen]) -> Snapshot {
        let screenFrames = screens.map(\.frame)
        if Thread.isMainThread,
           let cachedSnapshot,
           cachedSnapshot.screenFrames == screenFrames {
            return cachedSnapshot
        }

        let dockIsAutoHidden = dockAutoHideEnabled
        let snapshot = Snapshot(
            screenFrames: screenFrames,
            dockFrame: dockIsAutoHidden ? nil : currentDockFrame(primaryScreenMaxY: screens.first?.frame.maxY),
            dockAutoHideEnabled: dockIsAutoHidden
        )

        // adjustedVisibleFrame can run several times during one action. Reuse its synchronous
        // preference/AX reads until control returns to the main queue, then refresh on the next event.
        if Thread.isMainThread {
            cachedSnapshot = snapshot
            if !snapshotInvalidationPending {
                snapshotInvalidationPending = true
                DispatchQueue.main.async {
                    cachedSnapshot = nil
                    snapshotInvalidationPending = false
                }
            }
        }
        return snapshot
    }

    static func correctedVisibleFrame(for screen: NSScreen, snapshot: Snapshot) -> CGRect {
        let screenFrame = screen.frame
        let reportedVisibleFrame = screen.visibleFrame
        let visibleFrame = correctedVisibleFrame(
            screenFrame: screenFrame,
            visibleFrame: reportedVisibleFrame,
            screenFrames: snapshot.screenFrames,
            dockFrame: snapshot.dockFrame,
            dockAutoHideEnabled: snapshot.dockAutoHideEnabled
        )

        if visibleFrame != reportedVisibleFrame {
            Logger.log("Corrected stale visible screen frame: \(reportedVisibleFrame.debugDescription) -> \(visibleFrame.debugDescription)")
        }
        return visibleFrame
    }

    static func correctedVisibleFrame(screenFrame: CGRect,
                                      visibleFrame: CGRect,
                                      screenFrames: [CGRect],
                                      dockFrame: CGRect?,
                                      dockAutoHideEnabled: Bool) -> CGRect {
        guard !screenFrame.isNull, !visibleFrame.isNull else { return visibleFrame }

        if dockAutoHideEnabled {
            // AppKit can intentionally retain a small boundary used to reveal the hidden Dock.
            return reclaimDockEdges(from: visibleFrame, screenFrame: screenFrame, preservingSmallInsets: true)
        }

        guard
            let dockFrame,
            !dockFrame.isNull,
            dockFrame.width > 0,
            dockFrame.height > 0,
            let dockScreenFrame = dockScreenFrame(for: dockFrame, screenFrames: screenFrames),
            let edge = dockEdge(for: dockFrame, screenFrame: dockScreenFrame)
        else {
            return visibleFrame
        }

        let dockInset = dockInset(for: dockFrame, screenFrame: dockScreenFrame, edge: edge)
        let maximumInset = (edge == .bottom ? dockScreenFrame.height : dockScreenFrame.width) * maximumInsetRatio
        guard dockInset > 0.5, dockInset <= maximumInset else { return visibleFrame }

        guard screenFrame.equalTo(dockScreenFrame) else {
            return reclaimDockEdges(from: visibleFrame, screenFrame: screenFrame)
        }

        let reportedInset = reportedInset(for: visibleFrame, screenFrame: screenFrame, edge: edge)
        // AXList bounds describe the Dock's tiles rather than its exact reserved area.
        // Preserve a plausible AppKit inset and use AX only to recover one that is missing.
        let correctedInset = reportedInset > minimumReliableInset
            ? reportedInset
            : dockInset

        var correctedFrame = reclaimDockEdges(from: visibleFrame, screenFrame: screenFrame)
        let correctedMaxY = correctedFrame.maxY
        switch edge {
        case .left:
            correctedFrame.origin.x = screenFrame.minX + correctedInset
            correctedFrame.size.width = screenFrame.maxX - correctedFrame.minX
        case .right:
            correctedFrame.size.width = screenFrame.maxX - correctedInset - correctedFrame.minX
        case .bottom:
            correctedFrame.origin.y = screenFrame.minY + correctedInset
            correctedFrame.size.height = correctedMaxY - correctedFrame.minY
        }

        guard correctedFrame.width > 0, correctedFrame.height > 0 else { return visibleFrame }
        return correctedFrame
    }

    private static var dockAutoHideEnabled: Bool {
        let domain = bundleIdentifier as CFString
        _ = CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool ?? false
    }

    private static func currentDockFrame(primaryScreenMaxY: CGFloat?) -> CGRect? {
        guard let primaryScreenMaxY else { return nil }
        guard let dockElement = AccessibilityElement(bundleIdentifier) else { return nil }
        dockElement.setMessagingTimeout(0.1)
        guard let dockListElement = dockElement.getChildElement(.list) else { return nil }
        dockListElement.setMessagingTimeout(0.1)
        let frame = dockListElement.frame
        guard !frame.isNull else { return nil }
        return CGRect(x: frame.minX, y: primaryScreenMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func dockScreenFrame(for dockFrame: CGRect, screenFrames: [CGRect]) -> CGRect? {
        let candidates = screenFrames
            .compactMap { screenFrame -> (frame: CGRect, overlap: CGFloat)? in
                let intersection = screenFrame.intersection(dockFrame)
                guard !intersection.isNull else { return nil }
                return (screenFrame, intersection.width * intersection.height)
            }
            .sorted { $0.overlap > $1.overlap }

        guard
            let candidate = candidates.first,
            candidate.overlap >= dockFrame.width * dockFrame.height * 0.5
        else {
            return nil
        }
        if candidates.count > 1, abs(candidate.overlap - candidates[1].overlap) < 1 {
            return nil
        }
        return candidate.frame
    }

    private static func dockEdge(for dockFrame: CGRect, screenFrame: CGRect) -> Edge? {
        let intersection = screenFrame.intersection(dockFrame)
        guard !intersection.isNull else { return nil }

        if intersection.width >= intersection.height,
           intersection.minY - screenFrame.minY <= edgeTolerance {
            return .bottom
        }
        if intersection.height > intersection.width {
            if intersection.minX - screenFrame.minX <= edgeTolerance {
                return .left
            }
            if screenFrame.maxX - intersection.maxX <= edgeTolerance {
                return .right
            }
        }
        return nil
    }

    private static func dockInset(for dockFrame: CGRect, screenFrame: CGRect, edge: Edge) -> CGFloat {
        switch edge {
        case .left:
            return max(0, dockFrame.maxX - screenFrame.minX)
        case .right:
            return max(0, screenFrame.maxX - dockFrame.minX)
        case .bottom:
            return max(0, dockFrame.maxY - screenFrame.minY)
        }
    }

    private static func reportedInset(for visibleFrame: CGRect, screenFrame: CGRect, edge: Edge) -> CGFloat {
        switch edge {
        case .left:
            return max(0, visibleFrame.minX - screenFrame.minX)
        case .right:
            return max(0, screenFrame.maxX - visibleFrame.maxX)
        case .bottom:
            return max(0, visibleFrame.minY - screenFrame.minY)
        }
    }

    private static func reclaimDockEdges(from visibleFrame: CGRect,
                                         screenFrame: CGRect,
                                         preservingSmallInsets: Bool = false) -> CGRect {
        let leftInset = reportedInset(for: visibleFrame, screenFrame: screenFrame, edge: .left)
        let rightInset = reportedInset(for: visibleFrame, screenFrame: screenFrame, edge: .right)
        let bottomInset = reportedInset(for: visibleFrame, screenFrame: screenFrame, edge: .bottom)
        let preservedLeftInset = preservingSmallInsets && leftInset <= minimumReliableInset ? leftInset : 0
        let preservedRightInset = preservingSmallInsets && rightInset <= minimumReliableInset ? rightInset : 0
        let preservedBottomInset = preservingSmallInsets && bottomInset <= minimumReliableInset ? bottomInset : 0
        // The Dock cannot reserve the top edge. Preserve AppKit's menu bar/notch boundary there.
        let maxY = min(visibleFrame.maxY, screenFrame.maxY)
        let minY = screenFrame.minY + preservedBottomInset
        let width = screenFrame.width - preservedLeftInset - preservedRightInset
        guard maxY > minY, width > 0 else { return visibleFrame }
        return CGRect(x: screenFrame.minX + preservedLeftInset,
                      y: minY,
                      width: width,
                      height: maxY - minY)
    }
}

extension NSScreen {

    func adjustedVisibleFrame(_ ignoreTodo: Bool = false, _ ignoreStage: Bool = false) -> CGRect {
        let screens = NSScreen.screens
        let dockSnapshot = DockUtil.snapshot(for: screens)
        var newFrame: CGRect

        if !NSScreen.screensHaveSeparateSpaces && Defaults.combinedDisplayMode.userEnabled {
            let combinedScreenFrame = dockSnapshot.screenFrames.reduce(CGRect.null) { $0.union($1) }
            let combinedVisibleFrame = screens.reduce(CGRect.null) {
                $0.union(DockUtil.correctedVisibleFrame(for: $1, snapshot: dockSnapshot))
            }
            newFrame = DockUtil.correctedVisibleFrame(
                screenFrame: combinedScreenFrame,
                visibleFrame: combinedVisibleFrame,
                screenFrames: [combinedScreenFrame],
                dockFrame: dockSnapshot.dockFrame,
                dockAutoHideEnabled: dockSnapshot.dockAutoHideEnabled
            )
        } else {
            newFrame = DockUtil.correctedVisibleFrame(for: self, snapshot: dockSnapshot)
        }

        if !ignoreStage && Defaults.stageSize.value > 0 {
            if StageUtil.stageCapable && StageUtil.stageEnabled && StageUtil.stageStripShow && StageUtil.isStageStripVisible(self) {
                let stageSize = Defaults.stageSize.value < 1
                    ? newFrame.size.width * Defaults.stageSize.cgFloat
                    : Defaults.stageSize.cgFloat
                
                if StageUtil.stageStripPosition == .left {
                    newFrame.origin.x += stageSize
                }
                newFrame.size.width -= stageSize
            }
        }
        
        if !ignoreTodo, Defaults.todo.userEnabled, Defaults.todoMode.enabled, TodoManager.todoScreen == self, TodoManager.hasTodoWindow() {
            let sidebarWidth = TodoManager.getSidebarWidth(visibleFrameWidth: newFrame.width)
            newFrame.size.width -= sidebarWidth
            if Defaults.todoSidebarSide.value == .left {
                newFrame.origin.x += sidebarWidth
            }
        }

        if Defaults.screenEdgeGapsOnMainScreenOnly.enabled, self != NSScreen.screens.first {
            return newFrame
        }

        newFrame.origin.x += Defaults.screenEdgeGapLeft.cgFloat
        newFrame.origin.y += Defaults.screenEdgeGapBottom.cgFloat
        newFrame.size.width -= (Defaults.screenEdgeGapLeft.cgFloat + Defaults.screenEdgeGapRight.cgFloat)
        
        if #available(macOS 12.0, *), self.safeAreaInsets.top != 0, Defaults.screenEdgeGapTopNotch.value != 0 {
            newFrame.size.height -= (Defaults.screenEdgeGapTopNotch.cgFloat + Defaults.screenEdgeGapBottom.cgFloat)
        } else {
            newFrame.size.height -= (Defaults.screenEdgeGapTop.cgFloat + Defaults.screenEdgeGapBottom.cgFloat)
        }
        
        return newFrame
    }

    static var portraitDisplayConnected: Bool {
        NSScreen.screens.contains(where: {!$0.frame.isLandscape})
    }
}
