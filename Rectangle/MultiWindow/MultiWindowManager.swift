/// MultiWindowManager.swift

import Cocoa
import MASShortcut

class MultiWindowManager {
    enum BandDirection {
        case rows, columns
    }

    struct TilingWindow {
        let element: AccessibilityElement
        let frame: CGRect
        let windowId: CGWindowID?
        let pid: pid_t?
        let isFocused: Bool
    }

    enum BandConstraint: Equatable {
        case fixed(Int)
        case resizable(minimum: Int, maximum: Int)

        var lowerBound: Int {
            switch self {
            case .fixed(let size):
                return max(0, size)
            case .resizable(let minimum, _):
                return max(0, minimum)
            }
        }

        var upperBound: Int {
            switch self {
            case .fixed(let size):
                return max(0, size)
            case .resizable(_, let maximum):
                return max(0, maximum)
            }
        }

        func observing(achieved: Int, requested: Int) -> BandConstraint {
            switch self {
            case .fixed:
                return self
            case .resizable(let minimum, let maximum):
                let lower = achieved > requested ? max(minimum, achieved) : minimum
                let upper = achieved < requested ? min(maximum, achieved) : maximum
                return lower <= upper ? .resizable(minimum: lower, maximum: upper) : self
            }
        }
    }

    struct BackingPixelBounds {
        let left: Int
        let right: Int
        let bottom: Int
        let top: Int

        init(_ frame: CGRect) {
            left = Int(frame.minX.rounded())
            right = Int(frame.maxX.rounded())
            bottom = Int(frame.minY.rounded())
            top = Int(frame.maxY.rounded())
        }

        func extent(_ direction: BandDirection) -> Int {
            direction == .rows ? top - bottom : right - left
        }
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

    private static func allWindowsOnScreen(windowElement: AccessibilityElement? = nil, sortByPID: Bool = false, includeTodoWindow: Bool = false) -> (screens: UsableScreens, windows: [AccessibilityElement])? {
        let screenDetection = ScreenDetection()

        guard let windowElement = windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let screens = screenDetection.detectScreens(using: windowElement)
        else {
            NSSound.beep()
            Logger.log("Can't detect screen for multiple windows")
            return nil
        }

        return windowsOnScreen(screens: screens, windows: AccessibilityElement.getAllWindowElements(),
                               sortByPID: sortByPID, includeTodoWindow: includeTodoWindow,
                               screenFor: { screenDetection.detectScreens(using: $0)?.currentScreen })
    }

    private static func isActiveTodoWindow(_ window: AccessibilityElement) -> Bool {
        Defaults.todo.userEnabled && TodoManager.isTodoWindow(window)
    }

    static func windowsOnScreen(screens: UsableScreens, windows: [AccessibilityElement],
                                sortByPID: Bool = false, includeTodoWindow: Bool = false,
                                isActiveTodoWindow: (AccessibilityElement) -> Bool = MultiWindowManager.isActiveTodoWindow,
                                screenFor: (AccessibilityElement) -> NSScreen?) -> (screens: UsableScreens, windows: [AccessibilityElement]) {
        var windows = windows
        if sortByPID {
            windows.sort(by: { (w1: AccessibilityElement, w2: AccessibilityElement) -> Bool in
                w1.pid ?? pid_t(0) > w2.pid ?? pid_t(0)
            })
        }

        var actualWindows = [AccessibilityElement]()
        for w in windows {
            if !includeTodoWindow, isActiveTodoWindow(w) { continue }
            if screenFor(w) == screens.currentScreen,
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
                                      includeTodoWindow: true,
                                      screenFor: { screenDetection.detectScreens(using: $0)?.currentScreen }).windows

        tileWindowsInBands(direction, focusedWindow: context.focusedWindow, windows: windows,
                           visibleWindowInfo: visibleInfo, screen: context.screens.currentScreen)
    }

    static func tileWindowsInBands(_ direction: BandDirection, focusedWindow: AccessibilityElement?,
                                   windows: [AccessibilityElement], visibleWindowInfo: [WindowInfo],
                                   screen: NSScreen) {
        guard focusedWindow?.frame.screenFlipped.intersects(screen.frame) != false else { return }

        var snapshots = windows.compactMap { window -> TilingWindow? in
            let frame = window.frame
            guard !frame.isNull else { return nil }
            return TilingWindow(element: window,
                                frame: frame,
                                windowId: window.windowId,
                                pid: window.pid,
                                isFocused: window == focusedWindow)
        }

        // App discovery starts with CG's on-screen process list. The focused
        // AX window is independently known to be present even if CG omits it.
        if let focusedWindow, !snapshots.contains(where: \.isFocused) {
            snapshots.append(TilingWindow(element: focusedWindow,
                                          frame: focusedWindow.frame,
                                          windowId: focusedWindow.windowId,
                                          pid: focusedWindow.pid,
                                          isFocused: true))
        }

        let currentSpaceWindows = selectCurrentSpaceWindows(snapshots, visibleWindowInfo: visibleWindowInfo,
                                                           frameTolerance: 1 / max(1, screen.backingScaleFactor))
        let ordered = orderForBandTiling(currentSpaceWindows, direction: direction)
        guard !ordered.isEmpty else { return }

        let visibleFrame = screen.singleDisplayTilingFrame()
        let bounds = BackingPixelBounds(screen.convertRectToBacking(visibleFrame))
        let totalPixels = bounds.extent(direction)
        guard totalPixels > 0 else { return }

        let constraints = ordered.map { candidate -> BandConstraint in
            let isResizable = candidate.element.isResizable()
            let size = isResizable ? (candidate.element.minimumSize ?? .zero) : candidate.frame.size
            let backingSize = screen.convertRectToBacking(CGRect(origin: .zero, size: size)).size
            let axisSize = direction == .rows ? backingSize.height : backingSize.width
            let pixels = max(0, Int(isResizable ? ceil(axisSize) : axisSize.rounded()))
            return isResizable
                ? .resizable(minimum: pixels, maximum: totalPixels)
                : .fixed(pixels)
        }

        applyBandTiling(ordered, bounds: bounds, direction: direction, constraints: constraints,
                        pointFrame: { screen.convertRectFromBacking($0).screenFlipped },
                        backingFrame: { screen.convertRectToBacking($0.screenFlipped) })
    }

    static func applyBandTiling(_ ordered: [TilingWindow],
                                bounds: BackingPixelBounds,
                                direction: BandDirection,
                                constraints initialConstraints: [BandConstraint],
                                pointFrame: (CGRect) -> CGRect,
                                backingFrame: (CGRect) -> CGRect) {
        var constraints = initialConstraints
        let totalPixels = bounds.extent(direction)
        var lastRequestedFrames = [CGRect?](repeating: nil, count: ordered.count)

        // A clamp changes the remaining targets now and earlier targets on the
        // next pass. Avoid repeating a frame request that was already made.
        for _ in 0..<(2 * ordered.count + 1) {
            var allocation = balancedBandLengths(totalPixels: totalPixels, constraints: constraints)
            var frames = backingBandRects(bounds: bounds, lengths: allocation.lengths, direction: direction)
            var learnedConstraint = false
            var infeasibleConstraint = false
            for (index, candidate) in ordered.enumerated() {
                let targetFrame = pointFrame(frames[index])
                if lastRequestedFrames[index] != targetFrame {
                    candidate.element.setFrame(targetFrame)
                    lastRequestedFrames[index] = targetFrame
                    if allocation.feasible && !infeasibleConstraint {
                        let achievedFrame = candidate.element.frame
                        if !achievedFrame.isNull {
                            let backingSize = backingFrame(achievedFrame).size
                            let achieved = max(0, Int((direction == .rows ? backingSize.height : backingSize.width).rounded()))
                            let revised = constraints[index].observing(achieved: achieved,
                                                                       requested: allocation.lengths[index])
                            if revised != constraints[index] {
                                var candidateConstraints = constraints
                                candidateConstraints[index] = revised
                                let candidateAllocation = balancedBandLengths(totalPixels: totalPixels,
                                                                              constraints: candidateConstraints)
                                if candidateAllocation.feasible {
                                    constraints = candidateConstraints
                                    allocation = candidateAllocation
                                    frames = backingBandRects(bounds: bounds, lengths: allocation.lengths,
                                                              direction: direction)
                                    learnedConstraint = true
                                } else {
                                    infeasibleConstraint = true
                                }
                            }
                        }
                    }
                }
            }

            if !allocation.feasible || !learnedConstraint {
                break
            }
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
        return abs(first.minX - second.minX) <= tolerance
            && abs(first.minY - second.minY) <= tolerance
            && abs(first.maxX - second.maxX) <= tolerance
            && abs(first.maxY - second.maxY) <= tolerance
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

    static func backingBandRects(bounds: BackingPixelBounds, lengths: [Int], direction: BandDirection) -> [CGRect] {
        var next = direction == .rows ? bounds.top : bounds.left
        return lengths.map { length in
            if direction == .rows {
                next -= length
                return CGRect(x: bounds.left, y: next, width: bounds.right - bounds.left, height: length)
            } else {
                let rect = CGRect(x: next, y: bounds.bottom, width: length, height: bounds.top - bounds.bottom)
                next += length
                return rect
            }
        }
    }

    /// Equalize flexible bands within observed limits, retaining exact fixed
    /// extents when feasible. Infeasible restrictions use equal targets for every window.
    static func balancedBandLengths(totalPixels: Int, constraints: [BandConstraint]) -> (lengths: [Int], feasible: Bool) {
        guard !constraints.isEmpty, totalPixels > 0 else { return ([], false) }
        let count = constraints.count
        let equal = (0..<count).map { totalPixels / count + ($0 < totalPixels % count ? 1 : 0) }
        let lower = constraints.map(\.lowerBound)
        let upper = constraints.map(\.upperBound)
        guard zip(lower, upper).allSatisfy({ pair in pair.0 <= pair.1 }),
              lower.reduce(0, +) <= totalPixels,
              upper.reduce(0, +) >= totalPixels
        else { return (equal, false) }

        var low = 0
        var high = totalPixels
        while low < high {
            let middle = low + (high - low + 1) / 2
            let required = zip(lower, upper).reduce(0) { $0 + min($1.1, max($1.0, middle)) }
            if required <= totalPixels {
                low = middle
            } else {
                high = middle - 1
            }
        }

        var lengths = zip(lower, upper).map { min($0.1, max($0.0, low)) }
        var remainder = totalPixels - lengths.reduce(0, +)
        // Bands held above the water level by a minimum are already larger.
        for index in lengths.indices where lengths[index] == low && lengths[index] < upper[index] && remainder > 0 {
            lengths[index] += 1
            remainder -= 1
        }
        return (lengths, true)
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

        let screenFrame = screen.adjustedVisibleFrame().screenFlipped
        let count = windows.count

        let columns = Int(ceil(sqrt(CGFloat(count))))
        let rows = Int(ceil(CGFloat(count) / CGFloat(columns)))
        let size = CGSize(width: (screenFrame.maxX - screenFrame.minX) / CGFloat(columns), height: (screenFrame.maxY - screenFrame.minY) / CGFloat(rows))

        for (ind, w) in windows.enumerated() {
            let column = ind % Int(columns)
            let row = ind / Int(columns)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
    }

    private static func tileWindow(_ w: AccessibilityElement, screenFrame: CGRect, size: CGSize, column: Int, row: Int) {
        var rect = w.frame

        // TODO: save previous position in history

        rect.origin.x = screenFrame.origin.x + size.width * CGFloat(column)
        rect.origin.y = screenFrame.origin.y + size.height * CGFloat(row)
        rect.size = size

        w.setFrame(rect)
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

        w.setFrame(rect)
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

        let count = filtered.count

        let columns = Int(ceil(sqrt(CGFloat(count))))
        let rows = Int(ceil(CGFloat(count) / CGFloat(columns)))
        let size = CGSize(width: (screenFrame.maxX - screenFrame.minX) / CGFloat(columns), height: (screenFrame.maxY - screenFrame.minY) / CGFloat(rows))

        for (ind, w) in filtered.enumerated() {
            let column = ind % Int(columns)
            let row = ind / Int(columns)
            tileWindow(w, screenFrame: screenFrame, size: size, column: column, row: row)
        }
    }
}
