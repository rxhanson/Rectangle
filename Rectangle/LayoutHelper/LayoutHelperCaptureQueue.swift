import Cocoa
import ScreenCaptureKit

final class LayoutHelperCaptureQueue<Key: Hashable, Value> {
    var load: (Key) async -> Value?
    var completed: (Key, Value) -> Void = { _, _ in }
    var failed: (Key) -> Void = { _ in }
    private var waiting: [Key] = []
    private var running = Set<Key>()
    private var runningGeneration: [Key: Int] = [:]
    private var generation = 0
    private var tasks: [Key: Task<Void, Never>] = [:]
    private(set) var activeCount = 0
    init(load: @escaping (Key) async -> Value?) { self.load = load }

    func replace(with keys: [Key]) {
        var seen = Set<Key>()
        // Scrolling changes priority even when the candidate set stays the same.
        waiting = keys.filter { runningGeneration[$0] != generation && seen.insert($0).inserted }
        pump()
    }
    func stop(discardResults: Bool = false) {
        waiting.removeAll()
        generation += 1
        for task in tasks.values { task.cancel() }
    }
    private func pump() {
        while activeCount < 2, let index = waiting.firstIndex(where: { !running.contains($0) }) {
            let key = waiting.remove(at: index)
            running.insert(key); activeCount += 1
            let epoch = generation
            runningGeneration[key] = epoch
            tasks[key] = Task { @MainActor [weak self] in
                guard let self else { return }
                let value = Task.isCancelled ? nil : await self.load(key)
                self.tasks[key] = nil
                self.running.remove(key); self.runningGeneration[key] = nil; self.activeCount -= 1
                if !Task.isCancelled, self.generation == epoch {
                    if let value { self.completed(key, value) } else { self.failed(key) }
                }
                self.pump()
            }
        }
    }
}

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

/// Resolve optional WindowServer capture symbols without linking private frameworks.
/// The caller owns permission, identity and concurrency checks; capture runs off-main.
enum LayoutHelperLegacyCapture {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Capture = @convention(c) (UInt32, UnsafeMutablePointer<CGWindowID>, UInt32, UInt32) -> Unmanaged<CFArray>?
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    private static func lookup<T>(_ names: [String], as type: T.Type) -> T? {
        guard let library else { return nil }
        for name in names {
            if let symbol = dlsym(library, name) { return unsafeBitCast(symbol, to: type) }
        }
        return nil
    }
    static func capture(id: CGWindowID, limit: CGSize) -> CGImage? {
        guard CGPreflightScreenCaptureAccess(),
              let connection = lookup(["SLSMainConnectionID", "CGSMainConnectionID"], as: Connection.self),
              let capture = lookup(["CGSHWCaptureWindowList"], as: Capture.self) else { return nil }
        var windowID = id
        // Best resolution, full size, and no desktop clipping.
        let options: UInt32 = (1 << 8) | (1 << 19) | (1 << 11)
        guard let images = capture(connection(), &windowID, 1, options)?.takeRetainedValue() as? [CGImage],
              let image = images.first, LayoutHelperPreviewValidation.isValid(image) else { return nil }
        let pixels = LayoutHelperPreviewStore.pixelSize(for: CGSize(width: image.width, height: image.height),
            limit: limit, sourceScale: 1)
        guard let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: pixels))
        guard let preview = context.makeImage(), LayoutHelperPreviewValidation.isValid(preview) else { return nil }
        return preview
    }
}
