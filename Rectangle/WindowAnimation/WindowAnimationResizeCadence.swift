import Cocoa
import QuartzCore

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
