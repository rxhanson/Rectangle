import Cocoa

/// Require both apps to acknowledge the final geometry continuously before
/// revealing them; a bounded deadline prevents a stalled app from trapping UI.
struct WindowDividerRevealGate {
    enum State: Equatable { case waiting, ready, timedOut }
    let left: CGRect
    let right: CGRect
    let startedAt: TimeInterval
    private var matchedSince: TimeInterval?

    init(left: CGRect, right: CGRect, startedAt: TimeInterval, matchedSince: TimeInterval? = nil) {
        self.left = left; self.right = right; self.startedAt = startedAt
        self.matchedSince = matchedSince.flatMap { $0.isFinite && $0 <= startedAt ? $0 : nil }
    }

    mutating func observe(left actualLeft: CGRect, right actualRight: CGRect, at time: TimeInterval) -> State {
        if WindowGeometry.matches(actualLeft, left, tolerance: 1),
           WindowGeometry.matches(actualRight, right, tolerance: 1) {
            if let matchedSince, time - matchedSince >= 0.05 { return .ready }
            if matchedSince == nil { matchedSince = time }
        } else { matchedSince = nil }
        return time - startedAt >= 0.6 ? .timedOut : .waiting
    }
}
