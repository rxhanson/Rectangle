/// MultiWindowManager.swift

import Cocoa
import MASShortcut

class MultiWindowManager {
    typealias BandDirection = GridTiling.Direction
    typealias BandConstraint = GridTiling.Constraint
    typealias BackingPixelBounds = GridTiling.Bounds

    private static var gridStates = [NSScreen: GridTiling.State<AccessibilityElement>]()

    struct TilingWindow {
        let element: AccessibilityElement
        let frame: CGRect
        let windowId: CGWindowID?
        let pid: pid_t?
        let isFocused: Bool
    }

    static func execute(parameters: ExecutionParameters) -> Bool {
        // TODO: Protocol and factory for all multi-window positioning algorithms
        switch parameters.action {
        case .reverseAll:
            ReverseAllManager.reverseAll(windowElement: parameters.windowElement)
            return true
        case .tileAll:
            tileAllWindowsOnScreen()
            return true
        case .tileRows:
            tileWindowsInBands(.rows)
            return true
        case .tileColumns:
            tileWindowsInBands(.columns)
            return true
        case .cascadeAll:
            cascadeAllWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .cascadeActiveApp:
            cascadeActiveAppWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        case .tileActiveApp:
            tileActiveAppWindowsOnScreen(windowElement: parameters.windowElement)
            return true
        default:
            return false
        }
    }

    private static func allWindowsOnScreen(windowElement: AccessibilityElement? = nil, sortByPID: Bool = false) -> (screens: UsableScreens, windows: [AccessibilityElement])? {
        let screenDetection = ScreenDetection()

        guard let windowElement = windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let screens = screenDetection.detectScreens(using: windowElement)
        else {
            NSSound.beep()
            Logger.log("Can't detect screen for multiple windows")
            return nil
        }

        return windowsOnScreen(screens: screens, windows: AccessibilityElement.getAllWindowElements(),
                               sortByPID: sortByPID,
                               screenFor: { screenDetection.detectScreens(using: $0)?.currentScreen })
    }

    private static func isActiveTodoWindow(_ window: AccessibilityElement) -> Bool {
        Defaults.todo.userEnabled && TodoManager.isTodoWindow(window)
    }

    static func windowsOnScreen(screens: UsableScreens, windows: [AccessibilityElement],
                                focusedWindow: AccessibilityElement? = nil,
                                sortByPID: Bool = false, combineScreens: Bool = false,
                                isActiveTodoWindow: (AccessibilityElement) -> Bool = MultiWindowManager.isActiveTodoWindow,
                                screenFor: (AccessibilityElement) -> NSScreen?) -> (screens: UsableScreens, windows: [AccessibilityElement]) {
        var windows = windows
        // Focus is known even when CG omits its app, but still obeys the display
        // and Todo exclusions applied to every other candidate.
        if let focusedWindow, !windows.contains(focusedWindow) {
            windows.append(focusedWindow)
        }
        if sortByPID {
            windows.sort(by: { (w1: AccessibilityElement, w2: AccessibilityElement) -> Bool in
                w1.pid ?? pid_t(0) > w2.pid ?? pid_t(0)
            })
        }

        var actualWindows = [AccessibilityElement]()
        for w in windows {
            if isActiveTodoWindow(w) { continue }
            if combineScreens || screenFor(w) == screens.currentScreen,
               w.isWindow == true,
               w.isSheet != true,
               w.isMinimized != true,
               w.isHidden != true,
               w.isSystemDialog != true
            {
                actualWindows.append(w)
            }
        }

        return (screens, actualWindows)
    }

    static func tilingContext(focusedWindow: AccessibilityElement?,
                              screenDetection: ScreenDetection) -> (focusedWindow: AccessibilityElement?, screens: UsableScreens)? {
        let eligibleFocus: AccessibilityElement?
        if let focusedWindow,
              focusedWindow.isWindow == true,
              focusedWindow.isSheet != true,
              focusedWindow.isMinimized != true,
              focusedWindow.isHidden != true,
              focusedWindow.isSystemDialog != true,
              !focusedWindow.frame.isNull {
            eligibleFocus = focusedWindow
        } else {
            eligibleFocus = nil
        }

        let screens: UsableScreens?
        if let eligibleFocus {
            screens = screenDetection.detectScreens(using: eligibleFocus)
        } else {
            screens = screenDetection.detectScreensAtCursor()
        }

        return screens.map { (eligibleFocus, $0) }
    }

    private static func tileWindowsInBands(_ direction: BandDirection) {
        let screenDetection = ScreenDetection()
        guard let context = tilingContext(focusedWindow: AccessibilityElement.getFocusedWindowElement(),
                                          screenDetection: screenDetection) else { return }

        // Reuse this new on-screen snapshot for AX app discovery and for Space
        // membership, even when another tiling action just moved windows.
        let visibleInfo = WindowUtil.getWindowList(forceRefresh: true)
        let windows = windowsOnScreen(screens: context.screens,
                                      windows: AccessibilityElement.getAllWindowElements(from: visibleInfo),
                                      focusedWindow: context.focusedWindow,
                                      combineScreens: !NSScreen.screensHaveSeparateSpaces && Defaults.combinedDisplayMode.userEnabled,
                                      screenFor: { screenDetection.detectScreens(using: $0)?.currentScreen }).windows

        tileWindowsInBands(direction, focusedWindow: context.focusedWindow, windows: windows,
                           visibleWindowInfo: visibleInfo, screen: context.screens.currentScreen,
                           visibleFrame: context.screens.currentScreen.adjustedVisibleFrame())
    }

    static func tileWindowsInBands(_ direction: BandDirection, focusedWindow: AccessibilityElement?,
                                    windows: [AccessibilityElement], visibleWindowInfo: [WindowInfo],
                                    screen: NSScreen, visibleFrame: CGRect) {
        guard focusedWindow?.frame.screenFlipped.intersects(screen.frame) != false else { return }

        let snapshots = windows.compactMap { window -> TilingWindow? in
            let frame = window.frame
            guard !frame.isNull else { return nil }
            return TilingWindow(element: window,
                                frame: frame,
                                windowId: window.windowId,
                                pid: window.pid,
                                isFocused: window == focusedWindow)
        }

        let currentSpaceWindows = selectCurrentSpaceWindows(snapshots, visibleWindowInfo: visibleWindowInfo,
                                                           frameTolerance: 1 / max(1, screen.backingScaleFactor))
        let ordered = orderForBandTiling(currentSpaceWindows, direction: direction)
        guard !ordered.isEmpty else { return }

        let bounds = BackingPixelBounds(screen.convertRectToBacking(visibleFrame))
        guard bounds.extent(.rows) > 0, bounds.extent(.columns) > 0 else { return }

        let constraints = ordered.map { candidate -> GridTiling.WindowConstraints in
            let isResizable = candidate.element.isResizable()
            let size = isResizable ? (candidate.element.minimumSize ?? .zero) : candidate.frame.size
            let backingSize = screen.convertRectToBacking(CGRect(origin: .zero, size: size)).size
            func constraint(_ size: CGFloat, maximum: Int) -> GridTiling.Constraint {
                let pixels = max(0, Int(isResizable ? ceil(size) : size.rounded()))
                return isResizable ? .resizable(minimum: pixels, maximum: maximum) : .fixed(pixels)
            }
            return GridTiling.WindowConstraints(width: constraint(backingSize.width, maximum: bounds.extent(.columns)),
                                                height: constraint(backingSize.height, maximum: bounds.extent(.rows)))
        }

        let limit = direction == .rows ? Defaults.tileRowsMaxWindows.value : Defaults.tileColumnsMaxWindows.value
        let observed = ordered.map { BackingPixelBounds(screen.convertRectToBacking($0.frame.screenFlipped)).rect }
        gridStates[screen] = GridTiling.perform(windows: ordered.map(\.element), observedFrames: observed,
                                               bounds: bounds, direction: direction, limit: limit,
                                               constraints: constraints, previous: gridStates[screen]) { index, frame in
            let window = ordered[index].element
            window.setFrame(screen.convertRectFromBacking(frame).screenFlipped)
            let achieved = window.frame
            return achieved.isNull ? .null : BackingPixelBounds(screen.convertRectToBacking(achieved.screenFlipped)).rect
        }
    }

    /// On-screen CG records supply current-Space evidence. Raw IDs are exact;
    /// ID-less windows enter only if every maximum one-to-one PID/frame match
    /// uses them. Focus is independently known but still competes for CG evidence.
    /// Identical PID/frame records without IDs cannot prove actual identity.
    static func selectCurrentSpaceWindows(_ snapshots: [TilingWindow], visibleWindowInfo: [WindowInfo],
                                          frameTolerance: CGFloat = 1) -> [TilingWindow] {
        let visibleIds = Set(visibleWindowInfo.map(\.id))
        let identifiedIds = Set(snapshots.compactMap(\.windowId)).intersection(visibleIds)
        var seenVisibleIds = Set<CGWindowID>()
        let unmatchedVisible = visibleWindowInfo.filter {
            !identifiedIds.contains($0.id) && seenVisibleIds.insert($0.id).inserted
        }
        let idlessIndices = snapshots.indices.filter {
            snapshots[$0].windowId == nil && snapshots[$0].pid != nil
        }
        let matches = idlessIndices.map { index in
            unmatchedVisible.indices.filter { cgIndex in
                let info = unmatchedVisible[cgIndex]
                return info.pid == snapshots[index].pid
                    && framesMatch(info.frame, snapshots[index].frame, tolerance: frameTolerance)
            }
        }

        // -1 marks a vertex that has no partner in the current matching.
        var matchedAXForCG = [Int](repeating: -1, count: unmatchedVisible.count)
        func augment(_ ax: Int, seenCG: inout [Bool], matchedAXForCG: inout [Int]) -> Bool {
            for cg in matches[ax] {
                if seenCG[cg] {
                    continue
                } else {
                    seenCG[cg] = true
                    let previousAX = matchedAXForCG[cg]
                    if previousAX == -1 || augment(previousAX, seenCG: &seenCG, matchedAXForCG: &matchedAXForCG) {
                        matchedAXForCG[cg] = ax
                        return true
                    }
                }
            }
            return false
        }
        for ax in matches.indices {
            var seenCG = [Bool](repeating: false, count: unmatchedVisible.count)
            _ = augment(ax, seenCG: &seenCG, matchedAXForCG: &matchedAXForCG)
        }

        var matchedCGForAX = [Int](repeating: -1, count: matches.count)
        for (cg, ax) in matchedAXForCG.enumerated() where ax >= 0 {
            matchedCGForAX[ax] = cg
        }

        // Alternating paths from unmatched AX windows reach every AX window
        // that another equally large assignment could leave unmatched.
        var optionalAX = [Bool](repeating: false, count: matches.count)
        var queue = matches.indices.filter { matchedCGForAX[$0] == -1 }
        for ax in queue {
            optionalAX[ax] = true
        }
        var next = 0
        while next < queue.count {
            let ax = queue[next]
            next += 1
            for cg in matches[ax] where cg != matchedCGForAX[ax] {
                let otherAX = matchedAXForCG[cg]
                if otherAX >= 0 && !optionalAX[otherAX] {
                    optionalAX[otherAX] = true
                    queue.append(otherAX)
                }
            }
        }

        var established = [Bool](repeating: false, count: snapshots.count)
        for ax in matches.indices where matchedCGForAX[ax] >= 0 && !optionalAX[ax] {
            established[idlessIndices[ax]] = true
        }
        return snapshots.enumerated().compactMap { index, candidate in
            if candidate.isFocused {
                return candidate
            } else if let windowId = candidate.windowId {
                return visibleIds.contains(windowId) ? candidate : nil
            } else if established[index] {
                return candidate
            } else {
                return nil
            }
        }
    }

    private static func framesMatch(_ first: CGRect, _ second: CGRect, tolerance: CGFloat) -> Bool {
        let tolerance = max(0, tolerance)
        // AX and CG can round position and size independently. Comparing far
        // edges would add those errors and reject an otherwise matching frame.
        return abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance
            && abs(first.height - second.height) <= tolerance
    }

    static func orderForBandTiling(_ windows: [TilingWindow], direction: BandDirection) -> [TilingWindow] {
        windows.sorted { first, second in
            let firstPrimary = direction == .rows ? first.frame.minY : first.frame.minX
            let secondPrimary = direction == .rows ? second.frame.minY : second.frame.minX
            let firstSecondary = direction == .rows ? first.frame.minX : first.frame.minY
            let secondSecondary = direction == .rows ? second.frame.minX : second.frame.minY
            if firstPrimary != secondPrimary {
                return firstPrimary < secondPrimary
            } else {
                return firstSecondary < secondSecondary
            }
        }
    }

    static func tileAllWindowsOnScreen() {
        let screenDetection = ScreenDetection()
        guard let context = tilingContext(focusedWindow: AccessibilityElement.getFocusedWindowElement(),
                                          screenDetection: screenDetection) else { return }
        let windows = windowsOnScreen(screens: context.screens,
                                      windows: AccessibilityElement.getAllWindowElements(),
                                      sortByPID: true,
                                      screenFor: { screenDetection.detectScreens(using: $0)?.currentScreen }).windows
        tileAllWindowsOnScreen(windows: windows, screen: context.screens.currentScreen)
    }

    static func tileAllWindowsOnScreen(windows: [AccessibilityElement], screen: NSScreen) {
        guard !windows.isEmpty else { return }

        tileWindows(windows, in: screen.adjustedVisibleFrame().screenFlipped)
    }

    private static func tileWindows(_ windows: [AccessibilityElement], in bounds: CGRect) {
        guard !windows.isEmpty else { return }
        WindowSizeConstraints.shared.cancelPendingObservations()
        let minima = windows.map { $0.isResizable() ? $0.minimumSize : $0.frame.size }
        guard let frames = WindowSizeConstraints.tileFrames(in: bounds, minimumSizes: minima) else {
            NSSound.beep(); Logger.log("Known window minimum sizes do not fit the tile area"); return
        }
        for (window, frame) in zip(windows, frames) { window.setFrame(frame) }
    }

    static func cascadeAllWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true) else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)

        for (ind, w) in windows.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind)
        }
    }

    private struct CascadeActiveAppParameters {
        let right: Bool
        let bottom: Bool
        let numWindows: Int
        let size: CGSize

        init(windowFrame: CGRect, screenFrame: CGRect, numWindows: Int, size: CGSize, delta: CGFloat) {
            right = windowFrame.midX > screenFrame.midX
            bottom = windowFrame.midY > screenFrame.midY
            self.numWindows = numWindows
            let maxSize = CGSize(width: screenFrame.width - CGFloat(numWindows - 1) * delta, height: screenFrame.height - CGFloat(numWindows - 1) * delta)
            self.size = CGSize(width: min(size.width, maxSize.width), height: min(size.height, maxSize.height))
        }
    }

    static func cascadeActiveAppWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true),
              let frontWindowElement = AccessibilityElement.getFrontWindowElement()
        else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        let delta = CGFloat(Defaults.cascadeAllDeltaSize.value)

        // keep windows with a pid equal to the front window's pid
        var filtered = windows.filter(hasFrontWindowPid(_:))

        // parameters for cascading active app windows
        var cascadeParameters: CascadeActiveAppParameters?

        if let first = filtered.first {
            // move the first to become the last (top)
            filtered.append(filtered.removeFirst())
            // set up parameters
            cascadeParameters = CascadeActiveAppParameters(windowFrame: first.frame, screenFrame: screenFrame, numWindows: filtered.count, size: first.size!, delta: delta)
        }

        // cascade the filtered windows
        for (ind, w) in filtered.enumerated() {
            cascadeWindow(w, screenFrame: screenFrame, delta: delta, index: ind, cascadeParameters: cascadeParameters)
        }

        // return true for a w pid equal to the front window's pid
        func hasFrontWindowPid(_ w: AccessibilityElement) -> Bool {
            return w.pid == frontWindowElement.pid
        }
    }

    private static func cascadeWindow(_ w: AccessibilityElement, screenFrame: CGRect, delta: CGFloat, index: Int, cascadeParameters: CascadeActiveAppParameters? = nil) {
        var rect = w.frame

        // TODO: save previous position in history

        rect.origin.x = screenFrame.origin.x + delta * CGFloat(index)
        rect.origin.y = screenFrame.origin.y + delta * CGFloat(index)

        if let cascadeParameters {
            rect.size.width = cascadeParameters.size.width
            rect.size.height = cascadeParameters.size.height

            if cascadeParameters.right {
                rect.origin.x = screenFrame.origin.x + screenFrame.size.width - cascadeParameters.size.width - delta * CGFloat(index)
            }
            if cascadeParameters.bottom {
                rect.origin.y = screenFrame.origin.y + screenFrame.size.height - cascadeParameters.size.height - delta * CGFloat(cascadeParameters.numWindows - 1 - index)
            }
        }

        guard WindowSizeConstraints.shared.place(w, target: rect, in: screenFrame) else { return }
        w.bringToFront()
    }

    static func tileActiveAppWindowsOnScreen(windowElement: AccessibilityElement? = nil) {
        guard let (screens, windows) = allWindowsOnScreen(windowElement: windowElement, sortByPID: true),
              let frontWindowElement = AccessibilityElement.getFrontWindowElement()
        else {
            return
        }

        let screenFrame = screens.currentScreen.adjustedVisibleFrame().screenFlipped

        // keep windows with a pid equal to the front window's pid
        let filtered = windows.filter { $0.pid == frontWindowElement.pid }

        tileWindows(filtered, in: screenFrame)
    }
}
