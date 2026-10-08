import Cocoa
import ScreenCaptureKit

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
                  Defaults.layoutHelper.userEnabled, WindowCapturePermission.previewsAllowed else { return nil }
            return await self.capture(key)
        }
        queue.completed = { [weak self] key, preview in
            guard let self, !self.suspended, Defaults.layoutHelper.userEnabled,
                  WindowCapturePermission.previewsAllowed else { return }
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
              WindowCapturePermission.previewsAllowed else { clear(); return }
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
              WindowCapturePermission.previewsAllowed,
              WindowProcessIdentity.launchTime(for: key.pid) == key.launch else { return nil }
        if #unavailable(macOS 26) {
            let image = await Task.detached(priority: .userInitiated) {
                LayoutHelperLegacyCapture.capture(id: key.id,
                    limit: CGSize(width: key.captureWidth, height: key.captureHeight)).flatMap(LayoutHelperValidatedPreview.init)
            }.value
            guard !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled,
                  WindowCapturePermission.previewsAllowed,
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
              !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled, WindowCapturePermission.previewsAllowed else { return nil }
        await WindowAnimationCaptureGate.shared.waitUntilIdle()
        guard !Task.isCancelled, !suspended, Defaults.layoutHelper.userEnabled,
              WindowCapturePermission.previewsAllowed else { return nil }
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
