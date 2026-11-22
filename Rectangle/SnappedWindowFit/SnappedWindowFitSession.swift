import Cocoa

final class SnappedWindowFitSession {
    static let shared = SnappedWindowFitSession()
    private var anchor: SnappedWindowFitOpportunity?
    private var verified = false
    private var previewing = false
    private let observeWorkspace: Bool
    private let now: () -> TimeInterval
    private var verification = AccessibilityReadCancellation()
    private lazy var verificationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Rectangle.SnappedWindowFitVerification"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let verify: (SnappedWindowFitOpportunity, @escaping () -> Bool) -> Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var hasPotentialAnchor: Bool { anchor != nil }

    var current: SnappedWindowFitOpportunity? {
        if previewing, verified, let anchor {
            return SnappedWindowFitOpportunity(id: anchor.id, pid: anchor.pid, launch: anchor.launch,
                action: anchor.action, frame: anchor.frame, bounds: anchor.bounds, createdAt: now())
        }
        if let anchor, now() - anchor.createdAt >= 10 { clear() }
        return verified ? anchor : nil
    }

    init(observeWorkspace: Bool = true, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         verify: @escaping (SnappedWindowFitOpportunity, @escaping () -> Bool) -> Bool = SnappedWindowFitSession.verifyNeighbor) {
        self.observeWorkspace = observeWorkspace
        self.now = now
        self.verify = verify
    }

    private func observeInvalidation() {
        guard observeWorkspace, observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for (source, names) in [
            (center, [NSApplication.didChangeScreenParametersNotification, .configImported, .fitBesideSnappedWindowsChanged]),
            (workspace, [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.sessionDidResignActiveNotification,
                         NSWorkspace.screensDidSleepNotification])
        ] {
            for name in names {
                observers.append((source, source.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.clear() }))
            }
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier == self.anchor?.pid else { return }
                self.clear()
            }))
        }
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
        verification.cancel()
    }

    func clear() {
        guard anchor != nil else { return }
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        verification.cancel()
        verificationQueue.cancelAllOperations()
        anchor = nil
        verified = false
        previewing = false
    }

    /// Publish only a completed verification belonging to the latest snap.
    /// Clearing/taking the opportunity also cancels any in-flight verification.
    func record(_ opportunity: SnappedWindowFitOpportunity) {
        clear()
        let cancellation = AccessibilityReadCancellation()
        verification = cancellation
        anchor = opportunity
        observeInvalidation()
        let verify = self.verify
        verificationQueue.addOperation { [weak self] in
            guard cancellation.isCurrent,
                  verify(opportunity, { cancellation.isCurrent }), cancellation.isCurrent else { return }
            DispatchQueue.main.async { [weak self] in
                guard cancellation.isCurrent else { return }
                self?.verified = true
            }
        }
    }

    private static func verifyNeighbor(_ opportunity: SnappedWindowFitOpportunity,
                                       isCurrent: @escaping () -> Bool) -> Bool {
        guard let element = WindowAccessibilityLookup.resolve(pid: opportunity.pid, id: opportunity.id,
            launch: opportunity.launch, preferred: nil, isCurrent: isCurrent) else { return false }
        let reader = AccessibilityReadBatch(budget: 0.15)
        guard isCurrent(), reader.value(element, kAXRoleAttribute) as? String == kAXWindowRole,
              isCurrent(), reader.value(element, kAXSubroleAttribute) as? String != kAXSystemDialogSubrole,
              isCurrent(), reader.value(element, kAXMinimizedAttribute) as? Bool != true,
              isCurrent(), reader.value(element, "AXFullScreen") as? Bool != true,
              isCurrent(), reader.value(AXUIElementCreateApplication(opportunity.pid), kAXHiddenAttribute) as? Bool != true,
              isCurrent(), let position: CGPoint = reader.wrapped(element, kAXPositionAttribute, type: .cgPoint),
              isCurrent(), let size: CGSize = reader.wrapped(element, kAXSizeAttribute, type: .cgSize),
              isCurrent(), reader.available,
              WindowProcessIdentity.launchTime(for: opportunity.pid) == opportunity.launch else { return false }
        return WindowGeometry.matches(CGRect(origin: position, size: size), opportunity.frame)
    }

    func invalidate(windowID: CGWindowID?) {
        if let windowID, anchor?.id == windowID { clear() }
    }

    func beginPreview() { if current != nil { previewing = true } }
    func endPreview() { previewing = false }

    func take(allowPreview: Bool = false) -> SnappedWindowFitOpportunity? {
        if !allowPreview { previewing = false }
        let opportunity = current
        clear()
        return opportunity
    }

    func record(result: ResultParameters, frame: CGRect) {
        clear()
        let action = result.calcResult.resultingAction
        guard Defaults.fitBesideSnappedWindows.enabled, !result.isFixedSize,
              result.source == .dragToSnap || result.source == .keyboardShortcut || result.source == .menuItem,
              WindowSplitAxis(action: action) != nil, let id = result.windowId,
              let pid = result.windowElement.pid, let launch = WindowProcessIdentity.launchTime(for: pid),
              WindowGeometry.valid(frame),
              let calculation = WindowCalculationFactory.calculationsByAction[action] else { return }
        let ordinary = calculation.calculateRect(RectCalculationParameters(window: Window(id: id, rect: frame.screenFlipped),
            visibleFrameOfScreen: result.visibleFrameOfScreen, action: action, lastAction: nil)).rect
        guard WindowGeometry.matches(result.calcResult.initialRect, ordinary, tolerance: 1) else { return }
        let bounds = SnappedWindowFit.effectiveBounds(result.visibleFrameOfScreen)
        record(SnappedWindowFitOpportunity(id: id, pid: pid, launch: launch, action: action,
            frame: frame, bounds: bounds, createdAt: now()))
    }
}
