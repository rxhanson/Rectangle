import Cocoa

/// Supplies fitted targets alongside the manager's other ordered providers.
/// Completed placements supply the actual reference frame, including display retries.
final class SnappedWindowFitProvider: WindowManagerDelegateProvider {
    private let enabled: () -> Bool
    private let session: () -> SnappedWindowFitSession
    private let resolve: (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var stagedAnchor: (action: WindowAction, source: ExecutionSource, anchor: SnappedWindowFitOpportunity?)?
    private var recordsCompletions = true
    private var fittedWindow: AccessibilityElement?

    init(enabled: @escaping () -> Bool = { Defaults.fitBesideSnappedWindows.enabled },
         session: @escaping () -> SnappedWindowFitSession = { .shared },
         resolve: @escaping (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution = { request, anchor in
             SnappedWindowFit.resolve(action: request.calcResult.resultingAction,
                                      window: Window(id: request.windowId, rect: request.currentFrame),
                                      initialTarget: request.calcResult.initialRect, target: request.calcResult.rect,
                                      screenFrame: request.screenFrame, opportunity: anchor)
         },
         notifications: NotificationCenter = .default) {
        self.enabled = enabled
        self.session = session
        self.resolve = resolve
        self.notifications = notifications
        observers.append(Notification.Name.windowActionWillExecute.onPost(center: notifications) { [weak self] note in
            self?.stage(note.object as? ExecutionParameters)
        })
        observers.append(Notification.Name.windowActionCompleted.onPost(center: notifications) { [weak self] note in
            guard let self, self.enabled(), self.recordsCompletions,
                  let completion = note.object as? WindowActionCompletion else { return }
            if self.fittedWindow === completion.result.windowElement {
                self.fittedWindow = nil
                return
            }
            self.session().record(result: completion.result, frame: completion.achievedFrame)
        })
        for name in [Notification.Name.configImported, .fitBesideSnappedWindowsChanged] {
            observers.append(name.onPost(center: notifications) { [weak self] _ in self?.stage(nil) })
        }
    }

    deinit { observers.forEach(notifications.removeObserver) }

    private func stage(_ parameters: ExecutionParameters?) {
        stagedAnchor = nil
        recordsCompletions = parameters != nil && parameters?.action != .restore
        guard enabled() else { return }
        guard let parameters else { session().clear(); return }
        let anchor = session().take()
        if parameters.action != .restore {
            stagedAnchor = (parameters.action, parameters.source, anchor)
        }
    }

    func delegate(for request: WindowMoveRequest) -> WindowManagerDelegate? {
        let staged = stagedAnchor
        stagedAnchor = nil
        fittedWindow = nil
        guard enabled() else { return nil }
        let anchor: SnappedWindowFitOpportunity?
        if let staged, staged.action == request.action, staged.source == request.source {
            anchor = staged.anchor
        } else {
            anchor = session().take()
        }
        guard let anchor, !request.isFixedSize, !request.action.allowedToExtendOutsideCurrentScreenArea,
              request.action.resizes || request.calcResult.rect.size != request.currentFrame.size else { return nil }
        switch resolve(request, anchor) {
        case .unchanged:
            return nil
        case .noRoom:
            return FittedMove(calcResult: request.calcResult, acceptsPlacement: false)
        case .fit(let plan):
            fittedWindow = request.windowElement
            var result = request.calcResult
            result.initialRect = plan.unpaddedTarget(for: result)
            result.rect = plan.target.screenFlipped
            return FittedMove(calcResult: result)
        }
    }
}

private struct FittedMove: WindowManagerDelegate {
    let calcResult: WindowCalculationResult
    var acceptsPlacement = true
}
