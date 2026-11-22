import Cocoa

/// Uses the selected move delegate to supply a fitted target or observe the
/// actual frame of an ordinary snap, including cooperative placement.
final class SnappedWindowFitProvider: WindowManagerDelegateProvider {
    private let fallback: WindowManagerDelegateProvider?
    private let enabled: () -> Bool
    private let session: () -> SnappedWindowFitSession
    private let resolve: (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution
    private let validateNeighbor: (SnappedWindowFit) -> Bool
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var stagedAnchor: (action: WindowAction, source: ExecutionSource, anchor: SnappedWindowFitOpportunity?)?
    private var command = UUID()
    private var observation = UUID()
    private var crossDisplaySnap: WindowMoveRequest?

    init(fallback: WindowManagerDelegateProvider? = nil,
         enabled: @escaping () -> Bool = { Defaults.fitBesideSnappedWindows.enabled },
         session: @escaping () -> SnappedWindowFitSession = { .shared },
         resolve: @escaping (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution = { request, anchor in
             SnappedWindowFit.resolve(action: request.calcResult.resultingAction,
                                      window: Window(id: request.windowId, rect: request.currentFrame),
                                      initialTarget: request.calcResult.initialRect, target: request.calcResult.rect,
                                      screenFrame: request.screenFrame, opportunity: anchor)
         },
         validateNeighbor: @escaping (SnappedWindowFit) -> Bool = { $0.neighborIsUnchanged() },
         notifications: NotificationCenter = .default) {
        self.fallback = fallback
        self.enabled = enabled
        self.session = session
        self.resolve = resolve
        self.validateNeighbor = validateNeighbor
        self.notifications = notifications

        observers.append(Notification.Name.windowActionWillExecute.onPost(center: notifications) { [weak self] note in
            self?.stage(note.object as? ExecutionParameters)
        })
        observers.append(Notification.Name.windowActionCompleted.onPost(center: notifications) { [weak self] note in
            guard let completion = note.object as? WindowActionCompletion else { return }
            self?.recordCrossDisplayCompletion(completion)
        })
        for name in [Notification.Name.configImported, .fitBesideSnappedWindowsChanged] {
            observers.append(name.onPost(center: notifications) { [weak self] _ in
                self?.stage(nil)
            })
        }
    }

    deinit { observers.forEach(notifications.removeObserver) }

    private func stage(_ parameters: ExecutionParameters?) {
        command = UUID()
        stagedAnchor = nil
        if parameters == nil || parameters?.action == .restore { crossDisplaySnap = nil }
        guard enabled() else { return }
        guard let parameters else {
            observation = UUID()
            session().clear()
            return
        }
        let anchor = session().take(allowPreview: parameters.source == .dragToSnap)
        stagedAnchor = (parameters.action, parameters.source, anchor)
        if parameters.action == .restore {
            observation = UUID()
            stagedAnchor = nil
        }
    }

    func delegate(for request: WindowMoveRequest) -> WindowManagerDelegate? {
        let staged = stagedAnchor
        stagedAnchor = nil
        command = UUID()
        let currentCommand = command
        guard enabled() else { return fallback?.delegate(for: request) }

        let anchor: SnappedWindowFitOpportunity?
        if let staged, staged.action == request.action, staged.source == request.source {
            anchor = staged.anchor
        } else {
            anchor = session().take(allowPreview: request.source == .dragToSnap)
        }

        if let anchor, !request.isFixedSize, !request.action.allowedToExtendOutsideCurrentScreenArea,
           request.action.resizes || request.calcResult.rect.size != request.currentFrame.size {
            switch resolve(request, anchor) {
            case .unchanged:
                break
            case .noRoom:
                return RejectedFitMove(calcResult: request.calcResult)
            case .fit(let plan):
                if validateNeighbor(plan) {
                    var result = request.calcResult
                    result.initialRect = plan.unpaddedTarget(for: result)
                    result.rect = plan.target.screenFlipped
                    observation = UUID()
                    crossDisplaySnap = nil
                    return ExistingHookFitMove(result, request: request) { [weak self] in
                        guard let self, self.command == currentCommand else { return nil }
                        return self.enabled() && self.validateNeighbor(plan)
                    }
                }
            }
        }

        let downstream = fallback?.delegate(for: request)
        let currentObservation = observation
        crossDisplaySnap = request.destinationScreenIsCurrentScreen ? nil : request
        return ObservedSnap(request: request, downstream: downstream) { [weak self] result, frame in
            guard let self, self.enabled(), self.observation == currentObservation else { return }
            self.session().record(result: result, frame: frame)
        }
    }

    private func recordCrossDisplayCompletion(_ completion: WindowActionCompletion) {
        let result = completion.result
        // An unrelated placement may finish while the display retry is pending.
        guard let snap = crossDisplaySnap, result.windowElement === snap.windowElement,
              result.action == snap.action, result.source == snap.source,
              result.calcResult.screen == snap.calcResult.screen else { return }
        crossDisplaySnap = nil
        if enabled() { session().record(result: result, frame: completion.achievedFrame) }
    }
}

private struct ObservedSnap: WindowManagerDelegate {
    let request: WindowMoveRequest
    let downstream: WindowManagerDelegate?
    let record: (ResultParameters, CGRect) -> Void

    var calcResult: WindowCalculationResult { downstream?.calcResult ?? request.calcResult }
    var acceptsPlacement: Bool { downstream?.acceptsPlacement ?? true }

    func moveDidAccept() { downstream?.moveDidAccept() }

    func additionalWriteTargets(in candidates: [WindowWriteFence.Target]) -> [WindowWriteFence.Target] {
        downstream?.additionalWriteTargets(in: candidates) ?? []
    }

    func isAlreadyAchieved() -> Bool? {
        let achieved = downstream?.isAlreadyAchieved()
        if achieved ?? request.currentFrame.equalTo(calcResult.rect) {
            recordFrame(request.currentFrame.screenFlipped)
        }
        return achieved
    }

    func place(result: ResultParameters, moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect? {
        downstream?.place(result: result, moveWindow: moveWindow)
    }

    func moveDidSettle(resultingRect: CGRect, screenFrame: CGRect) {
        downstream?.moveDidSettle(resultingRect: resultingRect, screenFrame: screenFrame)
        let achieved = downstream != nil && !request.windowElement.canAnimate ? request.windowElement.frame : resultingRect
        recordFrame(achieved)
    }

    private func recordFrame(_ frame: CGRect) {
        let result = ResultParameters(windowId: request.windowId, action: request.action,
                                      windowElement: request.windowElement, calcResult: calcResult,
                                      usableScreens: request.sourceScreens, visibleFrameOfScreen: request.screenFrame,
                                      source: request.source, isFixedSize: request.isFixedSize)
        record(result, frame)
    }
}

private struct RejectedFitMove: WindowManagerDelegate {
    let calcResult: WindowCalculationResult
    let acceptsPlacement = false
}

private final class ExistingHookFitMove: WindowManagerDelegate {
    let calcResult: WindowCalculationResult
    private let neighborIsCurrent: () -> Bool?
    private var monitor: Timer?

    init(_ calcResult: WindowCalculationResult, request: WindowMoveRequest,
         neighborIsCurrent: @escaping () -> Bool?) {
        self.calcResult = calcResult
        self.neighborIsCurrent = neighborIsCurrent

        let animator = WindowAnimator.shared
        let window = request.windowElement
        let destination = calcResult.rect.screenFlipped
        guard WindowMoveAnimation.forMove(of: window, action: request.action, calcResult: calcResult,
                                          screenFrame: request.screenFrame, isFixedSize: request.isFixedSize,
                                          isMovedAcrossDisplays: !request.destinationScreenIsCurrentScreen,
                                          source: request.source) != nil else { return }

        let origin = window.frame
        // Wait for the animation worker to stop before restoring the physical
        // origin. Recheck command ownership just before issuing the AX write.
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self, let valid = self.neighborIsCurrent(),
                  animator.destination(for: window) == destination else { timer.invalidate(); return }
            if !valid {
                timer.invalidate()
                animator.cancel(for: window)
                animator.afterPendingWrites {
                    guard neighborIsCurrent() == false else { return }
                    window.setFrame(origin)
                    guard let id = request.windowId else { return }
                    let achievedOrigin = WindowGeometry.matches(window.frame, origin)
                    AppDelegate.windowHistory.lastRectangleActions[id] = achievedOrigin ? request.lastRectangleAction : nil
                    if !achievedOrigin { AppDelegate.windowHistory.restoreRects[id] = origin }
                }
            }
        }
        monitor = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { monitor?.invalidate() }

    func place(result: ResultParameters, moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect? {
        guard neighborIsCurrent() == true else { return result.windowElement.frame }
        return nil
    }

    func moveDidSettle(resultingRect: CGRect, screenFrame: CGRect) { monitor?.invalidate() }
}
