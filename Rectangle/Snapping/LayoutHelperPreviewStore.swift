import Cocoa
import ScreenCaptureKit

/// Reject degenerate or fully transparent captures before adding an opaque backing.
/// Solid colors and partially transparent content remain valid.
enum LayoutHelperPreviewValidation {
    static func validSourceSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 1 && size.height > 1
    }
    static func isValid(_ image: CGImage) -> Bool {
        guard image.width > 1, image.height > 1 else { return false }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let sampledContent = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
        }
        if sampledContent { return true }
        // Sampling can miss a narrow edge or isolated pixel. Before rejecting,
        // inspect every source pixel at its original resolution, in bounded tiles.
        // Floating-point alpha preserves faint content in higher-depth captures.
        let tileSize = 256
        var components = [Float](repeating: 0, count: tileSize * tileSize * 4)
        for y in stride(from: 0, to: image.height, by: tileSize) {
            for x in stride(from: 0, to: image.width, by: tileSize) {
                let width = min(tileSize, image.width - x)
                let height = min(tileSize, image.height - y)
                guard let tile = image.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { return false }
                let hasContent = components.withUnsafeMutableBytes { bytes -> Bool in
                    guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                        bitsPerComponent: 32, bytesPerRow: tileSize * 4 * MemoryLayout<Float>.size,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.floatComponents.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                    context.interpolationQuality = .none
                    context.draw(tile, in: CGRect(x: 0, y: 0, width: width, height: height))
                    let values = bytes.bindMemory(to: Float.self)
                    return (0..<height).contains { row in
                        (0..<width).contains { column in values[(row * tileSize + column) * 4 + 3] > 0 }
                    }
                }
                if hasContent { return true }
            }
        }
        return false
    }
}

/// Only worker-side validation constructs images delivered to the main owner.
struct LayoutHelperValidatedPreview {
    let image: CGImage
    init?(_ image: CGImage) {
        guard LayoutHelperPreviewValidation.isValid(image) else { return nil }
        self.image = image
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
    private lazy var queue: LayoutHelperCaptureQueue<LayoutHelperPreviewKey, LayoutHelperValidatedPreview> = {
        let queue = LayoutHelperCaptureQueue<LayoutHelperPreviewKey, LayoutHelperValidatedPreview> { [weak self] key in
            guard #available(macOS 14, *), let self, !self.suspended,
                  Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsAllowed else { return nil }
            return await self.capture(key)
        }
        queue.completed = { [weak self] key, preview in
            guard let self, !self.suspended, Defaults.layoutHelper.userEnabled,
                  LayoutHelperPermission.previewsAllowed else { return }
            self.failures[key] = nil
            self.cache.insert(preview, for: key, now: Date.timeIntervalSinceReferenceDate)
            let image = preview.image
            if self.wanted.contains(key) {
                self.deliver?(key, NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
            }
            self.scheduleExpiry()
        }
        queue.failed = { [weak self] key in
            guard let self, self.wanted.contains(key) else { return }
            self.failures[key] = Date.timeIntervalSinceReferenceDate
            if let image = self.cached(key) { self.deliver?(key, image) }
            else { self.failureDelivery?(key) }
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
        let now = Date.timeIntervalSinceReferenceDate
        guard let image = cache.image(for: key, now: now) ?? cache.image(matching: {
            $0.id == key.id && $0.pid == key.pid && $0.launch == key.launch
        }, now: now) else { return nil }
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
    @MainActor @available(macOS 14, *) private func capture(_ key: LayoutHelperPreviewKey) async -> LayoutHelperValidatedPreview? {
        await WindowAnimationCaptureGate.shared.waitUntilIdle()
        guard !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled,
              LayoutHelperPermission.previewsAllowed,
              WindowProcessIdentity.launchTime(for: key.pid) == key.launch else { return nil }
        if #unavailable(macOS 26) {
            let image = await Task.detached(priority: .userInitiated) {
                LayoutHelperLegacyCapture.capture(id: key.id,
                    limit: CGSize(width: key.captureWidth, height: key.captureHeight)).flatMap(LayoutHelperValidatedPreview.init)
            }.value
            guard !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled,
                  LayoutHelperPermission.previewsAllowed,
                  WindowProcessIdentity.launchTime(for: key.pid) == key.launch else { return nil }
            return image
        }
        let now = Date.timeIntervalSinceReferenceDate
        if contentTask == nil || now - contentDate > 2 {
            contentDate = now
            // Minimized candidates are already scoped to the active desktop by the catalog.
            // Include them when requesting a desktop-independent screenshot.
            contentTask = Task { try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) }
        }
        guard let task = contentTask as? Task<SCShareableContent?, Never>,
              let content = await task.value,
              let window = content.windows.first(where: { $0.windowID == key.id && $0.owningApplication?.processID == key.pid }),
              WindowProcessIdentity.launchTime(for: key.pid) == key.launch,
              !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled, LayoutHelperPermission.previewsAllowed else { return nil }
        await WindowAnimationCaptureGate.shared.waitUntilIdle()
        guard !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled,
              LayoutHelperPermission.previewsAllowed else { return nil }
        guard LayoutHelperPreviewValidation.validSourceSize(window.frame.size) else { return nil }
        do {
            guard #available(macOS 26, *) else { return nil }
            let config = Self.screenshotConfiguration(for: window.frame.size,
                limit: CGSize(width: key.captureWidth, height: key.captureHeight), sourceScale: key.captureScale)
            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
            guard !Task.isCancelled, let image = output.sdrImage else { return nil }
            // Drawing for validation can decode the entire capture. Keep it in
            // the occupied capture slot, away from input and card animations.
            let preview = await Task.detached(priority: .userInitiated) {
                LayoutHelperValidatedPreview(image)
            }.value
            return Task.isCancelled ? nil : preview
        } catch {
            guard !Task.isCancelled else { return nil }
            failures[key] = Date.timeIntervalSinceReferenceDate
            return nil
        }
    }

    static func pixelSize(for size: CGSize, limit: CGSize, sourceScale: CGFloat) -> CGSize {
        let scale = min(sourceScale, limit.width / max(1, size.width), limit.height / max(1, size.height))
        return CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
    }

    @available(macOS 26, *) static func screenshotConfiguration(for size: CGSize,
        limit: CGSize = CGSize(width: 420, height: 260), sourceScale: CGFloat = 1) -> SCScreenshotConfiguration {
        let pixels = pixelSize(for: size, limit: limit, sourceScale: sourceScale)
        let config = SCScreenshotConfiguration()
        config.width = Int(pixels.width)
        config.height = Int(pixels.height)
        config.showsCursor = false
        config.ignoreShadows = true
        config.ignoreClipping = true
        return config
    }

}


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
