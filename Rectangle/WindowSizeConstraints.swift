import Cocoa

/// Per-window evidence. A successful smaller size disproves a learned limit;
/// a refused write alone is not evidence of a minimum.
final class WindowSizeConstraintStore<Key: Hashable> {
    private(set) var entries: [Key: WindowSizeEvidence] = [:]
    var lifetime: TimeInterval?
    private let capacity: Int

    init(lifetime: TimeInterval = 600, capacity: Int = 128) {
        self.lifetime = lifetime; self.capacity = capacity
    }

    func minimum(for key: Key, reported: CGSize?, current: CGSize, now: TimeInterval) -> CGSize? {
        let reported = Self.normalized(reported)
        guard var entry = entries[key] else { return reported }
        if lifetime.map({ now - entry.learnedAt > $0 }) == true || entry.reported != reported {
            entries.removeValue(forKey: key)
            return reported
        }
        if Self.valid(current) {
            if current.width + 2 < entry.learned.width { entry.learned.width = 0 }
            if current.height + 2 < entry.learned.height { entry.learned.height = 0 }
        }
        entries[key] = Self.normalized(entry.learned) == nil ? nil : entry
        return Self.normalized(CGSize(width: max(reported?.width ?? 0, entry.learned.width),
                                      height: max(reported?.height ?? 0, entry.learned.height)))
    }

    func observe(for key: Key, reported: CGSize?, before: CGSize, requested: CGSize,
                 first: CGSize, settled: CGSize, now: TimeInterval, verifiedClamp: Bool = false) {
        guard [before, requested, first, settled].allSatisfy(Self.valid),
              abs(first.width - settled.width) <= 1, abs(first.height - settled.height) <= 1 else { return }
        _ = minimum(for: key, reported: reported, current: settled, now: now)
        var entry = entries[key] ?? WindowSizeEvidence(reported: Self.normalized(reported), learned: .zero, learnedAt: now)
        func clamp(_ old: CGFloat, _ target: CGFloat, _ actual: CGFloat) -> CGFloat {
            // Require actual progress toward a smaller request. Unchanged or
            // growing windows can indicate refusal, latency, or another action.
            target + 2 < actual && (actual + 2 < old || (verifiedClamp && actual <= old + 1)) ? actual : 0
        }
        let width = clamp(before.width, requested.width, settled.width)
        let height = clamp(before.height, requested.height, settled.height)
        guard width > 0 || height > 0 else { return }
        entry.learned.width = max(entry.learned.width, width)
        entry.learned.height = max(entry.learned.height, height)
        entry.learnedAt = now
        entries[key] = entry
        if lifetime != nil, entries.count > capacity, let oldest = entries.min(by: { $0.value.learnedAt < $1.value.learnedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    func clear() { entries.removeAll() }

    func remove(_ key: Key) { entries.removeValue(forKey: key) }

    func restore(_ evidence: WindowSizeEvidence, for key: Key, now: TimeInterval) {
        guard Self.normalized(evidence.learned) != nil else { return }
        entries[key] = WindowSizeEvidence(reported: Self.normalized(evidence.reported),
            learned: Self.normalized(evidence.learned)!, learnedAt: now)
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

/// Shared by ordinary snapping, drag previews, Layout Helper and cooperative moves.
final class WindowSizeConstraints {
    static let shared = WindowSizeConstraints()
    static let changed = Notification.Name("windowSizeConstraintsChanged")
    private static let archiveKey = "learnedWindowSizeLimits.v1"
    private struct Key: Hashable {
        let element: AccessibilityElement
        let pid: pid_t
        let launch: TimeInterval
    }
    private let store = WindowSizeConstraintStore<Key>()
    private struct PendingResize {
        let token: UUID
        let before: CGRect
        let requested: CGRect
    }
    private struct Descriptor {
        var record: WindowSizeLimitRecord
        var checkedAt: TimeInterval
        var attemptedRestore = false
    }
    private var descriptors: [Key: Descriptor] = [:]
    private var pending: [Key: PendingResize] = [:]
    private var observations: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var archive = WindowSizeLimitArchive()
    private var remembers = Defaults.rememberWindowSizeLimits.enabled
    private let session = WindowSizeConstraints.sessionIdentifier()
    private(set) var observationGeneration = UUID()

    var rememberLimits: Bool { remembers }

    var records: [WindowSizeLimitRecord] {
        synchronizePreference()
        // Expiry is checked here too, so the management list never presents an
        // expired temporary record as an active minimum.
        let now = ProcessInfo.processInfo.systemUptime
        for (key, evidence) in store.entries {
            if store.lifetime.map({ now - evidence.learnedAt > $0 }) == true {
                store.remove(key)
            }
        }
        var result = remembers ? archive.records : []
        for (key, descriptor) in descriptors {
            guard let evidence = store.entries[key] else { continue }
            var record = descriptor.record; record.evidence = evidence
            result.removeAll { $0.id == record.id }
            result.append(record)
        }
        return result.sorted { ($0.appName.localizedLowercase, $0.identity.windowID) < ($1.appName.localizedLowercase, $1.identity.windowID) }
    }

    private init() {
        store.lifetime = remembers ? nil : 600
        if remembers, let data = UserDefaults.standard.data(forKey: Self.archiveKey) {
            archive = WindowSizeLimitArchive.decode(data) ?? WindowSizeLimitArchive()
        }
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.screenParametersChanged() })
        observations.append(NotificationCenter.default.addObserver(forName: .configImported,
            object: nil, queue: .main) { [weak self] _ in self?.synchronizePreference() })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancelPendingObservations() })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.removeRuntimeRecords(pid: app.processIdentifier)
            })
        // This applies even when drag-to-snap is disabled.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.cancelPendingObservations()
        }
    }

    private static func sessionIdentifier() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }

    func setRememberLimits(_ enabled: Bool) {
        Defaults.rememberWindowSizeLimits.enabled = enabled
        synchronizePreference()
    }

    private func synchronizePreference() {
        let enabled = Defaults.rememberWindowSizeLimits.enabled
        guard enabled != remembers else { return }
        if enabled {
            let now = ProcessInfo.processInfo.systemUptime
            for (key, evidence) in store.entries where now - evidence.learnedAt > 600 { store.remove(key) }
        }
        remembers = enabled
        cancelPendingObservations()
        store.lifetime = enabled ? nil : 600
        archive.clear()
        if enabled {
            for (key, evidence) in store.entries {
                guard var record = descriptors[key]?.record else { continue }
                record.evidence = evidence; archive.upsert(record)
            }
        }
        saveAndNotify()
    }

    func resetAll() {
        cancelPendingObservations()
        store.clear(); archive.clear(); descriptors.removeAll()
        saveAndNotify()
    }

    private func screenParametersChanged() {
        cancelPendingObservations()
        // Rebuild live descriptors after a display change, but retain opt-in
        // records. The next lookup rechecks reported and currently accepted
        // sizes before a saved minimum can constrain a new placement.
        store.clear(); descriptors.removeAll()
        saveAndNotify()
    }

    func reset(application bundleID: String) {
        cancelPendingObservations()
        for (key, descriptor) in descriptors where descriptor.record.identity.bundleID == bundleID {
            store.remove(key); descriptors.removeValue(forKey: key)
        }
        archive.remove(bundleID: bundleID)
        saveAndNotify()
    }

    func reset(recordID: UUID) {
        cancelPendingObservations()
        for (key, var descriptor) in descriptors where descriptor.record.id == recordID {
            store.remove(key)
            // A reset must not immediately fall back to another archived record
            // with the same identifier on the next lookup of this live window.
            descriptor.attemptedRestore = true
            descriptors[key] = descriptor
        }
        archive.remove(id: recordID)
        saveAndNotify()
    }

    private func removeRuntimeRecords(pid: pid_t) {
        for key in descriptors.keys where key.pid == pid {
            store.remove(key); descriptors.removeValue(forKey: key); pending.removeValue(forKey: key)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    private func saveAndNotify() {
        if remembers, !archive.records.isEmpty, let data = try? JSONEncoder().encode(archive) {
            UserDefaults.standard.set(data, forKey: Self.archiveKey)
        } else { UserDefaults.standard.removeObject(forKey: Self.archiveKey) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    private func identity(for window: AccessibilityElement, key: Key) -> WindowSizeLimitIdentity? {
        guard let app = NSRunningApplication(processIdentifier: key.pid), let bundleID = app.bundleIdentifier else { return nil }
        let metadata = window.sizeConstraintIdentity
        let info = app.bundleURL.flatMap(Bundle.init(url:))?.infoDictionary
        let version = [info?["CFBundleShortVersionString"] as? String, info?["CFBundleVersion"] as? String].compactMap { $0 }.joined(separator: "/")
        return WindowSizeLimitIdentity(bundleID: bundleID, appVersion: version, pid: key.pid, launch: key.launch,
            session: session, windowID: window.windowId ?? 0, identifier: metadata.identifier,
            role: metadata.role, subrole: metadata.subrole, structure: metadata.structure)
    }

    private func prepare(_ window: AccessibilityElement, key: Key) {
        synchronizePreference()
        let now = ProcessInfo.processInfo.systemUptime
        if let descriptor = descriptors[key], now - descriptor.checkedAt < 1 { return }
        guard let identity = identity(for: window, key: key) else { return }
        if var descriptor = descriptors[key] {
            // A sidebar or another structural layout change is evidence that a
            // previously learned minimum may no longer apply.
            if descriptor.record.identity.structure != identity.structure || descriptor.record.identity.identifier != identity.identifier {
                store.remove(key); archive.remove(id: descriptor.record.id)
                descriptor.attemptedRestore = true
                saveAndNotify()
            }
            descriptor.record.identity = identity; descriptor.checkedAt = now
            descriptors[key] = descriptor
        } else {
            let name = NSRunningApplication(processIdentifier: key.pid)?.localizedName ?? identity.bundleID
            descriptors[key] = Descriptor(record: WindowSizeLimitRecord(id: UUID(), identity: identity, appName: name,
                evidence: WindowSizeEvidence(reported: nil, learned: .zero, learnedAt: now)), checkedAt: now)
        }
        guard remembers, var descriptor = descriptors[key], !descriptor.attemptedRestore else { return }
        descriptor.attemptedRestore = true
        let live: [WindowSizeLimitIdentity]
        if archive.records.contains(where: { $0.identity.isSameLiveWindow(as: identity) }) {
            live = [identity]
        } else if identity.identifier != nil {
            live = (AccessibilityElement(key.pid).windowElements ?? []).compactMap { element in
                guard let candidateKey = self.key(for: element) else { return nil }
                return self.identity(for: element, key: candidateKey)
            }
        } else { live = [] }
        if var record = archive.match(identity, liveIdentities: live) {
            record.identity = identity
            descriptor.record = record
            store.restore(record.evidence, for: key, now: now)
            archive.upsert(record)
            descriptors[key] = descriptor
            saveAndNotify()
            return
        }
        descriptors[key] = descriptor
    }

    private func key(for window: AccessibilityElement) -> Key? {
        guard let pid = window.pid, let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, let launch = app.launchDate else { return nil }
        return Key(element: window, pid: pid, launch: launch.timeIntervalSinceReferenceDate)
    }

    func minimum(for window: AccessibilityElement, reported: CGSize?) -> CGSize? {
        guard let key = key(for: window) else { return reported }
        synchronizePreference()
        if !remembers && store.entries[key] == nil {
            // The default path needs no accessibility hierarchy inventory for
            // a window that has never supplied any learned evidence.
            return store.minimum(for: key, reported: reported, current: window.frame.size,
                now: ProcessInfo.processInfo.systemUptime)
        }
        prepare(window, key: key)
        let before = store.entries[key]
        let result = store.minimum(for: key, reported: reported, current: window.frame.size,
                                   now: ProcessInfo.processInfo.systemUptime)
        if before != store.entries[key] { synchronizeRecord(key) }
        return result
    }

    private func synchronizeRecord(_ key: Key) {
        guard var descriptor = descriptors[key] else { return }
        if let evidence = store.entries[key] {
            descriptor.record.evidence = evidence; descriptors[key] = descriptor
            if remembers { archive.upsert(descriptor.record) }
        } else { archive.remove(id: descriptor.record.id) }
        saveAndNotify()
    }

    func recordSettledResize(_ window: AccessibilityElement, before: CGRect, requested: CGRect,
                             first: CGRect, settled: CGRect, verifiedClamp: Bool = false, generation: UUID? = nil) {
        guard generation == nil || generation == observationGeneration else { return }
        guard let key = key(for: window), !before.isNull, !requested.isNull,
              LayoutHelperLayout.matches(first, settled, tolerance: 1) else { return }
        prepare(window, key: key)
        let previous = store.entries[key]
        store.observe(for: key, reported: window.reportedMinimumSize, before: before.size, requested: requested.size,
                      first: first.size, settled: settled.size, now: ProcessInfo.processInfo.systemUptime,
                      verifiedClamp: verifiedClamp)
        if previous != store.entries[key] { synchronizeRecord(key) }
    }

    /// Observe only the user's actual requested resize; never probe by secretly
    /// shrinking a window. A later command or manual grab cancels these samples.
    func observeResize(_ window: AccessibilityElement, before: CGRect, requested: CGRect, replacesEarlierAttempt: Bool = false) {
        guard let key = key(for: window), !before.isNull, !requested.isNull,
              before.size != requested.size else { return }
        let token = UUID()
        let original = Self.observationOrigin(before: before, requested: requested,
            earlierBefore: pending[key]?.before, earlierRequested: pending[key]?.requested,
            replacesEarlierAttempt: replacesEarlierAttempt)
        pending[key] = PendingResize(token: token, before: original, requested: requested)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.pending[key]?.token == token else { return }
            let first = window.frame
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, self.pending[key]?.token == token else { return }
                self.pending.removeValue(forKey: key)
                self.recordSettledResize(window, before: original, requested: requested, first: first, settled: window.frame)
            }
        }
    }

    func cancelPendingObservations() {
        pending.removeAll()
        observationGeneration = UUID()
        WindowSizeWarning.hideCurrent()
    }

    /// The command coordinator knows the true pre-animation frame. Its final
    /// observation must replace the raw mover's near-destination sample, while
    /// repeated raw writes retain their own first attempt's starting frame.
    static func observationOrigin(before: CGRect, requested: CGRect, earlierBefore: CGRect?,
                                  earlierRequested: CGRect?, replacesEarlierAttempt: Bool) -> CGRect {
        guard !replacesEarlierAttempt, let earlierBefore, let earlierRequested,
              LayoutHelperLayout.matches(earlierRequested, requested, tolerance: 1) else { return before }
        return earlierBefore
    }

    /// Used by batch and sidebar commands that do not go through WindowManager.
    @discardableResult func place(_ window: AccessibilityElement, target: CGRect, in bounds: CGRect) -> Bool {
        guard let fitted = Self.fitting(target, minimum: window.minimumSize, in: bounds) else { return false }
        window.setFrame(fitted)
        return true
    }

    /// Choose a grid that accommodates known minima before moving any windows.
    /// Columns and rows share the remaining space evenly after their minima are
    /// reserved. No tile expands into another tile when a known limit is large.
    static func tileFrames(in bounds: CGRect, minimumSizes: [CGSize?]) -> [CGRect]? {
        guard !minimumSizes.isEmpty, !bounds.isNull, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              minimumSizes.allSatisfy({ size in size.map { $0.width.isFinite && $0.height.isFinite && $0.width >= 0 && $0.height >= 0 } ?? true }) else { return nil }
        let count = minimumSizes.count, ideal = Int(ceil(sqrt(Double(minimumSizes.count))))
        let columnsToTry = (1...count).sorted { abs($0 - ideal) == abs($1 - ideal) ? $0 > $1 : abs($0 - ideal) < abs($1 - ideal) }
        func distribute(_ total: CGFloat, _ minimums: [CGFloat]) -> [CGFloat]? {
            guard minimums.reduce(0, +) <= total else { return nil }
            var result = [CGFloat](repeating: 0, count: minimums.count), remaining = total
            let ordered = minimums.indices.sorted { minimums[$0] > minimums[$1] }
            for (offset, index) in ordered.enumerated() {
                let size = max(minimums[index], remaining / CGFloat(ordered.count - offset))
                result[index] = size; remaining -= size
            }
            return result
        }
        for columns in columnsToTry {
            let rows = (count + columns - 1) / columns
            var widths = [CGFloat](repeating: 1, count: columns), heights = [CGFloat](repeating: 1, count: rows)
            for (index, minimum) in minimumSizes.enumerated() {
                widths[index % columns] = max(widths[index % columns], minimum?.width ?? 0)
                heights[index / columns] = max(heights[index / columns], minimum?.height ?? 0)
            }
            guard let widths = distribute(bounds.width, widths), let heights = distribute(bounds.height, heights) else { continue }
            return minimumSizes.indices.map { index in
                let column = index % columns, row = index / columns
                return CGRect(x: bounds.minX + widths.prefix(column).reduce(0, +),
                    y: bounds.minY + heights.prefix(row).reduce(0, +), width: widths[column], height: heights[row])
            }
        }
        return nil
    }

    /// Preserve the requested edge/center anchor when a minimum expands a snap.
    /// Both preview and execution call this function with the same gapped bounds.
    static func fitting(_ target: CGRect, minimum: CGSize?, in bounds: CGRect) -> CGRect? {
        guard !target.isNull, !bounds.isNull, target.width > 0, target.height > 0 else { return nil }
        guard let minimum else { return target }
        let width = max(target.width, minimum.width), height = max(target.height, minimum.height)
        if width == target.width && height == target.height { return target }
        guard width <= bounds.width + 1, height <= bounds.height + 1 else { return nil }
        func origin(_ start: CGFloat, _ length: CGFloat, _ expanded: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            if expanded == length { return start }
            let leading = abs(start - low), trailing = abs(high - start - length)
            let proposed = abs(leading - trailing) <= 2 ? start + (length - expanded) / 2
                : leading < trailing ? start : start + length - expanded
            return min(max(proposed, low), high - expanded)
        }
        return CGRect(x: origin(target.minX, target.width, width, bounds.minX, bounds.maxX),
                      y: origin(target.minY, target.height, height, bounds.minY, bounds.maxY),
                      width: width, height: height)
    }
}
