import Cocoa

final class SnappedWindowFitSession {
    static let shared = SnappedWindowFitSession()
    private var anchor: SnappedWindowFitOpportunity?
    private var verified = false
    private var verification = AccessibilityReadCancellation()
    private let verificationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Rectangle.SnappedWindowFitVerification"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let verify: (SnappedWindowFitOpportunity, @escaping () -> Bool) -> Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var current: SnappedWindowFitOpportunity? {
        if let anchor, ProcessInfo.processInfo.systemUptime - anchor.createdAt >= 10 { clear() }
        return verified ? anchor : nil
    }

    init(observeWorkspace: Bool = true,
         verify: @escaping (SnappedWindowFitOpportunity, @escaping () -> Bool) -> Bool = SnappedWindowFitSession.verifyNeighbor) {
        self.verify = verify
        guard observeWorkspace else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for (source, names) in [
            (center, [NSApplication.didChangeScreenParametersNotification, .configImported]),
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

    func clear() {
        verification.cancel()
        verificationQueue.cancelAllOperations()
        anchor = nil
        verified = false
    }

    /// Publish only a completed verification belonging to the latest snap.
    /// Clearing/taking the opportunity also cancels any in-flight verification.
    func record(_ opportunity: SnappedWindowFitOpportunity) {
        clear()
        let cancellation = AccessibilityReadCancellation()
        verification = cancellation
        anchor = opportunity
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
        let reader = AccessibilityReadBatch(budget: 0.15, isCurrent: isCurrent)
        guard reader.value(element, kAXRoleAttribute) as? String == kAXWindowRole,
              reader.value(element, kAXSubroleAttribute) as? String != kAXSystemDialogSubrole,
              reader.value(element, kAXMinimizedAttribute) as? Bool != true,
              reader.value(element, "AXFullScreen") as? Bool != true,
              reader.value(AXUIElementCreateApplication(opportunity.pid), kAXHiddenAttribute) as? Bool != true,
              let position: CGPoint = reader.wrapped(element, kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = reader.wrapped(element, kAXSizeAttribute, type: .cgSize),
              reader.available,
              WindowProcessIdentity.launchTime(for: opportunity.pid) == opportunity.launch else { return false }
        return WindowGeometry.matches(CGRect(origin: position, size: size), opportunity.frame)
    }

    func invalidate(windowID: CGWindowID?) {
        if let windowID, anchor?.id == windowID { clear() }
    }

    func take() -> SnappedWindowFitOpportunity? {
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
        let bounds = GapCalculation.applyGaps(result.visibleFrameOfScreen, gapSize: max(0, Defaults.gapSize.value),
            skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
        record(SnappedWindowFitOpportunity(id: id, pid: pid, launch: launch, action: action,
            frame: frame, bounds: bounds, createdAt: ProcessInfo.processInfo.systemUptime))
    }
}
