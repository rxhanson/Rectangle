import Foundation

/// Align the size actually accepted by the app at the requested destination.
struct ImmediateWindowPlacement: Equatable {
    let screenFrame: CGRect
    let sharedEdges: Edge?
    let constrainToScreen: Bool
    let gap: CGFloat

    func frame(for requested: CGRect, actualSize: CGSize) -> CGRect {
        var frame = CGRect(origin: requested.origin, size: actualSize)
        if let sharedEdges {
            frame = ClampedWindowAligner.aligned(window: frame, inZone: requested, sharedEdges: sharedEdges)
        }
        return constrainToScreen ? WindowFrameBounds.constrained(frame, to: screenFrame, gap: gap) : frame
    }
}
