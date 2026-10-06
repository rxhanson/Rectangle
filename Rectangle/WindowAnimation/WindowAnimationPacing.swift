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
