import Cocoa

/// Supplies fitted targets alongside the manager's other ordered providers.
/// Completed placements supply the actual reference frame, including display retries.
final class SnappedWindowFitProvider: WindowManagerDelegateProvider {
    private let enabled: () -> Bool
    private let session: () -> SnappedWindowFitSession
    private let resolve: (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private final class Reference {
        let anchor: SnappedWindowFitOpportunity?
        let order: Int
        var fitted = false
        init(_ anchor: SnappedWindowFitOpportunity?, order: Int) {
            self.anchor = anchor
            self.order = order
        }
    }
    // A deferred command keeps the reference it consumed at dispatch. Weak keys
    // release that state when the command and its planning attempts are gone.
    private let references = NSMapTable<WindowActionIdentity, Reference>(keyOptions: .weakMemory,
                                                                       valueOptions: .strongMemory)
    private var commandOrder = 0
    private var resetOrder = 0
    // A late accepted snap may establish a reference after a rejection, but
    // cannot replace a newer reference or cross a Restore/reset boundary.
    private var referenceOrder = 0

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
            // A fitted placement completes the opportunity. Ordinary snaps establish the next reference.
            guard let self, self.enabled(),
                  let completion = note.object as? WindowActionCompletion,
                  let reference = self.references.object(forKey: completion.identity), !reference.fitted,
                  reference.order > self.resetOrder, reference.order >= self.referenceOrder else { return }
            self.session().record(result: completion.result, frame: completion.achievedFrame)
            if self.session().current != nil { self.referenceOrder = reference.order }
        })
        for name in [Notification.Name.configImported, .fitBesideSnappedWindowsChanged] {
            observers.append(name.onPost(center: notifications) { [weak self] _ in self?.stage(nil) })
        }
    }

    deinit { observers.forEach(notifications.removeObserver) }

    private func stage(_ parameters: ExecutionParameters?) {
        commandOrder += 1
        guard let parameters, enabled() else {
            resetOrder = commandOrder
            references.removeAllObjects()
            session().clear()
            return
        }
        let anchor = session().take()
        if parameters.action == .restore { resetOrder = commandOrder }
        references.setObject(Reference(parameters.action == .restore ? nil : anchor, order: commandOrder),
                             forKey: parameters.identity)
    }

    func delegate(for request: WindowMoveRequest) -> WindowManagerDelegate? {
        guard enabled() else { return nil }
        let reference: Reference
        if let staged = references.object(forKey: request.identity) {
            reference = staged
        } else {
            commandOrder += 1
            reference = Reference(session().take(), order: commandOrder)
            references.setObject(reference, forKey: request.identity)
        }
        let anchor = reference.anchor
        guard let anchor, !request.isFixedSize, !request.action.allowedToExtendOutsideCurrentScreenArea,
              request.action.resizes || request.calcResult.rect.size != request.currentFrame.size else { return nil }
        switch resolve(request, anchor) {
        case .unchanged:
            return nil
        case .noRoom:
            return FittedMove(calcResult: request.calcResult, acceptsPlacement: false)
        case .fit(let plan):
            reference.fitted = true
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
