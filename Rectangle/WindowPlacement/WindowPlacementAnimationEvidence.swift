import Cocoa

/// Reuse verification only for this animation and destination. A new placement
/// discards it, and it is never saved as a window size limit.
struct WindowPlacementAnimationEvidence {
    let frame: CGRect
    let target: CGRect
    let placement: ImmediateWindowPlacement
    let completedAt: TimeInterval

    init?(frame: CGRect, original: CGRect, target: CGRect, placement: ImmediateWindowPlacement,
          completedAt: TimeInterval) {
        guard WindowGeometry.valid(frame), WindowGeometry.valid(original),
              WindowGeometry.valid(target), completedAt.isFinite,
              frame.width >= target.width - 1, frame.height >= target.height - 1,
              WindowGeometry.near(frame,
                placement.frame(for: target, actualSize: frame.size), tolerance: 1),
              WindowGeometry.near(frame, target, tolerance: 1)
                || !WindowGeometry.near(frame, original, tolerance: 1) else { return nil }
        self.frame = frame; self.target = target; self.placement = placement; self.completedAt = completedAt
    }

    func isCurrent(target: CGRect, placement: ImmediateWindowPlacement?, at time: TimeInterval) -> Bool {
        self.target == target && self.placement == placement && time >= completedAt && time - completedAt <= 0.25
    }
}
