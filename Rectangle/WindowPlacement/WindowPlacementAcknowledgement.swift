import Cocoa

/// Accept the app's actual size after the mover finishes, including size limits
/// and aspect ratios, then verify snap alignment. Rollback requires the exact
/// original frame.
struct WindowPlacementAcknowledgement {
    enum Decision { case waiting, position(CGPoint), size(CGSize), complete(CGRect), failed }
    let target: CGRect
    let bounds: CGRect?
    private let placement: WindowAnimationPlacement?
    private var waitingUntil: TimeInterval
    private var positionWrites = 0
    private var sizeWrites = 0
    private var stableAt: TimeInterval?
    private var stableFrame: CGRect?

    init(target: CGRect, startedAt: TimeInterval, pendingWrite: Bool, bounds: CGRect? = nil,
         placement: WindowAnimationPlacement? = nil) {
        self.target = target
        self.bounds = bounds
        self.placement = placement
        waitingUntil = startedAt + (pendingWrite ? 0.65 : 0)
    }

    mutating func observe(_ frame: CGRect?, at now: TimeInterval) -> Decision {
        guard let frame, WindowAnimationGeometry.valid(frame) else {
            stableAt = nil; stableFrame = nil
            return .waiting
        }
        let expected = placement?.frame(for: target, actualSize: frame.size, origin: frame, progress: 1) ?? target
        if WindowAnimationGeometry.near(frame, expected, tolerance: 1) {
            if let stableFrame, WindowAnimationGeometry.near(frame, stableFrame, tolerance: 1),
               let stableAt, now - stableAt >= 0.02 { return .complete(frame) }
            if stableFrame.map({ WindowAnimationGeometry.near(frame, $0, tolerance: 1) }) != true {
                stableFrame = frame; stableAt = now
            }
            return .waiting
        }
        stableAt = nil; stableFrame = nil
        guard now >= waitingUntil else { return .waiting }
        let needsPosition = abs(frame.minX - expected.minX) > 1 || abs(frame.minY - expected.minY) > 1
        let needsSize = abs(frame.width - expected.width) > 1 || abs(frame.height - expected.height) > 1
        // Snap verification never resizes. Only an exact rollback can request
        // size, using the same write order as the ordinary immediate mover.
        if needsSize, ImmediateFrameOrder.sizeFirst(from: frame, to: expected,
            bounds: bounds ?? frame.union(expected), acrossScreens: false, preferSizeFirst: true) || !needsPosition {
            guard sizeWrites < 2 else { return .failed }
            sizeWrites += 1; waitingUntil = now + 0.65
            return .size(expected.size)
        }
        if needsPosition {
            guard positionWrites < 2 else { return .failed }
            positionWrites += 1; waitingUntil = now + 0.65
            return .position(expected.origin)
        }
        return .failed
    }
}
