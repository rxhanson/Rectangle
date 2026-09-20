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
    func isFresh(_ key: Key, now: TimeInterval) -> Bool {
        entries[key].map { now - $0.captured < 2 } ?? false
    }
    func insert(_ image: CGImage, for key: Key, now: TimeInterval) {
        remove(key)
        let cost = image.bytesPerRow * image.height
        guard cost <= byteLimit else { return }
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

/// All entry points run on the main thread. In-flight calls retain their slots
/// until the system actually returns, even when the desired queue is replaced.
final class LayoutHelperCaptureQueue<Key: Hashable, Value> {
    var load: (Key) async -> Value?
    var completed: (Key, Value) -> Void = { _, _ in }
    private var waiting: [Key] = []
    private var running = Set<Key>()
    private var runningGeneration: [Key: Int] = [:]
    private var generation = 0
    private(set) var activeCount = 0
    init(load: @escaping (Key) async -> Value?) { self.load = load }

    func replace(with keys: [Key]) {
        var seen = Set<Key>()
        waiting = keys.filter { runningGeneration[$0] != generation && seen.insert($0).inserted }
        pump()
    }
    func stop(discardResults: Bool = false) {
        waiting.removeAll()
        if discardResults { generation += 1 }
    }
    private func pump() {
        while activeCount < 2, let index = waiting.firstIndex(where: { !running.contains($0) }) {
            let key = waiting.remove(at: index)
            running.insert(key); activeCount += 1
            let epoch = generation
            runningGeneration[key] = epoch
            Task { @MainActor [weak self] in
                guard let self else { return }
                let value = await self.load(key)
                self.running.remove(key); self.runningGeneration[key] = nil; self.activeCount -= 1
                if self.generation == epoch, let value { self.completed(key, value) }
                self.pump()
            }
        }
    }
}

struct LayoutHelperPreviewKey: Hashable {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let width: Int
    let height: Int
}

final class LayoutHelperPreviewStore {
    private let cache = LayoutHelperImageCache<LayoutHelperPreviewKey>()
    private var wanted = Set<LayoutHelperPreviewKey>()
    private var deliver: ((LayoutHelperPreviewKey, NSImage) -> Void)?
    private var expiry: DispatchWorkItem?
    private var pressure: DispatchSourceMemoryPressure?
    private var contentTask: Any?
    private var contentDate: TimeInterval = 0
    private var failures: [LayoutHelperPreviewKey: TimeInterval] = [:]
    private var suspensionReasons = Set<String>()
    private var suspended: Bool { !suspensionReasons.isEmpty }
    private lazy var queue: LayoutHelperCaptureQueue<LayoutHelperPreviewKey, CGImage> = {
        let queue = LayoutHelperCaptureQueue<LayoutHelperPreviewKey, CGImage> { [weak self] key in
            guard #available(macOS 14, *), let self, !self.suspended,
                  Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsAllowed else { return nil }
            return await self.capture(key)
        }
        queue.completed = { [weak self] key, image in
            guard let self, !self.suspended, Defaults.layoutHelper.userEnabled,
                  LayoutHelperPermission.previewsAllowed else { return }
            self.failures[key] = nil
            self.cache.insert(image, for: key, now: Date.timeIntervalSinceReferenceDate)
            if self.wanted.contains(key) {
                self.deliver?(key, NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
            }
            self.scheduleExpiry()
        }
        return queue
    }()

    init() {
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in self?.clear() }
        pressure.resume()
        self.pressure = pressure
    }
    deinit { pressure?.cancel(); expiry?.cancel() }

    static func key(id: CGWindowID, window: AccessibilityElement) -> LayoutHelperPreviewKey? {
        guard let pid = window.pid else { return nil }
        let frame = window.frame
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
        return LayoutHelperPreviewKey(id: id, pid: pid,
            launch: WindowProcessIdentity.launchTime(for: pid) ?? 0,
            width: Int(frame.width.rounded()), height: Int(frame.height.rounded()))
    }

    func cached(_ key: LayoutHelperPreviewKey) -> NSImage? {
        guard let image = cache.image(for: key, now: Date.timeIntervalSinceReferenceDate) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    func request(_ keys: [LayoutHelperPreviewKey], deliver: ((LayoutHelperPreviewKey, NSImage) -> Void)? = nil) {
        guard #available(macOS 14, *), !suspended, Defaults.layoutHelper.userEnabled,
              LayoutHelperPermission.previewsAllowed else { clear(); return }
        let now = Date.timeIntervalSinceReferenceDate
        self.wanted = Set(keys); self.deliver = deliver
        cache.prune(now: now)
        failures = failures.filter { now - $0.value < 5 }
        queue.replace(with: keys.filter { !cache.isFresh($0, now: now) && failures[$0] == nil })
    }
    func stop() {
        wanted.removeAll(); deliver = nil; queue.stop()
        scheduleExpiry()
    }
    func clear() {
        wanted.removeAll(); deliver = nil; queue.stop(discardResults: true)
        cache.removeAll(); failures.removeAll(); contentTask = nil; expiry?.cancel()
    }
    func suspend(_ reason: String) { suspensionReasons.insert(reason); clear() }
    func resume(_ reason: String) { suspensionReasons.remove(reason) }
    func removeClosedWindows(live: Set<CGWindowID>) {
        cache.prune(now: Date.timeIntervalSinceReferenceDate) { live.contains($0.id) }
    }
    private func scheduleExpiry() {
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clear() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }
    @MainActor @available(macOS 14, *) private func capture(_ key: LayoutHelperPreviewKey) async -> CGImage? {
        let now = Date.timeIntervalSinceReferenceDate
        if contentTask == nil || now - contentDate > 2 {
            contentDate = now
            contentTask = Task { try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        }
        guard let task = contentTask as? Task<SCShareableContent?, Never>,
              let content = await task.value,
              let window = content.windows.first(where: { $0.windowID == key.id && $0.owningApplication?.processID == key.pid }),
              WindowProcessIdentity.launchTime(for: key.pid) == key.launch,
              !suspended, Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsAllowed else { return nil }
        let config = Self.configuration(for: window.frame.size)
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        } catch {
            failures[key] = Date.timeIntervalSinceReferenceDate
            return nil
        }
    }

    @available(macOS 14, *) static func configuration(for size: CGSize) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = min(1, 640 / max(1, size.width), 400 / max(1, size.height))
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        config.showsCursor = false
        config.capturesAudio = false
        // ScreenCaptureKit supplies a solid backing via this option. Do not
        // assign a temporary CGColor to its non-retaining backgroundColor property:
        // copying that configuration can dereference the released color.
        config.shouldBeOpaque = true
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

}


/// App groups and their internal order remain stable during one assist sequence.
struct LayoutHelperWindowOrder {
    private var groups: [String] = []
    private var windows: [String: [CGWindowID]] = [:]
    mutating func ordered(_ candidates: [(CGWindowID, String)]) -> [CGWindowID] {
        let live = Dictionary(uniqueKeysWithValues: candidates)
        for group in groups { windows[group]?.removeAll { live[$0] != group } }
        for (id, group) in candidates {
            if !groups.contains(group) { groups.append(group) }
            if windows[group]?.contains(id) != true { windows[group, default: []].append(id) }
        }
        return groups.flatMap { windows[$0] ?? [] }
    }
}
