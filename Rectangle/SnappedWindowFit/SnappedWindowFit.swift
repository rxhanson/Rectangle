import Cocoa

/// The incoming window alone is placed. Both frames are in AX (top-left) coordinates.
struct SnappedWindowFit: Equatable {
    let target: CGRect
    let neighbor: SnappedWindowFitOpportunity

    enum Resolution: Equatable {
        case unchanged
        case fit(SnappedWindowFit)
        case noRoom
    }

    static func resolve(action: WindowAction, window: Window, initialTarget: CGRect, target: CGRect,
                        screenFrame: CGRect, opportunity: SnappedWindowFitOpportunity?,
                        windowList: () -> [WindowInfo] = { WindowUtil.getWindowList(forceRefresh: true) },
                        processLaunchTime: (pid_t) -> TimeInterval? = WindowProcessIdentity.launchTime(for:)) -> Resolution {
        guard Defaults.fitBesideSnappedWindows.enabled, let id = window.id, let opportunity,
              let calculation = WindowCalculationFactory.calculationsByAction[action] else { return .unchanged }
        let gap = max(0, CGFloat(Defaults.gapSize.value))
        let bounds = effectiveBounds(screenFrame)
        guard opportunity.accepts(action: action, movingWindowID: id, bounds: bounds) else { return .unchanged }

        // An explicitly cycled fraction should keep the target the user chose.
        let ordinary = calculation.calculateRect(RectCalculationParameters(window: window,
            visibleFrameOfScreen: screenFrame, action: action, lastAction: nil)).rect
        guard WindowGeometry.matches(initialTarget, ordinary, tolerance: 1) else { return .unchanged }
        guard processLaunchTime(opportunity.pid) == opportunity.launch else {
            SnappedWindowFitSession.shared.invalidate(windowID: opportunity.id)
            return .unchanged
        }
        DiagnosticTrace.event("fit-window-list", fields: ["windowID": id, "anchorID": opportunity.id])
        let windows = windowList()
        guard let index = windows.firstIndex(where: { $0.id == opportunity.id }) else {
            SnappedWindowFitSession.shared.invalidate(windowID: opportunity.id)
            return .unchanged
        }
        let windowInfo = windows[index]
        guard isExposed(windowInfo, inFront: windows[..<index], ignoring: id,
                        ignoredPID: ProcessInfo.processInfo.processIdentifier),
              windowInfo.pid == opportunity.pid, WindowGeometry.matches(windowInfo.frame, opportunity.frame) else {
            SnappedWindowFitSession.shared.invalidate(windowID: opportunity.id)
            return .unchanged
        }
        return resolve(action: action, movingWindowID: id, target: target.screenFlipped, bounds: bounds,
                       gap: gap, anchor: opportunity)
    }

    static func previewRect(for target: WindowCalculationResult, window: Window, screenFrame: CGRect,
                            adjustedTarget: () -> CGRect?) -> CGRect? {
        let ordinaryPreview = target.rect
        let action = target.resultingAction
        guard Defaults.fitBesideSnappedWindows.enabled,
              WindowSplitAxis(action: action) != nil,
              let opportunity = SnappedWindowFitSession.shared.current,
              let id = window.id,
              opportunity.accepts(action: action, movingWindowID: id,
                                  bounds: SnappedWindowFit.effectiveBounds(screenFrame)),
              let fittedInput = adjustedTarget()
        else { return ordinaryPreview }

        // Fit sees the same adjusted target as its move provider. If the offset excludes Fit,
        // the ordinary preview still follows the upstream gap-only behavior.
        switch SnappedWindowFit.resolve(action: action, window: window,
                                               initialTarget: target.initialRect, target: fittedInput,
                                               screenFrame: screenFrame, opportunity: opportunity) {
        case .fit(let plan):
            return plan.target.screenFlipped
        case .unchanged:
            return ordinaryPreview
        case .noRoom:
            return nil
        }
    }

    static func effectiveBounds(_ screenFrame: CGRect) -> CGRect {
        GapCalculation.applyGaps(screenFrame, gapSize: max(0, Defaults.gapSize.value),
                                 skipTopGap: Defaults.skipGapTopEdge.enabled).screenFlipped
    }

    static func resolve(action: WindowAction, movingWindowID: CGWindowID, target: CGRect,
                        bounds: CGRect, gap: CGFloat, anchor: SnappedWindowFitOpportunity) -> Resolution {
        guard let axis = WindowSplitAxis(action: action), gap.isFinite, gap >= 0 else { return .unchanged }
        // Transposing a vertical split lets all four directions share the same edge and tolerance rules.
        let bounds = axis.rect(bounds)
        let target = axis.rect(target)
        let anchorRect = axis.rect(anchor.frame)
        let incomingTrails = action == .rightHalf || action == .bottomHalf
        guard WindowGeometry.valid(bounds), WindowGeometry.valid(target), WindowGeometry.valid(anchorRect),
              fullHeight(target, in: bounds),
              abs(incomingTrails ? target.maxX - bounds.maxX : target.minX - bounds.minX) <= 3,
              anchor.id != movingWindowID, fullHeight(anchorRect, in: bounds),
              anchorRect.width < bounds.width - 1, anchorRect.minX >= bounds.minX - 3,
              anchorRect.maxX <= bounds.maxX + 3,
              abs(incomingTrails ? anchorRect.minX - bounds.minX : anchorRect.maxX - bounds.maxX) <= 3
        else { return .unchanged }

        let start = incomingTrails ? anchorRect.maxX + gap : bounds.minX
        let end = incomingTrails ? bounds.maxX : anchorRect.minX - gap
        // CGRect.width standardizes negative extents. Compare the signed edges before constructing the rectangle.
        guard end > start else { return .noRoom }
        return .fit(Self(target: axis.rect(CGRect(x: start, y: bounds.minY, width: end - start, height: bounds.height)),
                         neighbor: anchor))
    }

    static func isExposed(_ anchor: WindowInfo, inFront windows: ArraySlice<WindowInfo>,
                          ignoring movingWindowID: CGWindowID, ignoredPID: pid_t) -> Bool {
        guard anchor.id != movingWindowID, anchor.pid != ignoredPID, anchor.level == 0,
              anchor.isOnScreen, anchor.alpha > 0 else { return false }
        // Several partially overlapping windows can together conceal the anchor. Ignore its rounded perimeter.
        let interior = anchor.frame.insetBy(dx: 2, dy: 2)
        guard !interior.isNull, interior.size.width > 0, interior.size.height > 0 else { return false }
        var exposed = [interior]
        for window in windows where window.id != movingWindowID && window.pid != ignoredPID
            && window.level == 0 && window.isOnScreen && window.alpha > 0 {
            let other = window.frame
            exposed = exposed.flatMap { piece -> [CGRect] in
                let cut = piece.intersection(other)
                guard !cut.isNull, !cut.isEmpty else { return [piece] }
                return [CGRect(x: piece.minX, y: piece.minY, width: piece.width, height: cut.minY - piece.minY),
                        CGRect(x: piece.minX, y: cut.maxY, width: piece.width, height: piece.maxY - cut.maxY),
                        CGRect(x: piece.minX, y: cut.minY, width: cut.minX - piece.minX, height: cut.height),
                        CGRect(x: cut.maxX, y: cut.minY, width: piece.maxX - cut.maxX, height: cut.height)]
                    .filter { $0.width > 0 && $0.height > 0 }
            }
            if exposed.isEmpty { return false }
        }
        return !exposed.isEmpty
    }

    private static func fullHeight(_ frame: CGRect, in bounds: CGRect) -> Bool {
        abs(frame.minY - bounds.minY) <= 3 && abs(frame.maxY - bounds.maxY) <= 3
    }

    /// WindowCalculationResult retains the unpadded tile as well as the padded placement target.
    func unpaddedTarget(for result: WindowCalculationResult) -> CGRect {
        let initial = result.initialRect
        var gapOnly = result
        gapOnly.rect = initial
        GapTargetAdjuster().adjust(&gapOnly, action: result.resultingAction, windowId: nil)
        let padded = gapOnly.rect
        let frame = target.screenFlipped
        return CGRect(x: frame.minX - (padded.minX - initial.minX),
                      y: frame.minY - (padded.minY - initial.minY),
                      width: frame.width + initial.width - padded.width,
                      height: frame.height + initial.height - padded.height)
    }
}

/// Keeps AX measurements for one continuous hover. The anchor and WindowServer stack
/// are still sampled on every Fit refresh. WindowManager computes its own target on release.
final class SnappedWindowFitPreview {
    private let area: SnapArea
    private let windowID: CGWindowID?
    private let displayFrame: CGRect
    private let visibleFrame: CGRect
    let screenFrame: CGRect

    private struct AdjustmentInputs: Equatable {
        let raw: CGRect
        let padded: CGRect
        let offset: Float?
        let maxCascade: Int
    }
    private var adjustment: (inputs: AdjustmentInputs, rect: CGRect?)?

    init(area: SnapArea, windowID: CGWindowID?, screenFrame: CGRect) {
        self.area = area
        self.windowID = windowID
        self.screenFrame = screenFrame
        displayFrame = area.screen.frame
        visibleFrame = area.screen.visibleFrame
    }

    func matches(area: SnapArea, windowID: CGWindowID?) -> Bool {
        self.area == area && self.windowID == windowID
            && displayFrame == area.screen.frame && visibleFrame == area.screen.visibleFrame
    }

    func adjustedRect(for target: WindowCalculationResult, measure: () -> CGRect?) -> CGRect? {
        let inputs = AdjustmentInputs(raw: target.initialRect, padded: target.rect,
                                      offset: Defaults.cyclingOverlapOffset.userEnabled ? Defaults.cyclingOverlapOffsetSize.value : nil,
                                      maxCascade: Defaults.cyclingOverlapMaxCascade.value)
        if let adjustment, adjustment.inputs == inputs { return adjustment.rect }
        let rect = measure()
        adjustment = (inputs, rect)
        return rect
    }
}

struct SnappedWindowFitOpportunity: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let action: WindowAction
    let frame: CGRect
    let bounds: CGRect

    func accepts(action incoming: WindowAction, movingWindowID: CGWindowID, bounds: CGRect) -> Bool {
        guard movingWindowID != id,
              WindowGeometry.matches(self.bounds, bounds, tolerance: 0.5) else { return false }
        switch (action, incoming) {
        case (.leftHalf, .rightHalf), (.rightHalf, .leftHalf), (.topHalf, .bottomHalf), (.bottomHalf, .topHalf): return true
        default: return false
        }
    }
}
