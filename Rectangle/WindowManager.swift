/// WindowManager.swift

import Cocoa

class WindowManager {

    private let screenDetection: ScreenDetection
    private let standardWindowMoverChain: [WindowMover]
    private let fixedSizeWindowMoverChain: [WindowMover]
    private let animationsEnabled: () -> Bool
    private let animationDestination: (AccessibilityElement) -> CGRect?
    private var windowSizeWarning: WindowSizeWarning?
    private var requestID = 0
    private var executionID = 0
    
    init(screenDetection: ScreenDetection = ScreenDetection(),
         animationsEnabled: @escaping () -> Bool = { WindowAnimator.enabled },
         animationDestination: @escaping (AccessibilityElement) -> CGRect? = { WindowAnimator.shared.destination(for: $0) }) {
        self.screenDetection = screenDetection
        self.animationsEnabled = animationsEnabled
        self.animationDestination = animationDestination
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
        WindowFrostDiagnostics.event("window-action", fields: ["action": parameters.action.name])
        requestID &+= 1
        let currentRequestID = requestID
        hideSizeConstraintWarning()

        guard let frontmostWindowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement()
        else {
            NSSound.beep()
            return
        }

        // Recovery still owns the real window. Keep the latest action bound to this
        // element, and do not inspect its temporary parking geometry or update history.
        if WindowAnimator.shared.isRecovering(for: frontmostWindowElement) {
            let deferredParameters = ExecutionParameters(parameters.action,
                                                         updateRestoreRect: parameters.updateRestoreRect,
                                                         screen: parameters.screen,
                                                         windowElement: frontmostWindowElement,
                                                         windowId: parameters.windowId,
                                                         source: parameters.source)
            let deferred = WindowAnimator.shared.deferUntilReleased(element: frontmostWindowElement) { [weak self] in
                guard let self, self.requestID == currentRequestID else { return }
                self.execute(deferredParameters)
            }
            if deferred { return }
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
                executionID &+= 1
                let currentExecutionID = executionID
                // The animation planner accepts reachable, partly offscreen targets
                // and falls back when it cannot prepare a safe local transition.
                if animationsEnabled(), frontmostWindowElement.isResizable() {
                    animateWindow(frontmostWindowElement, to: restoreRect, restoring: true) { [weak self] frame in
                        guard let self, self.executionID == currentExecutionID else { return }
                        // A successful frosted transition has already verified and placed
                        // the real window. Only the ordinary fallback needs another write.
                        if frame.isNull { frontmostWindowElement.setFrame(restoreRect) }
                    }
                } else {
                    let restore = { [weak self] in
                        guard let self, self.executionID == currentExecutionID else { return }
                        frontmostWindowElement.setFrame(restoreRect)
                    }
                    if !WindowAnimator.shared.deferUntilReleased(element: frontmostWindowElement, action: restore) {
                        restore()
                    }
                }
            }
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            return
        }
        
        // An explicit screen (display cycling) or the cursor screen controls the
        // calculation, but neither necessarily contains the window before it moves.
        let sourceScreens = screenDetection.detectScreens(using: frontmostWindowElement)
        var screens: UsableScreens?
        if let screen = parameters.screen {
            screens = UsableScreens(currentScreen: screen, numScreens: 1)
        } else {
            screens = Defaults.useCursorScreenDetection.enabled
            ? screenDetection.detectScreensAtCursor()
            : sourceScreens
        }
        
        guard let usableScreens = screens, let sourceScreens else {
            NSSound.beep()
            Logger.log("Unable to obtain usable screens")
            return
        }
        
        let pendingDestination = animationDestination(frontmostWindowElement)
        let currentWindowRect = pendingDestination ?? frontmostWindowElement.frame
        
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
            calcResult.rect = OverlapOffsetGeometry.applyOverlapOffsetIfNeeded(calcResult.rect, windowId: windowId, screen: calcResult.screen)
        }

        let isFixedSize = (!frontmostWindowElement.isResizable() && action.resizes) || frontmostWindowElement.isSystemDialog == true
        let visibleFrameOfDestinationScreen = calcResult.resultingScreenFrame ?? calcResult.screen.adjustedVisibleFrame(ignoreTodo)
        let isMovedAcrossDisplays = sourceScreens.currentScreen != calcResult.screen
        let cooperativeCornerPlan = cooperativeCornerResizePlan(focusedWindowId: windowId,
                                                                focusedWindowIsFixedSize: isFixedSize,
                                                                focusedWindowMinimumSize: frontmostWindowElement.minimumSize,
                                                                action: action,
                                                                source: parameters.source,
                                                                oldFocusedFrame: currentNormalizedRect,
                                                                newFocusedFrame: calcResult.rect,
                                                                screenFrame: visibleFrameOfDestinationScreen,
                                                                destinationScreenIsCurrentScreen: !isMovedAcrossDisplays,
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
            if pendingDestination == nil && !cooperativeCornerPlan.needsApplication(focusedCurrentFrame: currentNormalizedRect) {
                ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(cooperativeCornerPlan.action,
                                                                            achievedFrame: currentNormalizedRect,
                                                                            screenFrame: cooperativeCornerPlan.screenFrame,
                                                                            gapSize: cooperativeCornerPlan.gapSize)
                Logger.log("Cooperative resize no-op: solved frames already match current frames")
                recordAction(windowId: windowId, resultingRect: currentWindowRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)
                finishSnapPreview(source: parameters.source, windowID: windowId, frame: calcResult.rect.screenFlipped)
                return
            }
        } else if pendingDestination == nil && currentNormalizedRect.equalTo(calcResult.rect) {
            Logger.log("Current frame is equal to new frame")

            recordAction(windowId: windowId, resultingRect: currentWindowRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)
            finishSnapPreview(source: parameters.source, windowID: windowId, frame: calcResult.rect.screenFlipped)

            return
        }

        // Only an accepted move supersedes the prior completion. A rejected or
        // already-achieved request must not discard an animation's needed fallback.
        // A matching logical target is still pending, so it continues through here.
        executionID &+= 1
        let currentExecutionID = executionID

        let resultParameters = ResultParameters(windowId: windowId,
                                                action: action,
                                                windowElement: frontmostWindowElement,
                                                calcResult: calcResult,
                                                usableScreens: sourceScreens,
                                                visibleFrameOfScreen: visibleFrameOfDestinationScreen,
                                                source: parameters.source,
                                                isFixedSize: isFixedSize)
        
        // Frosted commands prepare the destination before revealing the real
        // window, including when that destination is on another display.
        let animated = animationsEnabled() && !isFixedSize
            && (!isMovedAcrossDisplays || parameters.source == .dragToSnap || Defaults.windowAnimationStyle.value == .frosted)
            && !Defaults.cooperativeCornerResize.enabled
        WindowFrostDiagnostics.event("window-action-animation-decision", fields: [
            "windowID": windowId ?? 0, "source": String(describing: parameters.source),
            "animated": animated, "enabled": animationsEnabled(), "fixedSize": isFixedSize,
            "crossDisplay": isMovedAcrossDisplays, "cooperative": Defaults.cooperativeCornerResize.enabled,
            "sourceDisplayFrame": [sourceScreens.currentScreen.frame.minX, sourceScreens.currentScreen.frame.minY,
                                   sourceScreens.currentScreen.frame.width, sourceScreens.currentScreen.frame.height],
            "destinationDisplayFrame": [calcResult.screen.frame.minX, calcResult.screen.frame.minY,
                                        calcResult.screen.frame.width, calcResult.screen.frame.height],
            "actual": [currentWindowRect.minX, currentWindowRect.minY, currentWindowRect.width, currentWindowRect.height]])
        let completeMove = { [self] (animationHandledPlacement: Bool) in
            guard executionID == currentExecutionID else { return }
            var resultingRect: CGRect
            if let cooperativeCornerPlan {
                resultingRect = applyCooperativeCornerResize(result: resultParameters,
                                                             plan: cooperativeCornerPlan)
            } else if animationHandledPlacement {
                resultingRect = frontmostWindowElement.frame
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

            if isMovedAcrossDisplays {
                if calcResult.rect.size != resultingRect.size {
                    Logger.log("Window size wasn't applied perfectly across displays. Trying again.")
                    resultingRect = apply(result: resultParameters)

                    if calcResult.rect.size != resultingRect.size {
                        Logger.log("Final attempt to adjust across displays.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                            guard let self, self.executionID == currentExecutionID else { return }
                            let finalRect = self.apply(result: resultParameters)
                            self.windowMovedAcrossDisplays(windowElement: frontmostWindowElement, resultingRect: finalRect)
                            self.postProcess(result: resultParameters, resultingRect: finalRect, incrementCount: !animated)
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
                                                      screenFrame: sourceScreens.currentScreen.adjustedVisibleFrame(ignoreTodo),
                                                      currentAction: action,
                                                      lastRectangleAction: lastRectangleAction)
                resultingRect = frontmostWindowElement.frame
            }

            postProcess(result: resultParameters, resultingRect: resultingRect, incrementCount: !animated)
        }
        if animated {
            // Record the destination before animation for repeated-shortcut cycling.
            recordAction(windowId: windowId, resultingRect: calcResult.rect.screenFlipped,
                         action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)
            let placement = WindowAnimationPlacement(
                screenFrame: visibleFrameOfDestinationScreen.screenFlipped,
                sharedEdges: action.resizes ? Defaults.moveFixedSizeToEdge.value.alignmentEdges(
                    for: calcResult.initialRect.screenFlipped, in: visibleFrameOfDestinationScreen.screenFlipped) : nil,
                constrainToScreen: !(action.allowedToExtendOutsideCurrentScreenArea && !NSScreen.screensHaveSeparateSpaces),
                gap: CGFloat(Defaults.gapSize.value),
                displayCommand: isMovedAcrossDisplays && parameters.source != .dragToSnap)
            animateWindow(frontmostWindowElement, to: calcResult.rect.screenFlipped,
                          placement: placement,
                          restoring: Defaults.windowAnimationStyle.value == .direct && calcResult.resultingAction == .restore,
                          releasedSnap: parameters.source == .dragToSnap) { frame in
                completeMove(!frame.isNull)
            }
        } else {
            let complete = {
                completeMove(false)
            }
            if !WindowAnimator.shared.deferUntilReleased(element: frontmostWindowElement, action: complete) {
                complete()
            }
        }
    }

    private func finishSnapPreview(source: ExecutionSource, windowID: CGWindowID?, frame: CGRect) {
        guard source == .dragToSnap, let windowID else { return }
        SnapPreviewHandoff(windowID: windowID, frame: frame, covered: false).post()
    }

    func animateWindow(_ element: AccessibilityElement, to destination: CGRect,
                       placement: WindowAnimationPlacement? = nil, restoring: Bool = false, releasedSnap: Bool = false,
                       completion: @escaping (CGRect) -> Void) {
        WindowAnimator.shared.animate(element, to: destination, restoring: restoring, releasedSnap: releasedSnap, placement: placement, completion: completion)
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

    func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
        let calcResult = result.calcResult
        // Ordinary placement and no-animation fallbacks do not produce a renderer
        // coverage callback. They must still release the committed target outline.
        finishSnapPreview(source: result.source, windowID: result.windowId, frame: calcResult.rect.screenFlipped)

        if WindowSizeConstraint.isExceeded(requested: calcResult.rect, actual: resultingRect, action: result.action) {
            showSizeConstraintWarning(on: calcResult.screen)
        }
        
        if Defaults.moveCursor.userEnabled, result.source == .keyboardShortcut {
            CGWarpMouseCursorPosition(resultingRect.centerPoint)
        }
        
        recordAction(windowId: result.windowId, resultingRect: resultingRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction, incrementCount: incrementCount)

        let requestedRect = calcResult.rect.screenFlipped
        var evidence: [String: Any] = ["action": calcResult.resultingAction.name,
                                      "achieved": [resultingRect.minX, resultingRect.minY, resultingRect.width, resultingRect.height],
                                      "requested": [requestedRect.minX, requestedRect.minY, requestedRect.width, requestedRect.height]]
        if let windowId = result.windowId {
            evidence["windowID"] = windowId
            if let restore = AppDelegate.windowHistory.restoreRects[windowId] {
                evidence["restore"] = [restore.minX, restore.minY, restore.width, restore.height]
            }
        }
        WindowFrostDiagnostics.event("window-action-achieved", fields: evidence)
        Notification.Name.windowActionCompleted.post()
        
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

    func showSizeConstraintWarning(on screen: NSScreen) {
        if windowSizeWarning == nil {
            windowSizeWarning = WindowSizeWarning()
        }
        windowSizeWarning?.show(on: screen)
    }

    func hideSizeConstraintWarning() {
        windowSizeWarning?.hide()
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
