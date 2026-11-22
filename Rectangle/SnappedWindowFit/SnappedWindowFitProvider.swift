import Cocoa

/// Keeps the first window as an observation. Fit claims only the incoming window's
/// complementary snap, so ordinary movement retains the cooperative delegate.
final class SnappedWindowFitProvider: WindowManagerDelegateProvider {
    private let enabled: () -> Bool
    private let session: () -> SnappedWindowFitSession
    private let resolve: (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution
    private let validateNeighbor: (SnappedWindowFit) -> Bool
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var dispatchedAnchor: (requestID: UUID, opportunity: SnappedWindowFitOpportunity?)?
    private var pendingAnchorRequestID: UUID?
    private var claimedRequestID: UUID?

    init(enabled: @escaping () -> Bool = { Defaults.fitBesideSnappedWindows.enabled },
         session: @escaping () -> SnappedWindowFitSession = { .shared },
         resolve: @escaping (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution = { request, anchor in
             SnappedWindowFit.resolve(action: request.calcResult.resultingAction,
                                      window: Window(id: request.windowId, rect: request.currentFrame),
                                      initialTarget: request.calcResult.initialRect, target: request.calcResult.rect,
                                      screenFrame: request.screenFrame, opportunity: anchor)
         },
         validateNeighbor: @escaping (SnappedWindowFit) -> Bool = { $0.neighborIsUnchanged() },
         notifications: NotificationCenter = .default) {
        self.enabled = enabled
        self.session = session
        self.resolve = resolve
        self.validateNeighbor = validateNeighbor
        self.notifications = notifications
    }

    deinit { observers.forEach(notifications.removeObserver) }

    func delegate(for request: WindowMoveRequest) -> WindowManagerDelegate? {
        guard enabled() else { return nil }
        startObserving()
        let anchor: SnappedWindowFitOpportunity?
        if let dispatchedAnchor, dispatchedAnchor.requestID == request.requestID {
            anchor = dispatchedAnchor.opportunity
        } else {
            anchor = session().take(allowPreview: request.source == .dragToSnap)
        }
        dispatchedAnchor = nil
        guard let anchor, !request.isFixedSize, !request.action.allowedToExtendOutsideCurrentScreenArea,
              request.action.resizes || request.calcResult.rect.size != request.currentFrame.size
        else { return nil }

        switch resolve(request, anchor) {
        case .unchanged: return nil
        case .noRoom: return RejectedFitMove(calcResult: request.calcResult)
        case .fit(let plan):
            guard validateNeighbor(plan) else { return nil }
            claimedRequestID = request.requestID
            var result = request.calcResult
            result.initialRect = plan.unpaddedTarget(for: result)
            result.rect = plan.target.screenFlipped
            return SnappedWindowFitMove(result, notifications: notifications) { [enabled, validateNeighbor] in
                enabled() && validateNeighbor(plan)
            }
        }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        // The dispatcher can consume a command before WindowManager sees it. Take
        // the opportunity on intent; only that command's planning may use it.
        observers.append(Notification.Name.windowActionWillExecute.onPost(center: notifications) { [weak self] note in
            guard let self else { return }
            guard self.enabled() else { self.dispatchedAnchor = nil; return }
            guard let parameters = note.object as? ExecutionParameters else {
                // Minimize has no placement request and may run before a previous snap settles.
                self.dispatchedAnchor = nil
                self.pendingAnchorRequestID = nil
                self.session().clear()
                return
            }
            let opportunity = self.session().take(allowPreview: parameters.source == .dragToSnap)
            self.dispatchedAnchor = (parameters.requestID, opportunity)
        })
        // A rejected command leaves an earlier, accepted placement running.
        observers.append(Notification.Name.windowPlacementAccepted.onPost(center: notifications) { [weak self] note in
            guard let self, self.enabled(), let accepted = note.object as? WindowPlacementAcceptance else { return }
            self.pendingAnchorRequestID = self.claimedRequestID == accepted.requestID ? nil : accepted.requestID
            self.claimedRequestID = nil
        })
        observers.append(Notification.Name.windowPlacementSettled.onPost(center: notifications) { [weak self] note in
            guard let self, let settled = note.object as? WindowPlacementSettlement,
                  self.enabled(), settled.requestID == self.pendingAnchorRequestID else { return }
            self.pendingAnchorRequestID = nil
            self.session().record(result: settled.result, frame: settled.achievedFrame)
        })
        for name in [Notification.Name.configImported, .fitBesideSnappedWindowsChanged] {
            observers.append(name.onPost(center: notifications) { [weak self] _ in
                guard let self else { return }
                self.dispatchedAnchor = nil
                self.pendingAnchorRequestID = nil
                self.claimedRequestID = nil
                if !self.enabled() {
                    self.observers.forEach(self.notifications.removeObserver)
                    self.observers.removeAll()
                }
            })
        }
    }
}

private final class SnappedWindowFitMove: WindowManagerDelegate, WindowPlacementCondition {
    let calcResult: WindowCalculationResult
    let cleanupCanMoveWindow = false
    var placementCondition: WindowPlacementCondition? { self }
    private let notifications: NotificationCenter
    private let neighborIsCurrent: () -> Bool
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var invalidation: WindowPlacementInvalidation?

    init(_ calcResult: WindowCalculationResult, notifications: NotificationCenter,
         neighborIsCurrent: @escaping () -> Bool) {
        self.calcResult = calcResult
        self.notifications = notifications
        self.neighborIsCurrent = neighborIsCurrent
    }

    deinit { stopMonitoring() }

    func isValid() -> Bool {
        if invalidation == nil && !neighborIsCurrent() { invalidation = .anchorChanged }
        return invalidation == nil
    }

    func whilePending(cancel: @escaping (WindowPlacementInvalidation) -> Void) {
        observeChanges(pollNeighbor: true, notify: cancel)
    }

    func observeEnvironmentDuringRetry() -> (() -> Void)? {
        // The retry checks this state just before its AX write. No notification
        // callback may cancel or finish a placement that is already settling.
        observeChanges(pollNeighbor: false) { _ in }
        return { [weak self] in self?.stopMonitoring() }
    }

    private func observeChanges(pollNeighbor: Bool, notify: @escaping (WindowPlacementInvalidation) -> Void) {
        guard observers.isEmpty else { return }
        let invalidate: (WindowPlacementInvalidation) -> Void = { [weak self] reason in
            guard let self, self.invalidation != reason, self.invalidation != .environmentChanged else { return }
            self.invalidation = reason
            self.timer?.invalidate()
            self.timer = nil
            // Keep observing the desktop while a cancelled writer drains.
            notify(reason)
        }
        let events: [(NotificationCenter, WindowPlacementInvalidation, [Notification.Name])] = [
            (notifications, .anchorChanged, [.configImported, .fitBesideSnappedWindowsChanged]),
            (notifications, .environmentChanged, [NSApplication.willTerminateNotification,
                                                  NSApplication.didChangeScreenParametersNotification]),
            (NSWorkspace.shared.notificationCenter, .environmentChanged, [
                NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification,
                NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification])
        ]
        for (center, reason, names) in events {
            for name in names {
                observers.append((center, name.onPost(center: center, queue: .main) { _ in invalidate(reason) }))
            }
        }
        if let invalidation { return notify(invalidation) }
        // The anchor is another application's window; it can move while the
        // incoming window animates without generating a Rectangle action.
        guard pollNeighbor else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            if let self, self.invalidation == nil, !self.neighborIsCurrent() { invalidate(.anchorChanged) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}

private struct RejectedFitMove: WindowManagerDelegate {
    let calcResult: WindowCalculationResult
    let acceptsPlacement = false
}
