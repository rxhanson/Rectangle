import Cocoa
import QuartzCore

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
