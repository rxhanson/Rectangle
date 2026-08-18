/// WindowManager.swift

import Cocoa

class WindowManager {

    /// Bounds how long a hung app can stall the overlap scan's accessibility
    /// calls. Matches the badge's timeout for the same reason.
    static let axScanTimeout: Float = 0.25

    private let screenDetection = ScreenDetection()
    private let standardWindowMoverChain: [WindowMover]
    private let fixedSizeWindowMoverChain: [WindowMover]
    
    init() {
        standardWindowMoverChain = [
            StandardWindowMover(),
            EdgeAlignmentWindowMover(),
            BestEffortWindowMover()
        ]
        
        fixedSizeWindowMoverChain = [
            FixedSizeWindowMover(),
            BestEffortWindowMover()
        ]
    }
    
    func recordAction(windowId: CGWindowID?,
                      resultingRect: CGRect,
                      action: WindowAction,
                      subAction: SubWindowAction?,
                      incrementCount: Bool = true) {
        guard let windowId else { return }
        let newCount: Int
        if let lastRectangleAction = AppDelegate.windowHistory.lastRectangleActions[windowId],
           lastRectangleAction.action == action {
            newCount = incrementCount ? lastRectangleAction.count + 1 : lastRectangleAction.count
        } else {
            newCount = 1
        }
        
        AppDelegate.windowHistory.lastRectangleActions[windowId] = RectangleAction(
            action: action,
            subAction: subAction,
            rect: resultingRect,
            count: newCount
        )
    }
    
    func execute(_ parameters: ExecutionParameters) {
        guard let frontmostWindowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement()
        else {
            NSSound.beep()
            return
        }
        
        // The window id can be unavailable when macOS stops vending window info
        // after a session transition (#640). Actions still execute; only
        // window-id-keyed history is skipped.
        let windowId = parameters.windowId ?? frontmostWindowElement.getWindowId()

        let action = parameters.action
        
        if action == .restore {
            guard let windowId else {
                NSSound.beep()
                return
            }
            if let restoreRect = AppDelegate.windowHistory.restoreRects[windowId] {
                frontmostWindowElement.setFrame(restoreRect)
            }
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            return
        }
        
        var screens: UsableScreens?
        if let screen = parameters.screen {
            screens = UsableScreens(currentScreen: screen, numScreens: 1)
        } else {
            screens = Defaults.useCursorScreenDetection.enabled
            ? screenDetection.detectScreensAtCursor()
            : screenDetection.detectScreens(using: frontmostWindowElement)
        }
        
        guard let usableScreens = screens else {
            NSSound.beep()
            Logger.log("Unable to obtain usable screens")
            return
        }
        
        let currentWindowRect: CGRect = frontmostWindowElement.frame
        
        var lastRectangleAction = windowId.flatMap { AppDelegate.windowHistory.lastRectangleActions[$0] }
        
        let windowMovedExternally = currentWindowRect != lastRectangleAction?.rect
        
        if windowMovedExternally {
            lastRectangleAction = nil
            if let windowId {
                AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            }
        }
        
        if parameters.updateRestoreRect, let windowId {
            if AppDelegate.windowHistory.restoreRects[windowId] == nil
                || windowMovedExternally {
                AppDelegate.windowHistory.restoreRects[windowId] = currentWindowRect
            }
        }
        
        let ignoreTodo = windowId.map { TodoManager.isTodoWindow($0) } ?? false
        
        if frontmostWindowElement.isSheet == true
            || currentWindowRect.isNull
            || usableScreens.frameOfCurrentScreen.isNull
            || usableScreens.currentScreen.adjustedVisibleFrame(ignoreTodo).isNull {
            NSSound.beep()
            Logger.log("Window is not snappable or usable screen is not valid")
            return
        }
        
        let currentNormalizedRect = currentWindowRect.screenFlipped
        let currentWindow = Window(id: windowId, rect: currentNormalizedRect)
        
        let windowCalculation = WindowCalculationFactory.calculationsByAction[action]
        
        let calculationParams = WindowCalculationParameters(window: currentWindow, usableScreens: usableScreens, action: action, lastAction: lastRectangleAction, ignoreTodo: ignoreTodo)
        guard var calcResult = windowCalculation?.calculate(calculationParams) else {
            NSSound.beep()
            Logger.log("Nil calculation result")
            return
        }
        
        let gapsApplicable = calcResult.resultingAction.gapsApplicable
        
        if Defaults.gapSize.value > 0, gapsApplicable != .none {
            let gapSharedEdges = calcResult.resultingSubAction?.gapSharedEdge ?? calcResult.resultingAction.gapSharedEdge
            
            calcResult.rect = GapCalculation.applyGaps(calcResult.rect, dimension: gapsApplicable, sharedEdges: gapSharedEdges, gapSize: Defaults.gapSize.value, skipTopGap: Defaults.skipGapTopEdge.enabled)
        }

        if Defaults.cyclingOverlapOffset.userEnabled, action.overlapOffsetApplies {
            calcResult.rect = applyOverlapOffsetIfNeeded(calcResult.rect, windowId: windowId, screen: calcResult.screen)
        }

        let isFixedSize = (!frontmostWindowElement.isResizable() && action.resizes) || frontmostWindowElement.isSystemDialog == true
        let visibleFrameOfDestinationScreen = calcResult.resultingScreenFrame ?? calcResult.screen.adjustedVisibleFrame(ignoreTodo)
        let cooperativeCornerPlan = cooperativeCornerResizePlan(focusedWindowId: windowId,
                                                                focusedWindowIsFixedSize: isFixedSize,
                                                                focusedWindowMinimumSize: frontmostWindowElement.minimumSize,
                                                                action: action,
                                                                source: parameters.source,
                                                                oldFocusedFrame: currentNormalizedRect,
                                                                newFocusedFrame: calcResult.rect,
                                                                screenFrame: visibleFrameOfDestinationScreen,
                                                                destinationScreenIsCurrentScreen: usableScreens.currentScreen == calcResult.screen,
                                                                lastRectangleAction: lastRectangleAction)
        if let cooperativeCornerPlan {
            calcResult.rect = cooperativeCornerPlan.focusedFrame
            if let sideSplitRecordingFrame = cooperativeCornerPlan.sideSplitRecordingFrame {
                calcResult.initialRect = sideSplitRecordingFrame
            }
        }

        if cooperativeCornerPlan == nil {
            ActiveSideSplitRatios.shared.recordSideAction(calcResult.resultingAction,
                                                          targetFrame: calcResult.initialRect,
                                                          screenFrame: visibleFrameOfDestinationScreen)
        }

        if let cooperativeCornerPlan {
            if !cooperativeCornerPlan.needsApplication(focusedCurrentFrame: currentNormalizedRect) {
                ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(cooperativeCornerPlan.action,
                                                                            achievedFrame: currentNormalizedRect,
                                                                            screenFrame: cooperativeCornerPlan.screenFrame,
                                                                            gapSize: cooperativeCornerPlan.gapSize)
                Logger.log("Cooperative resize no-op: solved frames already match current frames")
                recordAction(windowId: windowId, resultingRect: currentWindowRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)
                return
            }
        } else if currentNormalizedRect.equalTo(calcResult.rect) {
            Logger.log("Current frame is equal to new frame")

            recordAction(windowId: windowId, resultingRect: currentWindowRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)

            return
        }

        let resultParameters = ResultParameters(windowId: windowId,
                                                action: action,
                                                windowElement: frontmostWindowElement,
                                                calcResult: calcResult,
                                                usableScreens: usableScreens,
                                                visibleFrameOfScreen: visibleFrameOfDestinationScreen,
                                                source: parameters.source,
                                                isFixedSize: isFixedSize)
        
        var resultingRect: CGRect
        if let cooperativeCornerPlan {
            resultingRect = applyCooperativeCornerResize(result: resultParameters,
                                                         plan: cooperativeCornerPlan)
        } else {
            resultingRect = apply(result: resultParameters)
        }

        if let cooperativeCornerPlan {
            // AX can enforce a minimum size that was not reported before the settling pass.
            ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(cooperativeCornerPlan.action,
                                                                        achievedFrame: resultingRect.screenFlipped,
                                                                        screenFrame: cooperativeCornerPlan.screenFrame,
                                                                        gapSize: cooperativeCornerPlan.gapSize)
        }
        
        let isMovedAcrossDisplays = usableScreens.currentScreen != calcResult.screen
        if isMovedAcrossDisplays {
            if calcResult.rect.height != resultingRect.height {
                Logger.log("Window size wasn't applied perfectly across displays. Trying again.")
                resultingRect = apply(result: resultParameters)
                
                if calcResult.rect.height != resultingRect.height {
                    Logger.log("Final attempt to adjust across displays.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                        guard let self else { return }
                        let finalRect = self.apply(result: resultParameters)
                        self.windowMovedAcrossDisplays(windowElement: frontmostWindowElement, resultingRect: finalRect)
                        self.postProcess(result: resultParameters, resultingRect: finalRect)
                    }
                    return
                }
            }
            windowMovedAcrossDisplays(windowElement: frontmostWindowElement, resultingRect: resultingRect)
        }

        if !isMovedAcrossDisplays {
            applyCooperativeCornerCleanupIfNeeded(focusedWindowId: windowId,
                                                  source: parameters.source,
                                                  oldFocusedFrame: currentNormalizedRect,
                                                  newFocusedFrame: resultingRect.screenFlipped,
                                                  screenFrame: usableScreens.currentScreen.adjustedVisibleFrame(ignoreTodo),
                                                  currentAction: action,
                                                  lastRectangleAction: lastRectangleAction)
            resultingRect = frontmostWindowElement.frame
        }
        
        postProcess(result: resultParameters, resultingRect: resultingRect)
    }
    
    /// Move/resize a window based on the calculation results.
    /// - Returns: The rect of the window after applying the window action
    func apply(result: ResultParameters) -> CGRect {
        let newRect = result.calcResult.rect
        if !result.windowElement.frame.screenFlipped.equalTo(newRect) {
            moveWindow(toRect: newRect, result: result)
        }
        return result.windowElement.frame
    }

    func moveWindow(toRect rect: CGRect, result: ResultParameters) {
        let windowMoverChain = result.isFixedSize
        ? fixedSizeWindowMoverChain
        : standardWindowMoverChain
        for windowMover in windowMoverChain {
            windowMover.moveWindow(toRect: rect, resultParameters: result)
        }
    }
    
    func windowMovedAcrossDisplays(windowElement: AccessibilityElement, resultingRect: CGRect) {
        windowElement.bringToFront(force: true)
        
        if Defaults.moveCursorAcrossDisplays.userEnabled {
            CGWarpMouseCursorPosition(resultingRect.centerPoint)
        }
    }
    
    private func applyOverlapOffsetIfNeeded(_ rect: CGRect, windowId: CGWindowID?, screen: NSScreen) -> CGRect {
        let overlapOffset = CGFloat(Defaults.cyclingOverlapOffsetSize.value)
        guard overlapOffset > 0 else { return rect }

        // Without a window id the current window can't be excluded from the
        // overlap scan, so skip the offset rather than cascade against itself.
        guard let windowId else { return rect }

        let screenFrameNormalized = screen.adjustedVisibleFrame()

        // Nothing to do if the window can't move on either axis - a window
        // sized to the whole visible frame has nowhere to shift. Checked
        // before the scan below, which is far more expensive than this.
        guard OverlapOffsetGeometry.canOffset(rect, in: screenFrameNormalized, by: overlapOffset) else {
            return rect
        }

        // This scan enumerates every window over the accessibility API on the
        // main thread. A hung or (under heavy system load) sluggish app can
        // otherwise block that for the full default AX timeout - seconds -
        // freezing the UI on each window move. Cap messaging system-wide for
        // the scan and restore the process default immediately after; an app
        // that can't answer in time is simply skipped (no offset), which is
        // harmless.
        //
        // The cap is per request, not per scan, so this bounds what any one
        // unresponsive app costs rather than the total: several hung apps
        // still add up. That is a large improvement on the default and not a
        // guarantee of a fixed ceiling.
        AXUIElementSetMessagingTimeout(AXUIElement.systemWide, Self.axScanTimeout)
        defer { AXUIElementSetMessagingTimeout(AXUIElement.systemWide, 0) }

        let screenFrameAX = screenFrameNormalized.screenFlipped
        let maxCascade = min(5, max(1, Defaults.cyclingOverlapMaxCascade.value))
        let placedCoversScreen = OverlapOffsetGeometry.coversScreen(rect, screenFrame: screenFrameNormalized)

        // Each element.frame is a pair of accessibility round-trips, so the
        // frames are read once here rather than on every cascade iteration.
        let occupiedTopLefts: [CGPoint] = AccessibilityElement.getAllWindowElements().compactMap { element in
            guard element.getWindowId() != windowId,
                  element.isWindow == true,
                  element.isMinimized != true,
                  element.isHidden != true,
                  element.isSheet != true
            else { return nil }

            let frameAX = element.frame
            guard !frameAX.isNull, screenFrameAX.intersects(frameAX) else { return nil }

            // A window covering the screen shares its origin with every
            // left/right half and corner placement, so matching one would
            // offset all of them (#1766) - it's ignored. That only holds while
            // the window being placed is smaller than it: when this window
            // covers the screen too, a shared origin is a genuine stack of
            // maximized windows, which is what the offset exists to reveal.
            let frame = frameAX.screenFlipped
            guard placedCoversScreen
                    || !OverlapOffsetGeometry.coversScreen(frame, screenFrame: screenFrameNormalized)
            else { return nil }

            return OverlapOffsetGeometry.topLeft(of: frame)
        }

        let offsetRect = OverlapOffsetGeometry.cascadedRect(rect,
                                                           occupiedTopLefts: occupiedTopLefts,
                                                           screenFrame: screenFrameNormalized,
                                                           offset: overlapOffset,
                                                           maxCascade: maxCascade)
        if offsetRect != rect {
            Logger.log("Overlap detected, offset window to \(offsetRect.origin.debugDescription)")
        }
        return offsetRect
    }

    func postProcess(result: ResultParameters, resultingRect: CGRect) {
        let calcResult = result.calcResult
        
        if Defaults.moveCursor.userEnabled, result.source == .keyboardShortcut {
            CGWarpMouseCursorPosition(resultingRect.centerPoint)
        }
        
        recordAction(windowId: result.windowId, resultingRect: resultingRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)
        
        if Logger.logging {
            var logItems = ["\(result.action.name)",
                            "display: \(result.visibleFrameOfScreen.debugDescription)",
                            "calculatedRect: \(result.calcResult.rect.screenFlipped.debugDescription)",
                            "resultRect: \(resultingRect.debugDescription)",
                            "srcScreen: \(result.usableScreens.currentScreen.localizedName)",
                            "destScreen: \(calcResult.screen.localizedName)"]
            if let resultScreens = screenDetection.detectScreens(using: result.windowElement) {
                logItems.append("resultScreen: \(resultScreens.currentScreen.localizedName)")
            }
            Logger.log(logItems.joined(separator: ", "))
        }
    }
}

struct ResultParameters {
    let windowId: CGWindowID?
    let action: WindowAction
    let windowElement: AccessibilityElement
    let calcResult: WindowCalculationResult
    let usableScreens: UsableScreens
    let visibleFrameOfScreen: CGRect
    let source: ExecutionSource
    let isFixedSize: Bool
}

struct RectangleAction {
    let action: WindowAction
    let subAction: SubWindowAction?
    let rect: CGRect
    let count: Int
}

struct ExecutionParameters {
    let action: WindowAction
    let updateRestoreRect: Bool
    let screen: NSScreen?
    let windowElement: AccessibilityElement?
    let windowId: CGWindowID?
    let source: ExecutionSource

    init(_ action: WindowAction, updateRestoreRect: Bool = true, screen: NSScreen? = nil, windowElement: AccessibilityElement? = nil, windowId: CGWindowID? = nil, source: ExecutionSource = .keyboardShortcut) {
        self.action = action
        self.updateRestoreRect = updateRestoreRect
        self.screen = screen
        self.windowElement = windowElement
        self.windowId = windowId
        self.source = source
    }
}

enum ExecutionSource {
    case keyboardShortcut, dragToSnap, menuItem, url, titleBar
}
