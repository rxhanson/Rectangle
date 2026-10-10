import Cocoa

/// Reported constraints and historical hints deliberately have different uses.
/// A verified, settled resize can promote an observation to a hint;
/// direct resize requests still verify the live app rather than trusting hints.
final class WindowSizeConstraintStore<Key: Hashable> {
    private(set) var entries: [Key: WindowSizeEvidence] = [:]
    var lifetime: TimeInterval?
    private let capacity: Int
    private var accepted: [Key: CGSize] = [:]
    private var reports: [Key: CGSize] = [:]

    init(lifetime: TimeInterval = 600, capacity: Int = 128) {
        self.lifetime = lifetime; self.capacity = capacity
    }

    func minimum(for key: Key, reported: CGSize?, current: CGSize, now: TimeInterval) -> CGSize? {
        let report = Self.normalized(reported) ?? .zero
        if let previous = reports[key], previous != report {
            accepted.removeValue(forKey: key)
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
        if var entry = entries[key] {
            if size.width + 2 < entry.learned.width { entry.learned.width = 0 }
            if size.height + 2 < entry.learned.height { entry.learned.height = 0 }
            entries[key] = Self.normalized(entry.learned) == nil ? nil : entry
        }
        if accepted.count > capacity { accepted.removeValue(forKey: accepted.keys.first!) }
    }

    func observe(for key: Key, reported: CGSize?, before: CGSize, requested: CGSize,
                 first: CGSize, settled: CGSize, now: TimeInterval, verifiedClamp: Bool = false) {
        guard [before, requested, first, settled].allSatisfy(Self.valid),
              abs(first.width - settled.width) <= 1, abs(first.height - settled.height) <= 1 else { return }
        if abs(requested.width - settled.width) <= 1 && abs(requested.height - settled.height) <= 1 {
            recordSuccess(for: key, size: settled)
            return
        }
        guard verifiedClamp else { return }
        guard let learned = WindowSizeResizeObservation.learnedMinimum(before: before,
            requested: requested, settled: settled) else { return }
        // A verified smaller result disproves an older hint even when the new
        // request was itself clamped. Retain unaffected axes only.
        recordSuccess(for: key, size: settled)
        let reported = Self.normalized(reported)
        var entry = entries[key].flatMap { $0.reported == reported ? $0 : nil }
            ?? WindowSizeEvidence(reported: reported, learned: .zero, learnedAt: now)
        if learned.width > 0 { entry.learned.width = learned.width }
        if learned.height > 0 { entry.learned.height = learned.height }
        entry.confirmations = 1
        entry.learnedAt = now
        entry.requested = requested; entry.achieved = settled
        entries[key] = entry
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.learnedAt < $1.value.learnedAt })?.key {
            remove(oldest)
        }
    }

    func clear() { entries.removeAll(); accepted.removeAll(); reports.removeAll() }
    func remove(_ key: Key) { entries.removeValue(forKey: key); accepted.removeValue(forKey: key); reports.removeValue(forKey: key) }
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
struct WindowSizeEvidence: Codable, Equatable {
    var reported: CGSize?
    var learned: CGSize
    var learnedAt: TimeInterval
    var confirmations: Int = 1
    var requested: CGSize = .zero
    var achieved: CGSize = .zero
    var source: String = "verified-placement"

    var isValid: Bool {
        learned.width.isFinite && learned.height.isFinite && learned.width >= 0 && learned.height >= 0
            && (learned.width > 0 || learned.height > 0)
            && learnedAt.isFinite && confirmations >= 1
            && requested.width.isFinite && requested.height.isFinite
            && achieved.width.isFinite && achieved.height.isFinite
            && requested.width > 0 && requested.height > 0 && achieved.width > 0 && achieved.height > 0
            && (reported.map { $0.width.isFinite && $0.height.isFinite && $0.width >= 0 && $0.height >= 0 } ?? true)
    }
}
/// Capture on the store's owner thread, then validate with bounded AX metadata
/// on a worker. No mutable store or AccessibilityElement is read by this value.
struct WindowSizeHintSnapshot {
    let evidence: WindowSizeEvidence
    let lifetime: TimeInterval?
    let cancellation: AccessibilityReadCancellation?

    var isCurrent: Bool { cancellation?.isCurrent != false }

    func minimum(reported: CGSize?, current: CGSize, now: TimeInterval) -> CGSize? {
        guard isCurrent, lifetime.map({ now - evidence.learnedAt > $0 }) != true,
              evidence.reported == Self.normalized(reported) else { return nil }
        var learned = evidence.learned
        if current.width.isFinite, current.height.isFinite, current.width > 0, current.height > 0 {
            if current.width + 2 < learned.width { learned.width = 0 }
            if current.height + 2 < learned.height { learned.height = 0 }
        }
        return Self.normalized(learned)
    }

    private static func normalized(_ size: CGSize?) -> CGSize? {
        guard let size else { return nil }
        let width = size.width.isFinite && size.width > 0 ? size.width : 0
        let height = size.height.isFinite && size.height > 0 ? size.height : 0
        return width > 0 || height > 0 ? CGSize(width: width, height: height) : nil
    }
}
