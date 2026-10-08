import Cocoa
import QuartzCore

struct WindowAnimationPacing {
    let maximumRate: Int
    private var divisor = 1
    private var slow = 0
    private var fast = 0
    private var costs: [TimeInterval] = []
    init(maximumRate: Int, initialRate: Double? = nil) {
        self.maximumRate = max(1, maximumRate > 0 ? maximumRate : 60)
        let preferred = min(Double(self.maximumRate), initialRate ?? Double(self.maximumRate))
        while rate > 120 || (rate > preferred && rate > 30) { divisor *= 2 }
    }
    var rate: Double { Double(maximumRate) / Double(divisor) }
    // Keep lower rates aligned to whole display refresh periods, including odd rates.
    var interval: TimeInterval { Double(divisor) / Double(maximumRate) }
    static func sampleTime(now: TimeInterval, deadline: TimeInterval?, displayInterval: TimeInterval) -> TimeInterval {
        guard let deadline, deadline.isFinite else { return now }
        return max(now, min(deadline, now + displayInterval))
    }
    mutating func observe(cost: TimeInterval) {
        costs.append(cost)
        if costs.count > 8 { costs.removeFirst() }
        let tail = costs.sorted()[max(0, Int(Double(costs.count - 1) * 0.9))]
        if cost > interval {
            slow += 1; fast = 0
            if slow >= 3, rate > 30 { divisor *= 2; slow = 0; costs.removeAll() }
        } else {
            slow = 0
            if divisor > 1, rate * 2 <= 120, tail < 0.65 * interval / 2 { fast += 1 } else { fast = 0 }
            if fast >= 12 { divisor /= 2; fast = 0; costs.removeAll() }
        }
    }
}

struct WindowAnimationFrameBudget {
    var deadline: TimeInterval?
    private(set) var sizeReadCost: TimeInterval = 0.0005
    private var lastSizeRead: TimeInterval?
    private(set) var positionWriteCost: TimeInterval = 0.001

    mutating func observeSizeRead(_ cost: TimeInterval, at time: TimeInterval, frameInterval: TimeInterval) {
        sizeReadCost = max(cost, estimatedSizeReadCost(at: time, frameInterval: frameInterval) * 0.75)
        lastSizeRead = time
    }
    func estimatedSizeReadCost(at time: TimeInterval, frameInterval: TimeInterval) -> TimeInterval {
        guard let lastSizeRead else { return sizeReadCost }
        // One slow read must not suppress feedback for the rest of the animation.
        let periods = max(0, time - lastSizeRead) / (frameInterval * 2)
        return max(0.0002, sizeReadCost * pow(0.5, periods))
    }
    mutating func observePositionWrite(_ cost: TimeInterval) {
        positionWriteCost = positionWriteCost * 0.75 + cost * 0.25
    }
    func allowsSizeRead(at time: TimeInterval, frameInterval: TimeInterval,
                        resizeCost: TimeInterval, reservingMotion: Bool) -> Bool {
        guard let deadline else { return true }
        let readCost = estimatedSizeReadCost(at: time, frameInterval: frameInterval)
        // A cheap acknowledgment can unblock resizing even after a late display callback.
        if readCost <= frameInterval * 0.25, time <= deadline + frameInterval { return true }
        let reserve = reservingMotion ? max(0.002, positionWriteCost + min(resizeCost, frameInterval / 2)) : 0.001
        return deadline - time >= readCost + reserve
    }
}

struct WindowAnimationResizeCadence {
    let frameInterval: TimeInterval
    private(set) var frames: Int = 1
    private var slow = 0
    private var fast = 0

    init(frameInterval: TimeInterval, cost: TimeInterval = 0) {
        self.frameInterval = frameInterval
        frames = requiredFrames(cost)
    }
    var interval: TimeInterval { frames > 1 ? Double(frames) * frameInterval : 0 }
    private func requiredFrames(_ cost: TimeInterval) -> Int {
        min(max(1, Int(ceil(0.05 / frameInterval))), max(1, Int(ceil(cost / (frameInterval * 0.8)))))
    }
    mutating func observe(cost: TimeInterval) {
        let required = requiredFrames(cost)
        if required > frames {
            slow += 1; fast = 0
            if slow >= 2 { frames = required; slow = 0 }
        } else {
            slow = 0
            if required < frames { fast += 1 } else { fast = 0 }
            if fast >= 6 { frames -= 1; fast = 0 }
        }
    }
}

struct WindowAnimationResponseKey: Hashable {
    let pid: pid_t
    let window: CGWindowID
    let launch: TimeInterval
}

struct WindowAnimationResponseHistory {
    struct Entry {
        let pacing: WindowAnimationPacing
        let resizeCost: TimeInterval
        let updatedAt: TimeInterval
    }
    private var entries: [WindowAnimationResponseKey: Entry] = [:]
    func entry(for key: WindowAnimationResponseKey, at time: TimeInterval) -> Entry? {
        guard let entry = entries[key], time - entry.updatedAt < 30 else { return nil }
        return entry
    }
    mutating func record(_ key: WindowAnimationResponseKey, pacing: WindowAnimationPacing, resizeCost: TimeInterval, at time: TimeInterval) {
        entries = entries.filter { time - $0.value.updatedAt < 30 }
        if entries.count >= 32, entries[key] == nil,
           let oldest = entries.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key { entries.removeValue(forKey: oldest) }
        entries[key] = Entry(pacing: pacing, resizeCost: resizeCost, updatedAt: time)
    }
}

@available(macOS 14.0, *)
final class WindowAnimationDisplayLinkTarget: NSObject {
    private let onFrame: (TimeInterval) -> Void
    init(onFrame: @escaping (TimeInterval) -> Void) { self.onFrame = onFrame }
    @objc func tick(_ link: CADisplayLink) { onFrame(link.targetTimestamp) }
}
