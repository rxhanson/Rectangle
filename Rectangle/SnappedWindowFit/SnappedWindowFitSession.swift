import Cocoa

final class SnappedWindowFitSession {
    static let shared = SnappedWindowFitSession()
    private var anchor: SnappedWindowFitOpportunity?
    private let observeWorkspace: Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var hasPotentialAnchor: Bool { anchor != nil }
    var current: SnappedWindowFitOpportunity? { anchor }

    init(observeWorkspace: Bool = true) {
        self.observeWorkspace = observeWorkspace
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
    }

    func clear() {
        guard anchor != nil else { return }
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        anchor = nil
    }

    /// The next window command consumes this reference. Its identity and frame
    /// are checked against the current window list when Fit calculates a target.
    func record(_ opportunity: SnappedWindowFitOpportunity) {
        clear()
        anchor = opportunity
        observeInvalidation()
    }

    func invalidate(_ opportunity: SnappedWindowFitOpportunity) {
        if anchor == opportunity { clear() }
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
        let bounds = SnappedWindowFit.effectiveBounds(result.visibleFrameOfScreen)
        record(SnappedWindowFitOpportunity(id: id, pid: pid, launch: launch, action: action,
            frame: frame, bounds: bounds))
    }
}
