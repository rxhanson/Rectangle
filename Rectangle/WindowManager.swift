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

        if currentNormalizedRect.equalTo(calcResult.rect) {
            Logger.log("Current frame is equal to new frame")

            recordAction(windowId: windowId, resultingRect: currentWindowRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction)

            return
        }
        
        let isFixedSize = (!frontmostWindowElement.isResizable() && action.resizes) || frontmostWindowElement.isSystemDialog == true
        let visibleFrameOfDestinationScreen = calcResult.resultingScreenFrame ?? calcResult.screen.adjustedVisibleFrame(ignoreTodo)
        let cooperativeCornerAdjustments = cooperativeCornerResizeAdjustments(focusedWindowId: windowId,
                                                                              focusedWindowIsFixedSize: isFixedSize,
                                                                              action: action,
                                                                              source: parameters.source,
                                                                              oldFocusedFrame: currentNormalizedRect,
                                                                              newFocusedFrame: calcResult.rect,
                                                                              screenFrame: visibleFrameOfDestinationScreen,
                                                                              destinationScreenIsCurrentScreen: usableScreens.currentScreen == calcResult.screen,
                                                                              lastRectangleAction: lastRectangleAction)
        let resultParameters = ResultParameters(windowId: windowId,
                                                action: action,
                                                windowElement: frontmostWindowElement,
                                                calcResult: calcResult,
                                                usableScreens: usableScreens,
                                                visibleFrameOfScreen: visibleFrameOfDestinationScreen,
                                                source: parameters.source,
                                                isFixedSize: isFixedSize)
        
        var resultingRect = apply(result: resultParameters, cooperativeCornerAdjustments: cooperativeCornerAdjustments)
        
        let isMovedAcrossDisplays = usableScreens.currentScreen != calcResult.screen
        if isMovedAcrossDisplays {
            if calcResult.rect.height != resultingRect.height {
                Logger.log("Window size wasn't applied perfectly across displays. Trying again.")
                resultingRect = apply(result: resultParameters, cooperativeCornerAdjustments: cooperativeCornerAdjustments)
                
                if calcResult.rect.height != resultingRect.height {
                    Logger.log("Final attempt to adjust across displays.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [weak self] in
                        guard let self else { return }
                        let finalRect = self.apply(result: resultParameters, cooperativeCornerAdjustments: cooperativeCornerAdjustments)
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
        apply(result: result, cooperativeCornerAdjustments: [])
    }

    private func apply(result: ResultParameters, cooperativeCornerAdjustments: [CooperativeCornerWindowAdjustment]) -> CGRect {
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
            apply(cooperativeCornerAdjustments, kind: .adjacent)
            apply(cooperativeCornerAdjustments, kind: .matchingFocusedFrame)
        }
        
        for windowMover in windowMoverChain {
            windowMover.moveWindow(toRect: newRect, resultParameters: result)
        }

        let resultingRect = result.windowElement.frame

        if !focusedWindowIsExpanding {
            apply(cooperativeCornerAdjustments, kind: .matchingFocusedFrame)
            apply(cooperativeCornerAdjustments, kind: .adjacent)
        }

        return resultingRect
    }

    private func cooperativeCornerResizeAdjustments(focusedWindowId: CGWindowID,
                                                    focusedWindowIsFixedSize: Bool,
                                                    action: WindowAction,
                                                    source: ExecutionSource,
                                                    oldFocusedFrame: CGRect,
                                                    newFocusedFrame: CGRect,
                                                    screenFrame: CGRect,
                                                    destinationScreenIsCurrentScreen: Bool,
                                                    lastRectangleAction: RectangleAction?) -> [CooperativeCornerWindowAdjustment] {
        guard Defaults.cooperativeCornerResize.enabled,
              source == .keyboardShortcut,
              !focusedWindowIsFixedSize,
              destinationScreenIsCurrentScreen,
              let cooperativeAxis = action.cooperativeResizeAxis,
              lastRectangleAction?.action == action
        else {
            return []
        }

        let tolerance = max(CGFloat(Defaults.gapSize.value) + 4, 4)
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
            CooperativeCornerResize.Candidate(id: id, frame: element.frame.screenFlipped)
        }
        let minimumSize = CGSize(width: max(1, CGFloat(Defaults.minimumWindowWidth.value)),
                                 height: max(1, CGFloat(Defaults.minimumWindowHeight.value)))
        let adjustments = CooperativeCornerResize.adjustments(oldFocusedFrame: oldFocusedFrame,
                                                              newFocusedFrame: newFocusedFrame,
                                                              screenFrame: screenFrame,
                                                              candidates: candidates,
                                                              axis: cooperativeAxis,
                                                              tolerance: tolerance,
                                                              minimumSize: minimumSize)

        return adjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element, newFrame: adjustment.newFrame, kind: adjustment.kind)
        }
    }

    private func apply(_ adjustments: [CooperativeCornerWindowAdjustment], kind: CooperativeCornerResize.Adjustment.Kind) {
        adjustments.filter { $0.kind == kind }.forEach { adjustment in
            adjustment.element.setFrame(adjustment.newFrame.screenFlipped)
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
    let newFrame: CGRect
    let kind: CooperativeCornerResize.Adjustment.Kind
}

private extension WindowAction {
    var cooperativeResizeAxis: CornerCycleExpansionAxis? {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return Defaults.cornerCycleExpansionAxis.value
        case .leftHalf, .rightHalf:
            return .horizontal
        case .topHalf, .bottomHalf:
            return .vertical
        default:
            return nil
        }
    }
}
