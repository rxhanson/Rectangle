import Cocoa
import QuartzCore

struct WindowAnimationWritePolicy {
    private var lastRequest: CGRect?
    private var confirmations = 0
    private var verifiedAt: TimeInterval = -.infinity
    var now: TimeInterval = 0
    var geometryChanged = false

    var needsVerification: Bool {
        let interval = confirmations < 2 ? 1.0 / 30 : (geometryChanged ? 1.0 / 20 : 1.0 / 12)
        return lastRequest != nil && now - verifiedAt >= interval
    }

    mutating func observe(ax: CGRect, server: CGRect?, at time: TimeInterval) {
        now = time
        guard let requested = lastRequest, let server,
              WindowAnimationGeometry.near(ax, requested, tolerance: 1),
              WindowAnimationGeometry.near(ax, server, tolerance: 1) else { reset(); return }
        if time > verifiedAt { confirmations = min(2, confirmations + 1) }
        verifiedAt = time
        geometryChanged = false
    }

    func mayPredict(_ frame: CGRect, previous: CGRect?, placement: WindowAnimationPlacement,
                    progress: CGFloat) -> Bool {
        guard confirmations >= 2, !needsVerification, progress < 0.9, let previous else { return false }
        if placement.constrainToScreen {
            let bounds = placement.screenFrame.insetBy(dx: placement.gap, dy: placement.gap)
            guard bounds.contains(previous), bounds.contains(frame),
                  placement.positionBeforeGrowing(from: previous, to: frame) == nil else { return false }
            // A stationary edge at the screen boundary is safe; a moving edge
            // approaching it still needs a readback to detect system clamping.
            let oldEdges = [previous.minX, previous.maxX, previous.minY, previous.maxY]
            let newEdges = [frame.minX, frame.maxX, frame.minY, frame.maxY]
            let boundaries = [bounds.minX, bounds.maxX, bounds.minY, bounds.maxY]
            for i in oldEdges.indices where abs(newEdges[i] - boundaries[i]) < 2 {
                guard abs(newEdges[i] - oldEdges[i]) < 0.5 else { return false }
            }
        }
        return true
    }

    mutating func requested(_ frame: CGRect) { lastRequest = frame }
    mutating func reset() { confirmations = 0; verifiedAt = now; lastRequest = nil }
}
