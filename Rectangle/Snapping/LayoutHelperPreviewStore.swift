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
/// Main-thread animation ownership. Waiting captures retain demand without polling
/// or a fixed delay, and recheck ownership after every asynchronous wake-up.
final class LayoutHelperCaptureGate {
    static let shared = LayoutHelperCaptureGate()
    private var owners = Set<UUID>()
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    var isPaused: Bool { !owners.isEmpty }

    func begin(_ owner: UUID) { owners.insert(owner) }
    func end(_ owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    @MainActor func waitUntilIdle() async {
        while isPaused && !Task.isCancelled {
            let id = UUID()
            await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled || !isPaused { continuation.resume() }
                    else { waiters[id] = continuation }
                }
            }, onCancel: { [weak self] in
                Task { @MainActor in self?.waiters.removeValue(forKey: id)?.resume() }
            })
        }
    }
}

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
        let desired = Set(keys)
        waiting.removeAll { !desired.contains($0) }
        seen.formUnion(waiting)
        waiting.append(contentsOf: keys.filter { runningGeneration[$0] != generation && seen.insert($0).inserted })
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

/// One capture budget per display, independent of candidate count and card layout.
final class LayoutHelperPreviewResolution {
    static let shared = LayoutHelperPreviewResolution()
    private var sizes: [CGDirectDisplayID: CGSize] = [:]
    private struct Input: Equatable {
        let size: CGSize
        let scale: CGFloat
    }
    private var inputs: [CGDirectDisplayID: Input] = [:]
    private var observer: NSObjectProtocol?

    static func limit(for available: CGSize, backingScale: CGFloat = 1) -> CGSize {
        let region = CGSize(width: available.width, height: available.height / 2)
        let inset = LayoutHelperPreviewLayout.inset(for: region)
        let scale = backingScale >= 2 ? CGFloat(2) : 1
        return CGSize(width: max(1, min(420, floor(region.width - inset * 2 - 40))) * scale, height: 260 * scale)
    }

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func refresh() {
        var live = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let key = id.uint32Value
            live.insert(key)
            let input = Input(size: screen.visibleFrame.size, scale: screen.backingScaleFactor)
            if inputs[key] != input {
                inputs[key] = input
                sizes[key] = Self.limit(for: input.size, backingScale: input.scale)
            }
        }
        sizes = sizes.filter { live.contains($0.key) }
        inputs = inputs.filter { live.contains($0.key) }
    }
    func limit(on screen: NSScreen) -> CGSize {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let size = sizes[id.uint32Value] else { return Self.limit(for: screen.visibleFrame.size, backingScale: screen.backingScaleFactor) }
        return size
    }
}

struct LayoutHelperPreviewKey: Hashable {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let width: Int
    let height: Int
    var captureWidth: Int = 420
    var captureHeight: Int = 260
    var captureScale: CGFloat = 1

    func on(_ screen: NSScreen) -> Self {
        let size = LayoutHelperPreviewResolution.shared.limit(on: screen)
        var key = self
        key.captureWidth = Int(size.width); key.captureHeight = Int(size.height)
        key.captureScale = screen.backingScaleFactor >= 2 ? 2 : 1
        return key
    }
}

final class LayoutHelperPreviewStore {
    private let cache = LayoutHelperImageCache<LayoutHelperPreviewKey>()
    private var wanted = Set<LayoutHelperPreviewKey>()
    private var deliver: ((LayoutHelperPreviewKey, NSImage) -> Void)?
    private var failureDelivery: ((LayoutHelperPreviewKey) -> Void)?
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
        queue.failed = { [weak self] key in
            guard let self, self.wanted.contains(key) else { return }
            self.failureDelivery?(key)
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
    func request(_ keys: [LayoutHelperPreviewKey], onFailure: ((LayoutHelperPreviewKey) -> Void)? = nil, deliver: ((LayoutHelperPreviewKey, NSImage) -> Void)? = nil) {
        guard #available(macOS 14, *), !suspended, Defaults.layoutHelper.userEnabled,
              LayoutHelperPermission.previewsAllowed else { clear(); return }
        let now = Date.timeIntervalSinceReferenceDate
        self.wanted = Set(keys); self.deliver = deliver; self.failureDelivery = onFailure
        cache.prune(now: now)
        failures = failures.filter { now - $0.value < 5 }
        for key in keys where failures[key] != nil && !cache.isFresh(key, now: now) { onFailure?(key) }
        queue.replace(with: keys.filter { !cache.isFresh($0, now: now) && failures[$0] == nil })
    }
    func stop() {
        wanted.removeAll(); deliver = nil; failureDelivery = nil; queue.stop()
        scheduleExpiry()
    }
    func clear() {
        wanted.removeAll(); deliver = nil; failureDelivery = nil; queue.stop(discardResults: true)
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
        await LayoutHelperCaptureGate.shared.waitUntilIdle()
        guard !Task.isCancelled else { return nil }
        let now = Date.timeIntervalSinceReferenceDate
        if contentTask == nil || now - contentDate > 2 {
            contentDate = now
            contentTask = Task { try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        }
        guard let task = contentTask as? Task<SCShareableContent?, Never>,
              let content = await task.value,
              let window = content.windows.first(where: { $0.windowID == key.id && $0.owningApplication?.processID == key.pid }),
              WindowProcessIdentity.launchTime(for: key.pid) == key.launch,
              !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsAllowed else { return nil }
        await LayoutHelperCaptureGate.shared.waitUntilIdle()
        guard !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled,
              LayoutHelperPermission.previewsAllowed else { return nil }
        let config = Self.configuration(for: window.frame.size, limit: CGSize(width: key.captureWidth, height: key.captureHeight), sourceScale: key.captureScale)
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
            return Task.isCancelled ? nil : image
        } catch {
            guard !Task.isCancelled else { return nil }
            failures[key] = Date.timeIntervalSinceReferenceDate
            return nil
        }
    }

    @available(macOS 14, *) static func configuration(for size: CGSize, limit: CGSize = CGSize(width: 420, height: 260), sourceScale: CGFloat = 1) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = min(sourceScale, limit.width / max(1, size.width), limit.height / max(1, size.height))
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
