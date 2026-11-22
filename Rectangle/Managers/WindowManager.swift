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
    private let placementServices: WindowPlacementServices
    private let placementOwnership = WindowPlacementOwnership()
    private var executionID = 0

    init(screenDetection: ScreenDetection = ScreenDetection(),
         windowAnimator: WindowAnimator = WindowAnimator.shared,
         windowHistory: WindowHistory = AppDelegate.windowHistory,
         delegateProviders: [WindowManagerDelegateProvider]? = nil,
         sizeConstraint: WindowSizeConstraint = WindowSizeConstraint(),
         placementServices: WindowPlacementServices? = nil) {

        self.screenDetection = screenDetection
        self.sizeConstraint = sizeConstraint
        self.windowAnimator = windowAnimator
        self.windowHistory = windowHistory
        self.placementServices = placementServices ?? WindowPlacementServices(animator: windowAnimator)
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
        var handedOff = false
        defer { if !handedOff { parameters.completion?() } }
        sizeConstraint.hideWarning()

        guard let windowElement = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement()
        else { return reject(parameters) }
        let windowId = parameters.windowId ?? windowElement.getWindowId()
        if parameters.action == .restore {
            handedOff = restore(windowElement, windowId: windowId, parameters: parameters)
            return
        }
        guard let move = planMove(windowElement, windowId: windowId, parameters: parameters) else { return }
        move.commitHistory()
        move.delegate?.moveDidAccept()
        Notification.Name.windowPlacementAccepted.post(
            object: WindowPlacementAcceptance(requestID: move.parameters.requestID, result: move.result))
        guard !finishIfAlreadyAchieved(move) else { return }
        handedOff = true
        perform(move)
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
        let transaction: WindowPlacementTransaction?
        let result: ResultParameters
        let commitHistory: () -> Void

        var action: WindowAction { parameters.action }

        func publishSettlement(_ frame: CGRect, alreadyAchieved: Bool = false) {
            WindowPlacementSettlement(requestID: parameters.requestID, result: result,
                                      achievedFrame: frame,
                                      alreadyAchieved: alreadyAchieved).publish()
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

        let previous = windowId.flatMap { windowHistory.lastRectangleActions[$0] }
        let movedExternally = currentWindowRect != previous?.rect
        let forgetLastAction = screens.forgetsLastAction || movedExternally
        let lastRectangleAction = forgetLastAction ? nil : previous
        let commitHistory = { [windowHistory] in
            guard let windowId else { return }
            if forgetLastAction { windowHistory.lastRectangleActions.removeValue(forKey: windowId) }
            if parameters.updateRestoreRect, movedExternally || windowHistory.restoreRects[windowId] == nil {
                windowHistory.restoreRects[windowId] = currentWindowRect
            }
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

        let calculationParams = WindowCalculationParameters(window: currentWindow, usableScreens: usableScreens, action: action, lastAction: lastRectangleAction, ignoreTodo: ignoreTodo)
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
                                                                 lastRectangleAction: lastRectangleAction,
                                                                 requestID: parameters.requestID))

        guard delegate?.acceptsPlacement != false else {
            reject(parameters)
            return nil
        }
        if let delegate { calcResult = delegate.calcResult }

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
                           transaction: delegate?.placementCondition.map {
                               WindowPlacementTransaction(condition: $0, result: result, history: windowHistory,
                                   previousAction: previous,
                                   previousRestore: windowId.flatMap { windowHistory.restoreRects[$0] },
                                   services: placementServices)
                           },
                           result: result,
                           commitHistory: commitHistory)
    }

    /// Returns true when the window is already where the move would put it, recording that as the action.
    private func finishIfAlreadyAchieved(_ move: PlannedMove) -> Bool {
        // The delegate's check records state, so it only runs without a pending destination.
        guard move.pendingDestination == nil,
              move.delegate?.isAlreadyAchieved() ?? move.currentNormalizedRect.equalTo(move.calcResult.rect)
        else { return false }

        guard move.transaction?.isValid() != false else { return false }
        // An accepted no-op owns the current frame and supersedes recovery for
        // this window while pending work on other windows keeps its generation.
        placementOwnership.finish(placementOwnership.claim(move.windowElement, id: move.windowId))
        Logger.log("Window is already at its target frame")
        recordAction(windowId: move.windowId, resultingRect: move.currentWindowRect,
                     action: move.calcResult.resultingAction, subAction: move.calcResult.resultingSubAction)
        move.publishSettlement(move.currentWindowRect, alreadyAchieved: true)
        return true
    }

    // MARK: - Supersession

    private func nextExecutionID() -> Int {
        executionID &+= 1
        return executionID
    }

    private func isCurrent(_ id: Int) -> Bool { executionID == id }

    // MARK: - Restore

    /// - Returns: Whether a deferred restore took over calling the completion
    private func restore(_ windowElement: AccessibilityElement, windowId: CGWindowID?,
                         parameters: ExecutionParameters) -> Bool {
        guard let windowId else {
            reject(parameters)
            return false
        }
        var handedOff = false
        if let restoreRect = windowHistory.restoreRects[windowId] {
            let currentExecutionID = nextExecutionID()
            let ownership = placementOwnership.claim(windowElement, id: windowId)
            handedOff = true
            let animation = WindowMoveAnimation.forRestore(to: restoreRect, of: windowElement, source: parameters.source)
            place(windowElement, animation: animation, cancellation: {
                self.placementOwnership.finish(ownership)
                parameters.cancellation?()
            }) { [weak self] animatedFrame in
                defer {
                    self?.placementOwnership.finish(ownership)
                    parameters.completion?()
                }
                guard let self, ownership.isCurrent, self.isCurrent(currentExecutionID), animatedFrame == nil else { return }
                windowElement.setFrame(restoreRect)
            }
        } else {
            placementOwnership.finish(placementOwnership.claim(windowElement, id: windowId))
        }
        windowHistory.lastRectangleActions.removeValue(forKey: windowId)
        return handedOff
    }

    // MARK: - Placement

    /// A planned move that has been accepted and now owns its completion.
    private struct ActivePlacement {
        let move: PlannedMove
        let executionID: Int
        let ownership: WindowPlacementOwnership.Token
        let animated: Bool
    }

    /// The cross-display retries: one straight away, then one once macOS has settled the window.
    private static let crossDisplayRetries: [(delay: DispatchTimeInterval?, message: String)] = [
        (nil, "Window size wasn't applied perfectly across displays. Trying again."),
        (.milliseconds(25), "Final attempt to adjust across displays.")
    ]

    private func perform(_ move: PlannedMove) {
        let animation = WindowMoveAnimation.forMove(of: move.windowElement, action: move.action, calcResult: move.calcResult,
                                                    screenFrame: move.visibleFrameOfDestinationScreen,
                                                    isFixedSize: move.isFixedSize,
                                                    isMovedAcrossDisplays: move.isMovedAcrossDisplays,
                                                    source: move.parameters.source)
        let placement = ActivePlacement(move: move, executionID: nextExecutionID(),
                                        ownership: placementOwnership.claim(move.windowElement, id: move.windowId),
                                        animated: animation != nil)
        if let transaction = move.transaction {
            transaction.start(animated: animation != nil,
                              isCurrent: { self.isCurrent(placement) },
                              ownsWindow: { placement.ownership.isCurrent },
                              onEnd: { self.end(placement) },
                              onCancel: { self.cancel(placement, conditionFailed: $0) }) { cancelled in
                self.place(move.windowElement, animation: animation, cancellation: cancelled) { frame in
                    self.completePlacement(placement, animatedFrame: frame)
                }
            }
        } else {
            if animation != nil {
                recordAction(windowId: move.windowId, resultingRect: move.calcResult.rect.screenFlipped,
                             action: move.calcResult.resultingAction, subAction: move.calcResult.resultingSubAction)
            }
            place(move.windowElement, animation: animation, cancellation: { self.cancel(placement) }) { frame in
                self.completePlacement(placement, animatedFrame: frame)
            }
        }
    }

    /// Runs `completion` straight away in the usual case. Only an animation, or a placement that
    /// must wait for an earlier animation to stop writing, goes through the animator.
    /// - Parameter completion: Receives the frame an animation achieved, or nil to write the frame
    private func place(_ windowElement: AccessibilityElement, animation: WindowMoveAnimation?,
                       cancellation: (() -> Void)?, completion: @escaping (CGRect?) -> Void) {
        guard animation != nil || !windowAnimator.isIdle else { return completion(nil) }
        placementServices.animate(windowElement, animation, cancellation, completion)
    }

    /// Places the window, unless an animation already did, then settles it. Every path ends in one completion.
    private func completePlacement(_ placement: ActivePlacement, animatedFrame: CGRect?) {
        let move = placement.move
        guard move.transaction?.beginSettlement() != false else { return }
        guard isCurrent(placement) else { return end(placement) }

        // The worker already verified an animated frame. A second AX read on
        // main can stall if the target becomes busy after completion.
        let whileOwned = ownershipCheck(for: placement)
        let resultingRect = animatedFrame
            ?? move.delegate?.place(result: move.result) { moveWindow(toRect: $0, result: $1, whileOwned: whileOwned) }
            ?? apply(result: move.result, whileOwned: whileOwned)

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
        guard isCurrent(placement) else { return end(placement) }
        guard move.transaction?.validate() != false else { return }
        guard move.calcResult.rect.size != resultingRect.size, let retry = retries.first else {
            windowMovedAcrossDisplays(windowElement: move.windowElement, windowId: move.windowId,
                                      resultingRect: resultingRect, destination: move.calcResult.screen,
                                      preservesFocus: move.parameters.preservesFocus)
            return finish(placement, resultingRect: resultingRect)
        }

        Logger.log(retry.message)
        let reapply = { [weak self] in
            guard let self else { return move.complete() }
            guard self.isCurrent(placement) else { return self.end(placement) }
            guard move.transaction?.validate() != false else { return }
            let frame = self.apply(result: move.result, whileOwned: self.ownershipCheck(for: placement))
            self.settleAcrossDisplays(placement, resultingRect: frame, retries: retries.dropFirst())
        }
        if let delay = retry.delay {
            let stopObserving = move.transaction?.observeEnvironmentDuringRetry()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                defer { stopObserving?() }
                reapply()
            }
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
        let settledRect = move.delegate?.cleanupCanMoveWindow == true && animatedFrame == nil ? move.windowElement.frame : resultingRect
        finish(placement, resultingRect: settledRect)
    }

    private func isCurrent(_ placement: ActivePlacement) -> Bool {
        placement.ownership.isCurrent && isCurrent(placement.executionID)
    }

    private func ownershipCheck(for placement: ActivePlacement) -> (() -> Bool)? {
        guard placement.move.transaction != nil else { return nil }
        return { self.isCurrent(placement) }
    }

    private func cancel(_ placement: ActivePlacement, conditionFailed: Bool = false) {
        guard placement.move.transaction?.finish() != false else { return }
        placementOwnership.finish(placement.ownership)
        let parameters = placement.move.parameters
        let cancellation = parameters.cancellation ?? (conditionFailed ? parameters.completion : nil)
        cancellation?()
    }

    private func end(_ placement: ActivePlacement) {
        guard placement.move.transaction?.finish() != false else { return }
        placementOwnership.finish(placement.ownership)
        placement.move.complete()
    }

    private func finish(_ placement: ActivePlacement, resultingRect: CGRect) {
        guard isCurrent(placement) else { return end(placement) }
        let move = placement.move
        guard move.transaction?.canCommit(resultingRect) != false else { return }
        postProcess(result: move.result, resultingRect: resultingRect, incrementCount: !placement.animated || move.transaction != nil)
        // An unchanged frame away from the target can be a refused AX write.
        // Complete a refused write without publishing a successful placement.
        if isCurrent(placement),
           resultingRect != move.currentWindowRect
            || WindowGeometry.near(resultingRect, move.calcResult.rect.screenFlipped) {
            move.publishSettlement(resultingRect)
        }
        end(placement)
    }

    
    /// Move/resize a window based on the calculation results.
    /// - Returns: The rect of the window after applying the window action
    func apply(result: ResultParameters, whileOwned: (() -> Bool)? = nil) -> CGRect {
        let newRect = result.calcResult.rect
        if !result.windowElement.frame.screenFlipped.equalTo(newRect) {
            moveWindow(toRect: newRect, result: result, whileOwned: whileOwned)
        }
        return result.windowElement.frame
    }

    func moveWindow(toRect rect: CGRect, result: ResultParameters, whileOwned: (() -> Bool)? = nil) {
        let windowMoverChain = result.isFixedSize
        ? fixedSizeWindowMoverChain
        : standardWindowMoverChain
        for windowMover in windowMoverChain {
            guard whileOwned?() != false else { return }
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
    let requestID: UUID

    init(_ action: WindowAction, updateRestoreRect: Bool = true, screen: NSScreen? = nil, windowElement: AccessibilityElement? = nil, windowId: CGWindowID? = nil, source: ExecutionSource = .keyboardShortcut, preservesFocus: Bool = false, completion: (() -> Void)? = nil, cancellation: (() -> Void)? = nil, requestID: UUID = UUID()) {
        self.action = action
        self.updateRestoreRect = updateRestoreRect
        self.screen = screen
        self.windowElement = windowElement
        self.windowId = windowId
        self.source = source
        self.preservesFocus = preservesFocus
        self.completion = completion
        self.cancellation = cancellation
        self.requestID = requestID
    }
}

enum ExecutionSource {
    case keyboardShortcut, dragToSnap, menuItem, url, titleBar, newWindow

}
