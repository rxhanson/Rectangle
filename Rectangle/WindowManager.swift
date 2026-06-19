/// WindowManager.swift

import Cocoa

class WindowManager {
    
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
    
    private func recordAction(windowId: CGWindowID, resultingRect: CGRect, action: WindowAction, subAction: SubWindowAction?) {
        let newCount: Int
        if let lastRectangleAction = AppDelegate.windowHistory.lastRectangleActions[windowId], lastRectangleAction.action == action {
            newCount = lastRectangleAction.count + 1
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
        guard let frontmostWindowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement(),
              let windowId = parameters.windowId ?? frontmostWindowElement.getWindowId()
        else {
            NSSound.beep()
            return
        }
        
        let action = parameters.action
        
        if action == .restore {
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
        
        var lastRectangleAction = AppDelegate.windowHistory.lastRectangleActions[windowId]
        
        let windowMovedExternally = currentWindowRect != lastRectangleAction?.rect
        
        if windowMovedExternally {
            lastRectangleAction = nil
            AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        }
        
        if parameters.updateRestoreRect {
            if AppDelegate.windowHistory.restoreRects[windowId] == nil
                || windowMovedExternally {
                AppDelegate.windowHistory.restoreRects[windowId] = currentWindowRect
            }
        }
        
        let ignoreTodo = TodoManager.isTodoWindow(windowId)
        
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

        if Defaults.cyclingOverlapOffset.userEnabled, action.positionCycles {
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
        }

        if let cooperativeCornerPlan {
            if !cooperativeCornerPlan.needsApplication(focusedCurrentFrame: currentNormalizedRect) {
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
        
        var resultingRect = apply(result: resultParameters,
                                  cooperativeCornerAdjustments: cooperativeCornerPlan?.adjustments ?? [],
                                  layoutTolerance: cooperativeCornerPlan?.layoutTolerance ?? 0)
        if let cooperativeCornerPlan,
           let settledRect = settleCooperativeCornerResizeIfNeeded(plan: cooperativeCornerPlan,
                                                                   focusedWindowElement: frontmostWindowElement) {
            resultingRect = settledRect
        }
        
        let isMovedAcrossDisplays = usableScreens.currentScreen != calcResult.screen
        if isMovedAcrossDisplays {
            if calcResult.rect.height != resultingRect.height {
                Logger.log("Window size wasn't applied perfectly across displays. Trying again.")
                resultingRect = apply(result: resultParameters,
                                      cooperativeCornerAdjustments: cooperativeCornerPlan?.adjustments ?? [],
                                      layoutTolerance: cooperativeCornerPlan?.layoutTolerance ?? 0)
                
                if calcResult.rect.height != resultingRect.height {
                    Logger.log("Final attempt to adjust across displays.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                        guard let self else { return }
                        let finalRect = self.apply(result: resultParameters,
                                                   cooperativeCornerAdjustments: cooperativeCornerPlan?.adjustments ?? [],
                                                   layoutTolerance: cooperativeCornerPlan?.layoutTolerance ?? 0)
                        self.windowMovedAcrossDisplays(windowElement: frontmostWindowElement, resultingRect: finalRect)
                        self.postProcess(result: resultParameters, resultingRect: finalRect)
                    }
                    return
                }
            }
            windowMovedAcrossDisplays(windowElement: frontmostWindowElement, resultingRect: resultingRect)
        }
        
        postProcess(result: resultParameters, resultingRect: resultingRect)
    }
    
    /// Move/resize a window based on the calculation results.
    /// - Returns: The rect of the window after applying the window action
    func apply(result: ResultParameters) -> CGRect {
        apply(result: result, cooperativeCornerAdjustments: [], layoutTolerance: 0)
    }

    private func apply(result: ResultParameters,
                       cooperativeCornerAdjustments: [CooperativeCornerWindowAdjustment],
                       layoutTolerance: CGFloat) -> CGRect {
        let windowMoverChain = result.isFixedSize
        ? fixedSizeWindowMoverChain
        : standardWindowMoverChain
        
        let newRect = result.calcResult.rect
        let cooperativeAxis = result.action.cooperativeResizeAxis
        let focusedWindowIsExpanding = cooperativeAxis.map {
            CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: result.windowElement.frame.screenFlipped,
                                                             newFrame: newRect,
                                                             axis: $0)
        } ?? false

        if focusedWindowIsExpanding {
            apply(cooperativeCornerAdjustments,
                  kind: .adjacent,
                  screenFrame: result.visibleFrameOfScreen,
                  layoutTolerance: layoutTolerance)
            apply(cooperativeCornerAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: result.visibleFrameOfScreen,
                  layoutTolerance: layoutTolerance)
        }

        if CooperativeCornerResize.frameNeedsApplication(currentFrame: result.windowElement.frame.screenFlipped,
                                                         solvedFrame: newRect,
                                                         screenFrame: result.visibleFrameOfScreen,
                                                         layoutTolerance: layoutTolerance) {
            for windowMover in windowMoverChain {
                windowMover.moveWindow(toRect: newRect, resultParameters: result)
            }
        } else if !cooperativeCornerAdjustments.isEmpty {
            Logger.log("Cooperative resize focused no-op: current frame already matches solved frame")
        }

        let resultingRect = result.windowElement.frame

        if !focusedWindowIsExpanding {
            apply(cooperativeCornerAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: result.visibleFrameOfScreen,
                  layoutTolerance: layoutTolerance)
            apply(cooperativeCornerAdjustments,
                  kind: .adjacent,
                  screenFrame: result.visibleFrameOfScreen,
                  layoutTolerance: layoutTolerance)
        }

        return resultingRect
    }

    private func cooperativeCornerResizePlan(focusedWindowId: CGWindowID,
                                             focusedWindowIsFixedSize: Bool,
                                             focusedWindowMinimumSize: CGSize?,
                                             action: WindowAction,
                                             source: ExecutionSource,
                                             oldFocusedFrame: CGRect,
                                             newFocusedFrame: CGRect,
                                             screenFrame: CGRect,
                                             destinationScreenIsCurrentScreen: Bool,
                                             lastRectangleAction: RectangleAction?) -> CooperativeCornerApplicationPlan? {
        guard Defaults.cooperativeCornerResize.enabled,
              source == .keyboardShortcut,
              !focusedWindowIsFixedSize,
              destinationScreenIsCurrentScreen,
              let cooperativeAxis = action.cooperativeResizeAxis,
              let movedEdge = action.cooperativeResizeMovedEdge
        else {
            return nil
        }

        let gapSize = max(0, CGFloat(Defaults.gapSize.value))
        let tolerance = CooperativeCornerResize.detectionTolerance(screenFrame: screenFrame, configuredGap: gapSize)
        let captureTolerance = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: cooperativeAxis)
        let isRepeatedCooperativeAction = action.isCompatibleRepeatedResizeAction(with: lastRectangleAction?.action)
        let actionDescription = isRepeatedCooperativeAction ? "repeated cooperative resize" : "initial corner/side cooperative placement"
        let candidateDiscoveryFrame = isRepeatedCooperativeAction ? oldFocusedFrame : newFocusedFrame
        let screenFrameAX = screenFrame.screenFlipped
        let elementsById = AccessibilityElement.getAllWindowElements().reduce(into: [CGWindowID: AccessibilityElement]()) { elements, element in
            guard let candidateId = element.getWindowId(),
                  candidateId != focusedWindowId,
                  element.isWindow == true,
                  element.isMinimized != true,
                  element.isFullScreen != true,
                  element.isHidden != true,
                  element.isSheet != true,
                  element.isResizable()
            else {
                return
            }

            let frame = element.frame
            guard !frame.isNull, screenFrameAX.intersects(frame) else {
                return
            }

            elements[candidateId] = element
        }

        let candidates = elementsById.map { id, element in
            CooperativeCornerResize.Candidate(id: id,
                                              frame: element.frame.screenFlipped,
                                              minimumSize: element.minimumSize)
        }
        let minimumSize = CGSize(width: max(1, CGFloat(Defaults.minimumWindowWidth.value)),
                                 height: max(1, CGFloat(Defaults.minimumWindowHeight.value)))
        guard let plan = CooperativeCornerResize.plan(oldFocusedFrame: oldFocusedFrame,
                                                      newFocusedFrame: newFocusedFrame,
                                                      screenFrame: screenFrame,
                                                      candidates: candidates,
                                                      axis: cooperativeAxis,
                                                      tolerance: tolerance,
                                                      minimumSize: minimumSize,
                                                      focusedMinimumSize: focusedWindowMinimumSize,
                                                      gapSize: gapSize,
                                                      captureTolerance: captureTolerance,
                                                      movedEdgeOverride: movedEdge,
                                                      candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                      actionDescription: actionDescription)
        else {
            return nil
        }

        plan.debugLog.forEach(Logger.log)

        let adjustments: [CooperativeCornerWindowAdjustment] = plan.adjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element,
                                                    id: adjustment.id,
                                                    newFrame: adjustment.newFrame,
                                                    kind: adjustment.kind)
        }
        guard !adjustments.isEmpty else { return nil }

        return CooperativeCornerApplicationPlan(oldFocusedFrame: oldFocusedFrame,
                                                requestedFocusedFrame: newFocusedFrame,
                                                focusedFrame: plan.focusedFrame,
                                                screenFrame: screenFrame,
                                                candidates: candidates,
                                                axis: cooperativeAxis,
                                                detectionTolerance: tolerance,
                                                captureTolerance: captureTolerance,
                                                layoutTolerance: 4,
                                                minimumSize: minimumSize,
                                                focusedMinimumSize: focusedWindowMinimumSize,
                                                gapSize: gapSize,
                                                movedEdge: movedEdge,
                                                candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                actionDescription: actionDescription,
                                                adjustments: adjustments,
                                                debugLog: plan.debugLog)
    }

    private func apply(_ adjustments: [CooperativeCornerWindowAdjustment],
                       kind: CooperativeCornerResize.Adjustment.Kind,
                       screenFrame: CGRect,
                       layoutTolerance: CGFloat) {
        adjustments.filter { $0.kind == kind }.forEach { adjustment in
            if CooperativeCornerResize.frameNeedsApplication(currentFrame: adjustment.element.frame.screenFlipped,
                                                             solvedFrame: adjustment.newFrame,
                                                             screenFrame: screenFrame,
                                                             layoutTolerance: layoutTolerance) {
                adjustment.element.setFrame(adjustment.newFrame.screenFlipped)
            } else {
                Logger.log("Cooperative resize no-op for \(adjustment.id): current frame already matches solved frame")
            }
        }
    }

    private func settleCooperativeCornerResizeIfNeeded(plan: CooperativeCornerApplicationPlan,
                                                       focusedWindowElement: AccessibilityElement) -> CGRect? {
        let actualFocusedFrame = focusedWindowElement.frame.screenFlipped
        let actualCandidateFramesById = Dictionary(uniqueKeysWithValues: plan.adjustments.map { adjustment in
            (adjustment.id, adjustment.element.frame.screenFlipped)
        })

        guard let correctionPlan = CooperativeCornerResize.correctionPlan(oldFocusedFrame: plan.oldFocusedFrame,
                                                                          requestedFocusedFrame: plan.requestedFocusedFrame,
                                                                          plannedPlan: plan.asGeometryPlan(),
                                                                          screenFrame: plan.screenFrame,
                                                                          candidates: plan.candidates,
                                                                          actualFocusedFrame: actualFocusedFrame,
                                                                          actualCandidateFramesById: actualCandidateFramesById,
                                                                          axis: plan.axis,
                                                                          tolerance: plan.detectionTolerance,
                                                                          layoutTolerance: plan.layoutTolerance,
                                                                          minimumSize: plan.minimumSize,
                                                                          focusedMinimumSize: plan.focusedMinimumSize,
                                                                          gapSize: plan.gapSize,
                                                                          captureTolerance: plan.captureTolerance,
                                                                          movedEdgeOverride: plan.movedEdge,
                                                                          candidateDiscoveryFrame: plan.candidateDiscoveryFrame,
                                                                          actionDescription: plan.actionDescription)
        else {
            return nil
        }

        correctionPlan.debugLog.forEach(Logger.log)
        let elementsById = Dictionary(uniqueKeysWithValues: plan.adjustments.map { ($0.id, $0.element) })
        let correctionAdjustments: [CooperativeCornerWindowAdjustment] = correctionPlan.adjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element,
                                                    id: adjustment.id,
                                                    newFrame: adjustment.newFrame,
                                                    kind: adjustment.kind)
        }

        let focusedWindowIsExpanding = CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: plan.oldFocusedFrame,
                                                                                        newFrame: correctionPlan.focusedFrame,
                                                                                        axis: plan.axis)
        if focusedWindowIsExpanding {
            apply(correctionAdjustments,
                  kind: .adjacent,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
            apply(correctionAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
            applyFocusedCooperativeFrameIfNeeded(correctionPlan.focusedFrame,
                                                 focusedWindowElement: focusedWindowElement,
                                                 screenFrame: plan.screenFrame,
                                                 layoutTolerance: plan.layoutTolerance)
        } else {
            applyFocusedCooperativeFrameIfNeeded(correctionPlan.focusedFrame,
                                                 focusedWindowElement: focusedWindowElement,
                                                 screenFrame: plan.screenFrame,
                                                 layoutTolerance: plan.layoutTolerance)
            apply(correctionAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
            apply(correctionAdjustments,
                  kind: .adjacent,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
        }

        return focusedWindowElement.frame
    }

    private func applyFocusedCooperativeFrameIfNeeded(_ frame: CGRect,
                                                      focusedWindowElement: AccessibilityElement,
                                                      screenFrame: CGRect,
                                                      layoutTolerance: CGFloat) {
        if CooperativeCornerResize.frameNeedsApplication(currentFrame: focusedWindowElement.frame.screenFlipped,
                                                         solvedFrame: frame,
                                                         screenFrame: screenFrame,
                                                         layoutTolerance: layoutTolerance) {
            focusedWindowElement.setFrame(frame.screenFlipped)
        } else {
            Logger.log("Cooperative resize focused no-op: current frame already matches solved frame")
        }
    }
    
    func windowMovedAcrossDisplays(windowElement: AccessibilityElement, resultingRect: CGRect) {
        windowElement.bringToFront(force: true)
        
        if Defaults.moveCursorAcrossDisplays.userEnabled {
            CGWarpMouseCursorPosition(resultingRect.centerPoint)
        }
    }
    
    private func applyOverlapOffsetIfNeeded(_ rect: CGRect, windowId: CGWindowID, screen: NSScreen) -> CGRect {
        let overlapOffset = CGFloat(Defaults.cyclingOverlapOffsetSize.value)
        guard overlapOffset > 0 else { return rect }

        let screenFrameAX = screen.adjustedVisibleFrame().screenFlipped
        let tolerance: CGFloat = 4
        let maxCascade = min(5, max(1, Defaults.cyclingOverlapMaxCascade.value))

        let otherWindows = AccessibilityElement.getAllWindowElements().filter { element in
            guard element.getWindowId() != windowId,
                  element.isWindow == true,
                  element.isMinimized != true,
                  element.isHidden != true,
                  element.isSheet != true
            else { return false }

            let frame = element.frame
            return !frame.isNull && screenFrameAX.intersects(frame)
        }

        let screenFrameNormalized = screen.adjustedVisibleFrame()
        var candidate = rect
        var cascadeLevel = 0

        while cascadeLevel < maxCascade {
            let candidateAX = candidate.screenFlipped
            let hasOverlap = otherWindows.contains { element in
                let otherFrame = element.frame
                let originsMatch = abs(otherFrame.origin.x - candidateAX.origin.x) < tolerance
                    && abs(otherFrame.origin.y - candidateAX.origin.y) < tolerance
                let otherCoversScreen = otherFrame.width > screenFrameAX.width * 0.9
                    && otherFrame.height > screenFrameAX.height * 0.9
                return originsMatch && !otherCoversScreen
            }

            guard hasOverlap else { break }

            candidate.origin.x += overlapOffset
            candidate.origin.y += overlapOffset
            cascadeLevel += 1

            if candidate.origin.x + candidate.width > screenFrameNormalized.maxX {
                candidate.origin.x = screenFrameNormalized.maxX - candidate.width
            }
            if candidate.origin.y + candidate.height > screenFrameNormalized.maxY {
                candidate.origin.y = screenFrameNormalized.maxY - candidate.height
            }
            if candidate.origin.x < screenFrameNormalized.origin.x {
                candidate.origin.x = screenFrameNormalized.origin.x
            }
            if candidate.origin.y < screenFrameNormalized.origin.y {
                candidate.origin.y = screenFrameNormalized.origin.y
            }
        }

        if cascadeLevel > 0 {
            Logger.log("Cycling overlap detected, applied \(cascadeLevel) x \(overlapOffset)pt cascade offset")
        }
        return candidate
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
    let windowId: CGWindowID
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

private struct CooperativeCornerWindowAdjustment {
    let element: AccessibilityElement
    let id: CGWindowID
    let newFrame: CGRect
    let kind: CooperativeCornerResize.Adjustment.Kind
}

private struct CooperativeCornerApplicationPlan {
    let oldFocusedFrame: CGRect
    let requestedFocusedFrame: CGRect
    let focusedFrame: CGRect
    let screenFrame: CGRect
    let candidates: [CooperativeCornerResize.Candidate]
    let axis: CornerCycleExpansionAxis
    let detectionTolerance: CGFloat
    let captureTolerance: CGFloat
    let layoutTolerance: CGFloat
    let minimumSize: CGSize
    let focusedMinimumSize: CGSize?
    let gapSize: CGFloat
    let movedEdge: CooperativeCornerResize.MovedEdge
    let candidateDiscoveryFrame: CGRect
    let actionDescription: String
    let adjustments: [CooperativeCornerWindowAdjustment]
    let debugLog: [String]

    func needsApplication(focusedCurrentFrame: CGRect) -> Bool {
        if CooperativeCornerResize.frameNeedsApplication(currentFrame: focusedCurrentFrame,
                                                         solvedFrame: focusedFrame,
                                                         screenFrame: screenFrame,
                                                         layoutTolerance: layoutTolerance) {
            return true
        }

        return adjustments.contains { adjustment in
            CooperativeCornerResize.frameNeedsApplication(currentFrame: adjustment.element.frame.screenFlipped,
                                                         solvedFrame: adjustment.newFrame,
                                                         screenFrame: screenFrame,
                                                         layoutTolerance: layoutTolerance)
        }
    }

    func asGeometryPlan() -> CooperativeCornerResize.Plan {
        let geometryAdjustments = adjustments.map { adjustment in
            CooperativeCornerResize.Adjustment(id: adjustment.id,
                                               oldFrame: adjustment.element.frame.screenFlipped,
                                               newFrame: adjustment.newFrame,
                                               kind: adjustment.kind)
        }
        return CooperativeCornerResize.Plan(focusedFrame: focusedFrame,
                                            adjustments: geometryAdjustments,
                                            debugLog: debugLog)
    }
}
