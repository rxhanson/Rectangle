import Cocoa
import QuartzCore

/// Tracks an outstanding resize without interpreting delayed delivery as a limit.
struct WindowAnimationResizeResponse {
    private struct Request {
        let size: CGSize
        let previous: CGSize
        let sentAt: TimeInterval
        var acknowledged = false
        var progressed = false
    }
    private var pending: Request?
    private var accepted: (size: CGSize, time: TimeInterval)?
    private var latency: TimeInterval = 1.0 / 60
    var frameInterval: TimeInterval = 1.0 / 60
    private var period: TimeInterval { min(0.05, max(1.0 / 120, frameInterval)) }
    var pendingSize: CGSize? { pending?.size }
    var freshnessInterval: TimeInterval { period * 1.25 }
    var readbackInterval: TimeInterval { min(0.1, max(period * 2, latency)) }
    var responseInterval: TimeInterval { min(0.15, max(period * 2, latency * 2)) }

    func planningSize(observed: CGSize, at time: TimeInterval) -> CGSize {
        guard let accepted, time - accepted.time <= 0.15 else { return observed }
        return accepted.size
    }

    func hasRecentAcceptance(at time: TimeInterval) -> Bool {
        accepted.map { time - $0.time <= freshnessInterval } ?? false
    }

    mutating func requested(_ size: CGSize, previous: CGSize, at time: TimeInterval) {
        if let pending, !pending.acknowledged, !pending.progressed {
            // Back off when a retry still has no response, rather than stacking requests.
            latency = max(latency, min(0.15, time - pending.sentAt))
        }
        pending = Request(size: size, previous: previous, sentAt: time)
    }
    @discardableResult
    mutating func observe(_ size: CGSize, at time: TimeInterval) -> Bool {
        if let accepted, matches(size, accepted.size) { self.accepted = nil }
        guard var pending, time >= pending.sentAt else { return false }
        // A delayed intermediate size is progress, not delivery of the latest request.
        guard matches(size, pending.size) else {
            let progressed = !pending.progressed && !matches(size, pending.previous)
            pending.progressed = pending.progressed || progressed
            self.pending = pending
            return progressed
        }
        if !pending.acknowledged { latency = latency * 0.75 + min(0.15, time - pending.sentAt) * 0.25 }
        self.pending = nil
        accepted = nil
        return true
    }

    mutating func acknowledge(_ size: CGSize, at time: TimeInterval) -> Bool {
        guard var pending, !pending.acknowledged, time >= pending.sentAt,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return false }
        let delivered = matches(size, pending.size)
        guard delivered || !matches(size, pending.previous) else { return false }
        if let accepted, matches(size, accepted.size), !delivered { return false }
        if delivered { latency = latency * 0.75 + min(0.15, time - pending.sentAt) * 0.25 }
        pending.acknowledged = delivered
        pending.progressed = true
        self.pending = pending
        accepted = (size, time)
        return true
    }

    func mayRequest(at time: TimeInterval) -> Bool {
        pending.map { $0.acknowledged || $0.progressed || time - $0.sentAt >= responseInterval } ?? true
    }

    private func matches(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
    }
}
