import Cocoa
import QuartzCore

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
