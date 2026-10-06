import Cocoa

/// Only the next complementary snap can use this temporary anchor;
/// an older snap in window history does not establish a current layout.
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
              WindowGeometry.matches(self.bounds, bounds, tolerance: 0.5) else { return false }
        switch (action, incoming) {
        case (.leftHalf, .rightHalf), (.rightHalf, .leftHalf), (.topHalf, .bottomHalf), (.bottomHalf, .topHalf): return true
        default: return false
        }
    }
}
