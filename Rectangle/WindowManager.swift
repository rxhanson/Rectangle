/// WindowManager.swift

import Cocoa

class WindowManager {

    private let screenDetection: ScreenDetection
    private let standardWindowMoverChain: [WindowMover]
    private let fixedSizeWindowMoverChain: [WindowMover]
    private let windowAnimator: WindowAnimator
    private var windowSizeWarning: WindowSizeWarning?
    private var executionID = 0
    
    init(screenDetection: ScreenDetection = ScreenDetection(),
         windowAnimator: WindowAnimator = WindowAnimator.shared) {
        
        self.screenDetection = screenDetection
        self.windowAnimator = windowAnimator
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
    
    func logicalFrame(for element: AccessibilityElement) -> CGRect {
        windowAnimator.destination(for: element) ?? element.frame
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
        WindowAnimationDiagnostics.event("window-action", fields: ["action": parameters.action.name])
        hideSizeConstraintWarning()

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
                executionID &+= 1
                let currentExecutionID = executionID
                if WindowAnimator.enabled, frontmostWindowElement.isResizable() {
                    animateWindow(frontmostWindowElement, to: restoreRect, profile: parameters.source == .keyboardShortcut ? .keyboard : .standard) { [weak self] frame in
                        guard let self, self.executionID == currentExecutionID else { return }
                        // A completed animation has already placed the real window.
                        if frame.isNull { frontmostWindowElement.setFrame(restoreRect) }
                    }
                } else {
                    WindowAnimator.shared.cancel(for: frontmostWindowElement)
                    frontmostWindowElement.setFrame(restoreRect)
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
        
        let pendingDestination = windowAnimator.destination(for: frontmostWindowElement)
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
                return
            }
        } else if pendingDestination == nil && currentNormalizedRect.equalTo(calcResult.rect) {
            Logger.log("Current frame is equal to new frame")

            recordAction(windowId: windowId, resultingRect: currentWindowRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)

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
        
        let animated = WindowAnimator.enabled && !isFixedSize
            && (!isMovedAcrossDisplays || parameters.source == .dragToSnap)
            && !Defaults.cooperativeCornerResize.enabled
        WindowAnimationDiagnostics.event("window-action-animation-decision", fields: [
            "windowID": windowId ?? 0, "source": String(describing: parameters.source),
            "animated": animated, "enabled": WindowAnimator.enabled, "fixedSize": isFixedSize,
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
                gap: CGFloat(Defaults.gapSize.value))
            animateWindow(frontmostWindowElement, to: calcResult.rect.screenFlipped,
                          placement: placement,
                          releasedSnap: parameters.source == .dragToSnap,
                          profile: parameters.source == .keyboardShortcut ? .keyboard : .standard) { frame in
                completeMove(!frame.isNull)
            }
        } else {
            WindowAnimator.shared.cancel(for: frontmostWindowElement)
            completeMove(false)
        }
    }



    func animateWindow(_ element: AccessibilityElement, to destination: CGRect,
                       placement: WindowAnimationPlacement? = nil, releasedSnap: Bool = false,
                       profile: WindowAnimationProfile = .standard, completion: @escaping (CGRect) -> Void) {
        WindowAnimator.shared.animate(element, to: destination, releasedSnap: releasedSnap, placement: placement, profile: profile, completion: completion)
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
        WindowAnimationDiagnostics.event("window-action-achieved", fields: evidence)
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
