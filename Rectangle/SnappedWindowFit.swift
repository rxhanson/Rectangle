import Cocoa

/// A fit changes only the incoming window. Coordinates here are top-left AX
/// points, including the configured outer padding and inter-window gap.
struct SnappedWindowFit: Equatable {
    let target: CGRect
    let neighborID: CGWindowID
    let neighborPID: pid_t
    let neighborFrame: CGRect

    enum Resolution: Equatable {
        case unchanged
        case fit(SnappedWindowFit)
        case noRoom
    }

    static func resolve(action: WindowAction, window: Window, initialTarget: CGRect,
                        target: CGRect, screenFrame: CGRect, minimum: CGSize?,
                        opportunity: SnappedWindowFitOpportunity? = SnappedWindowFitSession.shared.current) -> Resolution {
        guard Defaults.fitBesideSnappedWindows.enabled, let id = window.id, let opportunity,
              WindowSplitAxis(action: action) != nil,
              let calculation = WindowCalculationFactory.calculationsByAction[action] else { return .unchanged }
        // Preserve explicit fractions and repeated-command size cycling. Only
        // the ordinary half-screen target adopts an existing neighbor's edge.
        let ordinary = calculation.calculateRect(RectCalculationParameters(window: window,
            visibleFrameOfScreen: screenFrame, action: action, lastAction: nil)).rect
        guard LayoutHelperLayout.matches(initialTarget, ordinary, tolerance: 1) else { return .unchanged }
        let gap = max(0, CGFloat(Defaults.gapSize.value))
        let bounds = GapCalculation.applyGaps(screenFrame, gapSize: Float(gap),
            skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
        guard opportunity.accepts(action: action, movingWindowID: id, bounds: bounds,
                                  at: ProcessInfo.processInfo.systemUptime),
              WindowProcessIdentity.launchTime(for: opportunity.pid) == opportunity.launch else { return .unchanged }
        let infos = WindowUtil.getWindowList(forceRefresh: true)
        guard infos.contains(where: { $0.id == opportunity.id && $0.pid == opportunity.pid
            && LayoutHelperLayout.matches($0.frame, opportunity.frame) }) else {
            SnappedWindowFitSession.shared.invalidate(windowID: opportunity.id)
            return .unchanged
        }
        let resolution = resolve(enabled: true, action: action, movingWindowID: id,
            target: target.screenFlipped, bounds: bounds, gap: gap, minimum: minimum,
            windows: infos, recordedFrames: [opportunity.id: opportunity.frame],
            ignoredPID: ProcessInfo.processInfo.processIdentifier)
        guard case let .fit(plan) = resolution else { return resolution }
        guard let neighbor = AccessibilityElement.getWindowElement(plan.neighborID),
              neighbor.pid == plan.neighborPID, neighbor.isWindow == true,
              neighbor.isMinimized != true, neighbor.isHidden != true, neighbor.isFullScreen != true,
              neighbor.isSheet != true, neighbor.isSystemDialog != true,
              LayoutHelperLayout.matches(neighbor.frame, plan.neighborFrame) else {
            SnappedWindowFitSession.shared.invalidate(windowID: opportunity.id)
            return .unchanged
        }
        return .fit(plan)
    }

    static func resolve(enabled: Bool, action: WindowAction, movingWindowID: CGWindowID,
                        target: CGRect, bounds: CGRect, gap: CGFloat, minimum: CGSize?,
                        windows: [WindowInfo], recordedFrames: [CGWindowID: CGRect],
                        ignoredPID: pid_t) -> Resolution {
        if let axis = WindowSplitAxis(action: action), axis == .vertical {
            let result = resolve(enabled: enabled, action: action == .topHalf ? .leftHalf : .rightHalf,
                movingWindowID: movingWindowID, target: axis.rect(target), bounds: axis.rect(bounds),
                gap: gap, minimum: minimum.map { axis.size($0) },
                windows: windows.map { WindowInfo(id: $0.id, level: $0.level, frame: axis.rect($0.frame), pid: $0.pid, processName: $0.processName) },
                recordedFrames: recordedFrames.mapValues { axis.rect($0) }, ignoredPID: ignoredPID)
            if case let .fit(plan) = result {
                return .fit(Self(target: axis.rect(plan.target), neighborID: plan.neighborID,
                    neighborPID: plan.neighborPID, neighborFrame: axis.rect(plan.neighborFrame)))
            }
            return result
        }
        guard enabled, action == .leftHalf || action == .rightHalf,
              bounds.width > 0, bounds.height > 0, gap.isFinite, gap >= 0,
              fullHeight(target, in: bounds),
              abs((action == .rightHalf ? target.maxX - bounds.maxX : target.minX - bounds.minX)) <= 3
        else { return .unchanged }
        let candidates = windows.enumerated().filter { index, info in
            guard info.id != movingWindowID, info.pid != ignoredPID, info.level == 0,
                  let recorded = recordedFrames[info.id],
                  LayoutHelperLayout.matches(info.frame, recorded),
                  fullHeight(info.frame, in: bounds),
                  info.frame.width > 0, info.frame.width < bounds.width - 1,
                  info.frame.minX >= bounds.minX - 3, info.frame.maxX <= bounds.maxX + 3,
                  abs((action == .rightHalf ? info.frame.minX - bounds.minX : info.frame.maxX - bounds.maxX)) <= 3
            else { return false }
            // The incoming window can cover its prospective neighbor while it
            // is dragged. Other normal windows covering that neighbor disqualify it.
            return !windows.prefix(index).contains { covering in
                covering.id != movingWindowID && covering.pid != ignoredPID && covering.level == 0
                    && covering.frame.intersects(info.frame.insetBy(dx: 2, dy: 2))
            }
        }
        guard candidates.count == 1, let neighbor = candidates.first?.element else { return .unchanged }
        let left = action == .rightHalf ? neighbor.frame.maxX + gap : bounds.minX
        let right = action == .leftHalf ? neighbor.frame.minX - gap : bounds.maxX
        let fitted = CGRect(x: left, y: bounds.minY, width: right - left, height: bounds.height)
        // The remaining region is a request, not a minimum-size admission test.
        // A constrained incoming window may overlap its unchanged neighbor.
        guard fitted.width > 0 else { return .noRoom }
        return .fit(Self(target: fitted, neighborID: neighbor.id, neighborPID: neighbor.pid, neighborFrame: neighbor.frame))
    }

    private static func fullHeight(_ frame: CGRect, in bounds: CGRect) -> Bool {
        abs(frame.minY - bounds.minY) <= 3 && abs(frame.maxY - bounds.maxY) <= 3
    }

    func neighborIsUnchanged() -> Bool {
        WindowUtil.getWindowList(forceRefresh: true).contains {
            $0.id == neighborID && $0.pid == neighborPID && LayoutHelperLayout.matches($0.frame, neighborFrame)
        }
    }

    /// Prefetch expects an unpadded anchor; reverse the exact padding applied to
    /// the ordinary target, retaining the newly adopted split.
    func unpaddedTarget(initial: CGRect, padded: CGRect) -> CGRect {
        let frame = target.screenFlipped
        return CGRect(x: frame.minX - (padded.minX - initial.minX),
                      y: frame.minY - (padded.minY - initial.minY),
                      width: frame.width + initial.width - padded.width,
                      height: frame.height + initial.height - padded.height)
    }
}

/// Historical placements do not imply an ongoing layout. Only the next
/// complementary snap may use this short-lived, explicitly created anchor.
struct SnappedWindowFitOpportunity {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let action: WindowAction
    let frame: CGRect
    let bounds: CGRect
    let createdAt: TimeInterval

    func accepts(action incoming: WindowAction, movingWindowID: CGWindowID, bounds: CGRect,
                 at time: TimeInterval) -> Bool {
        guard movingWindowID != id, time >= createdAt, time - createdAt < 10,
              LayoutHelperLayout.matches(self.bounds, bounds, tolerance: 0.5) else { return false }
        switch (action, incoming) {
        case (.leftHalf, .rightHalf), (.rightHalf, .leftHalf), (.topHalf, .bottomHalf), (.bottomHalf, .topHalf): return true
        default: return false
        }
    }
}

final class SnappedWindowFitSession {
    static let shared = SnappedWindowFitSession()
    private var anchor: SnappedWindowFitOpportunity?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var current: SnappedWindowFitOpportunity? {
        if let anchor, ProcessInfo.processInfo.systemUptime - anchor.createdAt >= 10 { clear() }
        return anchor
    }

    private init() {
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

    func clear() { anchor = nil }

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
              WindowAnimationGeometry.valid(frame),
              let calculation = WindowCalculationFactory.calculationsByAction[action] else { return }
        let ordinary = calculation.calculateRect(RectCalculationParameters(window: Window(id: id, rect: frame.screenFlipped),
            visibleFrameOfScreen: result.visibleFrameOfScreen, action: action, lastAction: nil)).rect
        guard LayoutHelperLayout.matches(result.calcResult.initialRect, ordinary, tolerance: 1) else { return }
        let bounds = GapCalculation.applyGaps(result.visibleFrameOfScreen, gapSize: max(0, Defaults.gapSize.value),
            skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
        anchor = SnappedWindowFitOpportunity(id: id, pid: pid, launch: launch, action: action,
            frame: frame, bounds: bounds, createdAt: ProcessInfo.processInfo.systemUptime)
    }
}
