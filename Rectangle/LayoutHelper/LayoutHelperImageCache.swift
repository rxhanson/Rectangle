import Cocoa
import ScreenCaptureKit

/// Explicit decoded-byte accounting; the budget covers retained cache images,
/// not ScreenCaptureKit's temporary buffers or views currently displaying them.
final class LayoutHelperImageCache<Key: Hashable> {
    private struct Entry {
        let image: CGImage
        let captured: TimeInterval
        let cost: Int
        var access: UInt64
    }
    private var entries: [Key: Entry] = [:]
    private var access: UInt64 = 0
    private(set) var byteCount = 0
    let byteLimit: Int
    init(byteLimit: Int = 32 * 1024 * 1024) { self.byteLimit = byteLimit }

    func image(for key: Key, now: TimeInterval, maximumAge: TimeInterval = 120) -> CGImage? {
        guard var entry = entries[key] else { return nil }
        guard now - entry.captured <= maximumAge else { remove(key); return nil }
        access += 1; entry.access = access; entries[key] = entry
        return entry.image
    }
    func image(matching predicate: (Key) -> Bool, now: TimeInterval) -> CGImage? {
        guard let key = entries.filter({ predicate($0.key) && now - $0.value.captured <= 120 })
            .max(by: { $0.value.captured < $1.value.captured })?.key else { return nil }
        return image(for: key, now: now)
    }
    func isFresh(_ key: Key, now: TimeInterval) -> Bool {
        entries[key].map { now - $0.captured < 2 } ?? false
    }
    func insert(_ image: CGImage, for key: Key, now: TimeInterval) {
        guard let preview = LayoutHelperValidatedPreview(image) else { return }
        insert(preview, for: key, now: now)
    }
    func insert(_ preview: LayoutHelperValidatedPreview, for key: Key, now: TimeInterval) {
        let image = preview.image
        let cost = image.bytesPerRow * image.height
        guard cost <= byteLimit else { return }
        remove(key)
        while byteCount + cost > byteLimit, let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key { remove(oldest) }
        access += 1
        entries[key] = Entry(image: image, captured: now, cost: cost, access: access)
        byteCount += cost
    }
    func remove(_ key: Key) { if let old = entries.removeValue(forKey: key) { byteCount -= old.cost } }
    func prune(now: TimeInterval, keeping: (Key) -> Bool = { _ in true }) {
        for key in Array(entries.keys) where !keeping(key) || now - entries[key]!.captured > 120 { remove(key) }
    }
    func removeAll() { entries.removeAll(); byteCount = 0 }
}

/// Main-thread queue with at most two in-flight captures. Cancelled captures
/// retain their slots until they return; generations discard stale results.
