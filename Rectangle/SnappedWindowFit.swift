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
                        target: CGRect, screenFrame: CGRect, minimum: CGSize?) -> Resolution {
        guard Defaults.fitBesideSnappedWindows.enabled, let id = window.id,
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
        let infos = WindowUtil.getWindowList(forceRefresh: true)
        let resolution = resolve(enabled: true, action: action, movingWindowID: id,
            target: target.screenFlipped, bounds: bounds, gap: gap, minimum: minimum,
            windows: infos, recordedFrames: AppDelegate.windowHistory.lastRectangleActions.mapValues(\.rect),
            ignoredPID: ProcessInfo.processInfo.processIdentifier)
        guard case let .fit(plan) = resolution else { return resolution }
        guard let neighbor = AccessibilityElement.getWindowElement(plan.neighborID),
              neighbor.pid == plan.neighborPID, neighbor.isWindow == true,
              neighbor.isMinimized != true, neighbor.isHidden != true, neighbor.isFullScreen != true,
              neighbor.isSheet != true, neighbor.isSystemDialog != true,
              LayoutHelperLayout.matches(neighbor.frame, plan.neighborFrame) else { return .unchanged }
        return .fit(plan)
    }

    /// Pure scene calculation shared by previews and actual placements.
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
