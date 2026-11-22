/// WindowManager.swift

import Cocoa

class WindowManager {

    private let screenDetection: ScreenDetection
    private let standardWindowMoverChain: [WindowMover]
    private let fixedSizeWindowMoverChain: [WindowMover]
    private let screenSelector: ScreenSelector
    private let targetAdjusterChain: [WindowTargetAdjuster]
    private let delegateProviders: [WindowManagerDelegateProvider]
    private let windowAnimator: WindowAnimator
    private let windowHistory: WindowHistory
    private let sizeConstraint: WindowSizeConstraint
    private let placementCoordinator: WindowPlacementCoordinator

    init(screenDetection: ScreenDetection = ScreenDetection(),
         windowAnimator: WindowAnimator = WindowAnimator.shared,
         windowHistory: WindowHistory = AppDelegate.windowHistory,
         delegateProviders: [WindowManagerDelegateProvider]? = nil,
         sizeConstraint: WindowSizeConstraint = WindowSizeConstraint(),
         writeFence: WindowWriteFence = .shared) {

        self.screenDetection = screenDetection
        self.sizeConstraint = sizeConstraint
        self.windowAnimator = windowAnimator
        self.windowHistory = windowHistory
        self.placementCoordinator = WindowPlacementCoordinator(fence: writeFence, animator: windowAnimator)
        standardWindowMoverChain = [
            StandardWindowMover(),
            EdgeAlignmentWindowMover(),
            BestEffortWindowMover()
        ]
        
        fixedSizeWindowMoverChain = [
            FixedSizeWindowMover(),
            BestEffortWindowMover()
        ]

        screenSelector = ScreenSelector(screenDetection: screenDetection)

        // Gaps come first: the overlap offset is measured from the gapped frame.
        targetAdjusterChain = [
            GapTargetAdjuster(),
            OverlapOffsetTargetAdjuster()
        ]

        self.delegateProviders = delegateProviders ?? [
            CooperativeResizeDelegateProvider(windowHistory: windowHistory)
        ]
    }

    /// The first provider that applies owns the move and its admission decision.
    func moveDelegate(for request: WindowMoveRequest) -> WindowManagerDelegate? {
        for provider in delegateProviders {
            if let delegate = provider.delegate(for: request) { return delegate }
        }
        return nil
    }

    func recordAction(windowId: CGWindowID?,
                      resultingRect: CGRect,
                      action: WindowAction,
                      subAction: SubWindowAction?,
                      incrementCount: Bool = true) {
        windowHistory.recordAction(windowId: windowId, resultingRect: resultingRect, action: action, subAction: subAction, incrementCount: incrementCount)
    }
    
    func execute(_ parameters: ExecutionParameters) {
        sizeConstraint.hideWarning()
        guard let windowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement() else {
            reject(parameters)
            parameters.completion?()
            return
        }
        let windowId = parameters.windowId ?? windowElement.getWindowId()
        execute(parameters, on: windowElement, windowId: windowId,
                hasWaitedForWrites: parameters.preservesUnrelatedActions)
    }

    private func execute(_ parameters: ExecutionParameters, on windowElement: AccessibilityElement, windowId: CGWindowID?,
                         hasWaitedForWrites: Bool = false) {
        var handedOff = false
        defer { if !handedOff { parameters.completion?() } }
        if parameters.action == .restore {
            handedOff = restore(windowElement, windowId: windowId, parameters: parameters,
                                hasWaitedForWrites: hasWaitedForWrites)
            return
        }
        guard let move = planMove(windowElement, windowId: windowId, parameters: parameters) else { return }
        let targets = [move.writeTarget] + (move.delegate?.additionalWriteTargets(in: placementCoordinator.externalTargets) ?? [])
        if placementCoordinator.deferPlanningIfNeeded(for: targets, discard: parameters.completion, resume: { [self] in
            execute(parameters, on: windowElement, windowId: windowId, hasWaitedForWrites: true)
        }) {
            handedOff = true
            return
        }
        move.commitHistory()
        move.delegate?.moveDidAccept()
        guard !finishIfAlreadyAchieved(move, targets: targets) else { return }
        handedOff = true
        perform(move, targets: targets, hasWaitedForWrites: hasWaitedForWrites)
    }

    /// Tells the user an action can't be carried out.
    private func reject(_ parameters: ExecutionParameters, reason: String? = nil) {
        NSSound.beep()
        if let reason { Logger.log(reason) }
    }

    // MARK: - Planning

    /// Everything about a move that is settled before any frame is written.
    private struct PlannedMove {
        let parameters: ExecutionParameters
        let windowElement: AccessibilityElement
        let windowId: CGWindowID?
        /// The window's logical frame in AX coordinates: a pending animation's destination, or its frame.
        let currentWindowRect: CGRect
        let currentNormalizedRect: CGRect
        let pendingDestination: CGRect?
        let sourceScreens: UsableScreens
        let ignoreTodo: Bool
        let calcResult: WindowCalculationResult
        let visibleFrameOfDestinationScreen: CGRect
        let isFixedSize: Bool
        let isMovedAcrossDisplays: Bool
        let delegate: WindowManagerDelegate?
        let result: ResultParameters
        let commitHistory: () -> Void

        var action: WindowAction { parameters.action }

        var writeTarget: WindowWriteTarget {
            .init(element: windowElement, windowID: windowId)
        }

        func complete() { parameters.completion?() }
    }

    /// Returns nil, after beeping, when the action can't be applied to this window.
    private func planMove(_ windowElement: AccessibilityElement, windowId: CGWindowID?,
                          parameters: ExecutionParameters) -> PlannedMove? {
        let action = parameters.action

        guard let screens = screenSelector.screens(for: windowElement, windowId: windowId, parameters: parameters) else {
            reject(parameters, reason: "Unable to obtain usable screens")
            return nil
        }
        let usableScreens = screens.usable
        let sourceScreens = screens.source

        let pendingDestination = windowAnimator.destination(for: windowElement)
        let currentWindowRect = pendingDestination ?? windowElement.frame

        // Use only current history when calculating the target. Keep the saved
        // Restore frame intact until the delegate accepts the move.
        let previousAction = parameters.isDisplayCycle ? nil : windowId.flatMap { windowHistory.lastRectangleActions[$0] }
        let movedExternally = currentWindowRect != previousAction?.rect
        let forgetsLastAction = screens.forgetsLastAction || movedExternally
        let lastRectangleAction = forgetsLastAction ? nil : previousAction

        var calculationHistoryUpdates: [() -> Void] = []
        let commitHistory = { [windowHistory, screenSelector] in
            guard let windowId else { return }
            screenSelector.recordCursorPress(screens, action: action, windowId: windowId)
            if forgetsLastAction {
                windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            }
            if parameters.updateRestoreRect, movedExternally || windowHistory.restoreRects[windowId] == nil {
                windowHistory.restoreRects[windowId] = currentWindowRect
            }
            for update in calculationHistoryUpdates { update() }
        }

        let ignoreTodo = windowId.map { TodoManager.isTodoWindow($0) } ?? false

        if windowElement.isSheet == true
            || currentWindowRect.isNull
            || usableScreens.frameOfCurrentScreen.isNull
            || usableScreens.currentScreen.adjustedVisibleFrame(ignoreTodo).isNull {
            commitHistory()
            reject(parameters, reason: "Window is not snappable or usable screen is not valid")
            return nil
        }

        let currentNormalizedRect = currentWindowRect.screenFlipped
        let currentWindow = Window(id: windowId, rect: currentNormalizedRect)

        let windowCalculation = WindowCalculationFactory.calculationsByAction[action]

        let calculationParams = WindowCalculationParameters(window: currentWindow, usableScreens: usableScreens,
                                                            action: action, lastAction: lastRectangleAction, ignoreTodo: ignoreTodo,
                                                            updateHistory: { calculationHistoryUpdates.append($0) })
        guard var calcResult = windowCalculation?.calculate(calculationParams) else {
            commitHistory()
            reject(parameters, reason: "Nil calculation result")
            return nil
        }

        for adjuster in targetAdjusterChain {
            adjuster.adjust(&calcResult, action: action, windowId: windowId)
        }

        // Derived from the adjusted target, and deliberately not recomputed after a delegate revises it.
        let willResize = action.resizes || calcResult.rect.size != currentNormalizedRect.size
        let isFixedSize = (!windowElement.isResizable() && willResize) || windowElement.isSystemDialog == true
        let visibleFrameOfDestinationScreen = calcResult.resultingScreenFrame ?? calcResult.screen.adjustedVisibleFrame(ignoreTodo)
        let isMovedAcrossDisplays = sourceScreens.currentScreen != calcResult.screen

        let delegate = moveDelegate(for: WindowMoveRequest(calcResult: calcResult,
                                                                 windowId: windowId,
                                                                 isFixedSize: isFixedSize,
                                                                 windowElement: windowElement,
                                                                 action: action,
                                                                 source: parameters.source,
                                                                 currentFrame: currentNormalizedRect,
                                                                 screenFrame: visibleFrameOfDestinationScreen,
                                                                 sourceScreens: sourceScreens,
                                                                 destinationScreenIsCurrentScreen: !isMovedAcrossDisplays,
                                                                 lastRectangleAction: lastRectangleAction, identity: parameters.identity))

        guard delegate?.acceptsPlacement != false else {
            reject(parameters)
            return nil
        }
        if let delegate {
            calcResult = delegate.calcResult
        }

        let result = ResultParameters(windowId: windowId,
                                      action: action,
                                      windowElement: windowElement,
                                      calcResult: calcResult,
                                      usableScreens: sourceScreens,
                                      visibleFrameOfScreen: visibleFrameOfDestinationScreen,
                                      source: parameters.source,
                                      isFixedSize: isFixedSize)

        return PlannedMove(parameters: parameters,
                           windowElement: windowElement,
                           windowId: windowId,
                           currentWindowRect: currentWindowRect,
                           currentNormalizedRect: currentNormalizedRect,
                           pendingDestination: pendingDestination,
                           sourceScreens: sourceScreens,
                           ignoreTodo: ignoreTodo,
                           calcResult: calcResult,
                           visibleFrameOfDestinationScreen: visibleFrameOfDestinationScreen,
                           isFixedSize: isFixedSize,
                           isMovedAcrossDisplays: isMovedAcrossDisplays,
                           delegate: delegate,
                           result: result,
                           commitHistory: commitHistory)
    }

    /// Returns true when the window is already where the move would put it, recording that as the action.
    private func finishIfAlreadyAchieved(_ move: PlannedMove, targets: [WindowWriteTarget]) -> Bool {
        // The delegate's check records state, so it only runs without a pending destination.
        guard move.pendingDestination == nil,
              move.delegate?.isAlreadyAchieved() ?? move.currentNormalizedRect.equalTo(move.calcResult.rect)
        else { return false }

        guard placementCoordinator.acceptAlreadyAchieved(for: targets) else { return false }
        Logger.log("Window is already at its target frame")
        recordAction(windowId: move.windowId, resultingRect: move.currentWindowRect,
                     action: move.calcResult.resultingAction, subAction: move.calcResult.resultingSubAction)
        publishCompletion(result: move.result, achievedFrame: move.currentWindowRect, identity: move.parameters.identity)
        return true
    }

    // MARK: - Restore

    /// - Returns: Whether a deferred restore took over calling the completion
    private func restore(_ windowElement: AccessibilityElement, windowId: CGWindowID?,
                         parameters: ExecutionParameters, hasWaitedForWrites: Bool) -> Bool {
        guard let windowId else {
            reject(parameters)
            return false
        }
        let target = WindowWriteTarget(element: windowElement, windowID: windowId)
        guard let restoreRect = windowHistory.restoreRects[windowId] else {
            placementCoordinator.acceptRestoreWithoutTarget(for: target)
            windowHistory.lastRectangleActions.removeValue(forKey: windowId)
            return false
        }
        let access = placementCoordinator.begin(to: [target], hasWaitedForWrites: hasWaitedForWrites)
        windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        let requested = WindowMoveAnimation.forRestore(to: restoreRect, of: windowElement, source: parameters.source)
        let animation = placementCoordinator.availableAnimation(requested, for: windowElement, access: access)
        placementCoordinator.place(windowElement, animation: animation, access: access, cancellation: { [self] in
            placementCoordinator.finish(access)
            parameters.cancellation?()
        }) { [self] animatedFrame in
            defer {
                placementCoordinator.finish(access)
                parameters.completion?()
            }
            guard placementCoordinator.isCurrent(access), animatedFrame == nil else { return }
            windowElement.setFrame(restoreRect)
        }
        return true
    }

    // MARK: - Placement

    /// A planned move that has been accepted and now owns its completion.
    private struct ActivePlacement {
        let move: PlannedMove
        let access: WindowPlacementCoordinator.Access
        let animated: Bool
    }

    /// The cross-display retries: one straight away, then one once macOS has settled the window.
    private static let crossDisplayRetries: [(delay: DispatchTimeInterval?, message: String)] = [
        (nil, "Window size wasn't applied perfectly across displays. Trying again."),
        (.milliseconds(25), "Final attempt to adjust across displays.")
    ]

    private func perform(_ move: PlannedMove, targets: [WindowWriteTarget], hasWaitedForWrites: Bool) {
        let requestedAnimation = WindowMoveAnimation.forMove(of: move.windowElement, action: move.action, calcResult: move.calcResult,
                                                    screenFrame: move.visibleFrameOfDestinationScreen,
                                                    isFixedSize: move.isFixedSize,
                                                    isMovedAcrossDisplays: move.isMovedAcrossDisplays,
                                                    source: move.parameters.source)
        let access = placementCoordinator.begin(to: targets, hasWaitedForWrites: hasWaitedForWrites)
        let animation = placementCoordinator.availableAnimation(requestedAnimation, for: move.windowElement, access: access)
        let placement = ActivePlacement(move: move, access: access, animated: animation != nil)
        if animation != nil {
            recordAction(windowId: move.windowId, resultingRect: move.calcResult.rect.screenFlipped,
                         action: move.calcResult.resultingAction, subAction: move.calcResult.resultingSubAction)
        }
        placementCoordinator.place(move.windowElement, animation: animation, access: access, cancellation: { [self] in
            placementCoordinator.finish(access)
            move.parameters.cancellation?()
        }) { [self] frame in
            completePlacement(placement, animatedFrame: frame)
        }
    }

    /// Places the window, unless an animation already did, then settles it. Every path ends in one completion.
    private func completePlacement(_ placement: ActivePlacement, animatedFrame: CGRect?) {
        let move = placement.move
        guard placementCoordinator.isCurrent(placement.access) else { return end(placement) }

        // The worker already verified an animated frame. A second AX read on
        // main can stall if the target becomes busy after completion.
        let resultingRect = animatedFrame
            ?? move.delegate?.place(result: move.result) { moveWindow(toRect: $0, result: $1) }
            ?? apply(result: move.result)

        if move.isMovedAcrossDisplays {
            settleAcrossDisplays(placement, resultingRect: resultingRect, retries: Self.crossDisplayRetries[...])
        } else {
            settleOnSourceScreen(placement, resultingRect: resultingRect, animatedFrame: animatedFrame)
        }
    }

    /// Reapplies the target while macOS hasn't given the window its size on the new display.
    private func settleAcrossDisplays(_ placement: ActivePlacement, resultingRect: CGRect,
                                      retries: ArraySlice<(delay: DispatchTimeInterval?, message: String)>) {
        let move = placement.move
        guard placementCoordinator.isCurrent(placement.access) else { return end(placement) }
        guard move.calcResult.rect.size != resultingRect.size, let retry = retries.first else {
            windowMovedAcrossDisplays(windowElement: move.windowElement, windowId: move.windowId,
                                      resultingRect: resultingRect, destination: move.calcResult.screen,
                                      preservesFocus: move.parameters.preservesFocus)
            return finish(placement, resultingRect: resultingRect)
        }

        Logger.log(retry.message)
        let coordinator = placementCoordinator
        let reapply = { [weak self] in
            guard let self else {
                coordinator.finish(placement.access)
                move.complete()
                return
            }
            guard self.placementCoordinator.isCurrent(placement.access) else { return self.end(placement) }
            let frame = self.apply(result: move.result)
            self.settleAcrossDisplays(placement, resultingRect: frame, retries: retries.dropFirst())
        }
        if let delay = retry.delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: reapply)
        } else {
            reapply()
        }
    }

    private func settleOnSourceScreen(_ placement: ActivePlacement, resultingRect: CGRect, animatedFrame: CGRect?) {
        let move = placement.move
        move.delegate?.moveDidSettle(resultingRect: resultingRect,
                                      screenFrame: move.sourceScreens.currentScreen.adjustedVisibleFrame(move.ignoreTodo))
        // A delegate's cleanup can move the focused window too, so read where it ended up.
        // Otherwise the placement's own read, or the animation's verified frame, still holds.
        let settledRect = move.delegate != nil && animatedFrame == nil ? move.windowElement.frame : resultingRect
        finish(placement, resultingRect: settledRect)
    }

    private func end(_ placement: ActivePlacement) {
        placementCoordinator.finish(placement.access)
        placement.move.complete()
    }

    private func finish(_ placement: ActivePlacement, resultingRect: CGRect) {
        guard placementCoordinator.isCurrent(placement.access) else { return end(placement) }
        let move = placement.move
        postProcess(result: move.result, resultingRect: resultingRect, incrementCount: !placement.animated)
        // An unchanged frame away from the target can be a refused AX write.
        // Complete a refused write without publishing a successful placement.
        if !placement.access.followsExternalWriter || resultingRect != move.currentWindowRect
            || WindowGeometry.near(resultingRect, move.calcResult.rect.screenFlipped) {
            publishCompletion(result: move.result, achievedFrame: resultingRect, identity: move.parameters.identity)
        }
        end(placement)
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
    
    func windowMovedAcrossDisplays(windowElement: AccessibilityElement, windowId: CGWindowID?,
                                   resultingRect: CGRect, destination: NSScreen, preservesFocus: Bool) {
        if !preservesFocus {
            windowElement.bringToFront(force: true)
        }
        
        if Defaults.moveCursorAcrossDisplays.userEnabled,
           screenSelector.shouldMoveCursorAcrossDisplays(onto: destination) {
            moveCursor(to: resultingRect.centerPoint, onto: destination, windowId: windowId)
        }
    }

    private func moveCursor(to point: CGPoint, onto screen: NSScreen, windowId: CGWindowID?) {
        warpCursor(to: point)
        screenSelector.didMoveCursor(onto: screen, windowId: windowId)
    }

    func warpCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    private func publishCompletion(result: ResultParameters, achievedFrame: CGRect, identity: WindowActionIdentity) {
        guard result.action != .restore, WindowGeometry.valid(achievedFrame) else { return }
        Notification.Name.windowActionCompleted.post(object: WindowActionCompletion(result: result, achievedFrame: achievedFrame, identity: identity))
    }

    func postProcess(result: ResultParameters, resultingRect: CGRect, incrementCount: Bool = true) {
        let calcResult = result.calcResult

        sizeConstraint.warnIfExceeded(result, resultingRect: resultingRect)
        
        if Defaults.moveCursor.userEnabled, result.source == .keyboardShortcut {
            moveCursor(to: resultingRect.centerPoint, onto: calcResult.screen, windowId: result.windowId)
        }
        
        recordAction(windowId: result.windowId, resultingRect: resultingRect, action: calcResult.resultingAction, subAction: calcResult.resultingSubAction, incrementCount: incrementCount)

        let requestedRect = calcResult.rect.screenFlipped
        var evidence: [String: Any] = ["action": calcResult.resultingAction.name,
                                      "achieved": [resultingRect.minX, resultingRect.minY, resultingRect.width, resultingRect.height],
                                      "requested": [requestedRect.minX, requestedRect.minY, requestedRect.width, requestedRect.height]]
        if let windowId = result.windowId {
            evidence["windowID"] = windowId
            if let restore = windowHistory.restoreRects[windowId] {
                evidence["restore"] = [restore.minX, restore.minY, restore.width, restore.height]
            }
        }
        DiagnosticTrace.event("window-action-achieved", fields: evidence)
        
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
    
    init(action: WindowAction, subAction: SubWindowAction? = nil, rect: CGRect, count: Int = 0) {
        self.action = action
        self.subAction = subAction
        self.rect = rect
        self.count = count
    }
}

struct ExecutionParameters {
    let identity: WindowActionIdentity
    let action: WindowAction
    let updateRestoreRect: Bool
    let screen: NSScreen?
    let windowElement: AccessibilityElement?
    let windowId: CGWindowID?
    let source: ExecutionSource
    /// For a window that needn't be the focused one, which acting on it
    /// mustn't bring forward.
    let preservesFocus: Bool
    let completion: (() -> Void)?
    // Cancellation cleanup must not run placement completion or fallback work.
    let cancellation: (() -> Void)?
    /// A display-cycle repeat calculates a fresh action on the chosen display.
    let isDisplayCycle: Bool
    /// A command resumed after another writer must leave unrelated actions running.
    let preservesUnrelatedActions: Bool

    init(_ action: WindowAction, updateRestoreRect: Bool = true, screen: NSScreen? = nil, windowElement: AccessibilityElement? = nil, windowId: CGWindowID? = nil, source: ExecutionSource = .keyboardShortcut, preservesFocus: Bool = false, completion: (() -> Void)? = nil, cancellation: (() -> Void)? = nil, isDisplayCycle: Bool = false, identity: WindowActionIdentity = WindowActionIdentity(), preservesUnrelatedActions: Bool = false) {
        self.identity = identity
        self.action = action
        self.updateRestoreRect = updateRestoreRect
        self.screen = screen
        self.windowElement = windowElement
        self.windowId = windowId
        self.source = source
        self.preservesFocus = preservesFocus
        self.completion = completion
        self.cancellation = cancellation
        self.isDisplayCycle = isDisplayCycle
        self.preservesUnrelatedActions = preservesUnrelatedActions
    }
}

enum ExecutionSource {
    case keyboardShortcut, dragToSnap, menuItem, url, titleBar, newWindow

}
