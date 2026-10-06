import Cocoa

/// Reported constraints and historical hints deliberately have different uses.
/// Only independently verified operations can promote an observation to a hint;
/// direct resize requests still verify the live app rather than trusting hints.
final class WindowSizeConstraintStore<Key: Hashable> {
    private(set) var entries: [Key: WindowSizeEvidence] = [:]
    var lifetime: TimeInterval?
    private let capacity: Int
    private struct Observation {
        let operation: UUID
        let learned: CGSize
        let reported: CGSize?
        let time: TimeInterval
    }
    private var observations: [Key: Observation] = [:]
    private var accepted: [Key: CGSize] = [:]
    private var reports: [Key: CGSize] = [:]

    init(lifetime: TimeInterval = 600, capacity: Int = 128) {
        self.lifetime = lifetime; self.capacity = capacity
    }

    func minimum(for key: Key, reported: CGSize?, current: CGSize, now: TimeInterval) -> CGSize? {
        let report = Self.normalized(reported) ?? .zero
        if let previous = reports[key], previous != report {
            accepted.removeValue(forKey: key)
            observations.removeValue(forKey: key)
        }
        reports[key] = report
        if reports.count > capacity, let oldest = reports.keys.first(where: { $0 != key }) { reports.removeValue(forKey: oldest) }
        _ = hint(for: key, reported: reported, current: current, now: now)
        var result = Self.normalized(reported) ?? .zero
        if let success = accepted[key] {
            if success.width + 2 < result.width { result.width = 0 }
            if success.height + 2 < result.height { result.height = 0 }
        }
        return Self.normalized(result)
    }

    func hintSnapshot(for key: Key, cancellation: AccessibilityReadCancellation? = nil) -> WindowSizeHintSnapshot? {
        entries[key].map { WindowSizeHintSnapshot(evidence: $0, lifetime: lifetime, cancellation: cancellation) }
    }

    func hint(for key: Key, reported: CGSize?, current: CGSize, now: TimeInterval) -> CGSize? {
        guard var entry = entries[key] else { return nil }
        if lifetime.map({ now - entry.learnedAt > $0 }) == true || entry.reported != Self.normalized(reported) {
            entries.removeValue(forKey: key)
            observations.removeValue(forKey: key)
            return nil
        }
        if Self.valid(current) {
            if current.width + 2 < entry.learned.width { entry.learned.width = 0 }
            if current.height + 2 < entry.learned.height { entry.learned.height = 0 }
        }
        entries[key] = Self.normalized(entry.learned) == nil ? nil : entry
        return Self.normalized(entry.learned)
    }

    func recordSuccess(for key: Key, size: CGSize) {
        guard Self.valid(size) else { return }
        let old = accepted[key] ?? size
        accepted[key] = CGSize(width: min(old.width, size.width), height: min(old.height, size.height))
        // Growing between independent resize attempts does not disprove a clamp.
        if let observation = observations[key],
           size.width + 2 < observation.learned.width || size.height + 2 < observation.learned.height {
            observations.removeValue(forKey: key)
        }
        if var entry = entries[key] {
            if size.width + 2 < entry.learned.width { entry.learned.width = 0 }
            if size.height + 2 < entry.learned.height { entry.learned.height = 0 }
            entries[key] = Self.normalized(entry.learned) == nil ? nil : entry
        }
        if accepted.count > capacity { accepted.removeValue(forKey: accepted.keys.first!) }
    }

    func observe(for key: Key, reported: CGSize?, before: CGSize, requested: CGSize,
                 first: CGSize, settled: CGSize, now: TimeInterval, verifiedClamp: Bool = false,
                 operation: UUID = UUID()) {
        guard [before, requested, first, settled].allSatisfy(Self.valid),
              abs(first.width - settled.width) <= 1, abs(first.height - settled.height) <= 1 else { return }
        if abs(requested.width - settled.width) <= 1 && abs(requested.height - settled.height) <= 1 {
            recordSuccess(for: key, size: settled)
            return
        }
        guard verifiedClamp else { return }
        guard let learned = WindowSizeResizeObservation.learnedMinimum(before: before,
            requested: requested, settled: settled) else { return }
        let reported = Self.normalized(reported)
        let previous = observations[key]
        if previous?.operation == operation { return }
        observations[key] = Observation(operation: operation, learned: learned, reported: reported, time: now)
        if observations.count > capacity, let oldest = observations.min(by: { $0.value.time < $1.value.time })?.key {
            observations.removeValue(forKey: oldest)
        }
        guard let previous, now - previous.time <= 600, previous.reported == reported,
              abs(previous.learned.width - learned.width) <= 1,
              abs(previous.learned.height - learned.height) <= 1 else { return }
        var entry = entries[key] ?? WindowSizeEvidence(reported: reported, learned: .zero, learnedAt: now)
        entry.learned.width = max(entry.learned.width, learned.width)
        entry.learned.height = max(entry.learned.height, learned.height)
        entry.learnedAt = now
        entry.requested = requested; entry.achieved = settled
        entries[key] = entry
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.learnedAt < $1.value.learnedAt })?.key {
            remove(oldest)
        }
        if observations.count > capacity, let oldest = observations.min(by: { $0.value.time < $1.value.time })?.key {
            observations.removeValue(forKey: oldest)
        }
    }

    func clear() { entries.removeAll(); observations.removeAll(); accepted.removeAll(); reports.removeAll() }
    func remove(_ key: Key) { entries.removeValue(forKey: key); observations.removeValue(forKey: key); accepted.removeValue(forKey: key); reports.removeValue(forKey: key) }
    func restore(_ evidence: WindowSizeEvidence, for key: Key, now: TimeInterval) {
        guard evidence.isValid else { return }
        entries[key] = evidence
    }

    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
    private static func normalized(_ size: CGSize?) -> CGSize? {
        guard let size else { return nil }
        let width = size.width.isFinite && size.width > 0 ? size.width : 0
        let height = size.height.isFinite && size.height > 0 ? size.height : 0
        return width > 0 || height > 0 ? CGSize(width: width, height: height) : nil
    }
}
