import Cocoa
import ScreenCaptureKit

/// Original geometry survives a failed or cancelled restoration until placement
/// succeeds. Process identity keeps retries from inheriting another app's frame.
struct LayoutHelperRestorationFrames {
    private struct Identity: Hashable {
        let id: CGWindowID
        let pid: pid_t
        let launch: TimeInterval
    }
    private var frames: [Identity: CGRect] = [:]
    mutating func original(id: CGWindowID, pid: pid_t, launch: TimeInterval, frame: CGRect, remember: Bool) -> CGRect {
        let key = Identity(id: id, pid: pid, launch: launch)
        if let original = frames[key] { return original }
        if remember { frames[key] = frame }
        return frame
    }
    mutating func remove(id: CGWindowID, pid: pid_t, launch: TimeInterval) {
        frames.removeValue(forKey: Identity(id: id, pid: pid, launch: launch))
    }
    mutating func prune(live: Set<CGWindowID>) {
        frames = frames.filter { live.contains($0.key.id) && WindowProcessIdentity.launchTime(for: $0.key.pid) == $0.key.launch }
    }
}
