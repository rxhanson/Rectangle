import Cocoa

/// Shares window size evidence across snapping, previews, and coordinated moves.
final class WindowSizeConstraints {
    static let shared = WindowSizeConstraints()

    /// Disabled learning must not add AX or WindowServer reads to a mover write.
    static func frameBeforeResize(for window: AccessibilityElement) -> CGRect? {
        guard Defaults.rememberWindowSizeLimits.enabled else { return nil }
        return window.windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
    }

    static let changed = Notification.Name("windowSizeConstraintsChanged")
    private static let archiveKey = "windowSizeHints.v2"
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
        guard remembers else { return [] }
        var result = archive.records
        for (key, descriptor) in descriptors {
            guard let evidence = store.entries[key] else { continue }
            var record = descriptor.record; record.evidence = evidence
            result.removeAll { $0.id == record.id }
            result.append(record)
        }
        return result.sorted { ($0.appName.localizedLowercase, $0.identity.windowID) < ($1.appName.localizedLowercase, $1.identity.windowID) }
    }

    private init() {
        observations.append(NotificationCenter.default.addObserver(forName: .windowActionWillExecute,
            object: nil, queue: .main) { [weak self] note in
                // A nil payload represents an action such as minimizing outside WindowManager.
                if note.object == nil { self?.cancelPendingObservations() }
            })
        store.lifetime = nil
        if remembers, let data = UserDefaults.standard.data(forKey: Self.archiveKey) {
            archive = WindowSizeLimitArchive.decode(data) ?? WindowSizeLimitArchive()
        } else if !remembers {
            UserDefaults.standard.removeObject(forKey: Self.archiveKey)
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
        remembers = enabled
        cancelPendingObservations()
        store.clear()
        descriptors.removeAll()
        observationIdentities.removeAll()
        archive.clear()
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
        // records. Fresh reported constraints are checked again on the next
        // request; saved hints never constrain a new placement.
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
        for (key, descriptor) in descriptors where descriptor.record.id == recordID {
            store.remove(key)
            descriptors.removeValue(forKey: key)
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

    private let identityQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Rectangle.WindowSizeEvidence"
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var identityRequests: [Key: UUID] = [:]
    private var observationIdentities: [Key: WindowSizeLimitIdentity] = [:]
    private var observationCancellation = AccessibilityReadCancellation()

    private func observeVerifiedClamp(_ window: AccessibilityElement, key: Key, before: CGRect,
                                      requested: CGRect, settled: CGRect, generation: UUID) {
        guard remembers else { return }
        guard identityRequests[key] == nil, let id = window.windowId,
              let app = NSRunningApplication(processIdentifier: key.pid), let bundleID = app.bundleIdentifier else { return }
        let request = UUID()
        identityRequests[key] = request
        let name = app.localizedName ?? bundleID
        let info = app.bundleURL.flatMap(Bundle.init(url:))?.infoDictionary
        let version = [info?["CFBundleShortVersionString"] as? String, info?["CFBundleVersion"] as? String]
            .compactMap { $0 }.joined(separator: "/")
        let session = self.session
        let cancellation = observationCancellation
        identityQueue.addOperation { [weak self] in
            let reader = AccessibilityReadBatch(budget: 0.15, isCurrent: { cancellation.isCurrent })
            let application = AXUIElementCreateApplication(key.pid)
            let elements = reader.value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
            var identity: WindowSizeLimitIdentity?
            var reported: CGSize?
            if let element = elements.first(where: { reader.windowID($0) == id }) {
                let identifier = reader.value(element, kAXIdentifierAttribute) as? String
                let role = reader.value(element, kAXRoleAttribute) as? String ?? ""
                let subrole = reader.value(element, kAXSubroleAttribute) as? String ?? ""
                var structure: [String] = []
                if let children = reader.value(element, kAXChildrenAttribute) as? [AXUIElement], children.count <= 32 {
                    for child in children where reader.available {
                        structure.append([kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute]
                            .map { reader.value(child, $0) as? String ?? "" }.joined(separator: "|"))
                    }
                }
                reported = reader.wrapped(element, "AXMinSize", type: .cgSize)
                    ?? reader.wrapped(element, "AXMinimumSize", type: .cgSize)
                let position: CGPoint? = reader.wrapped(element, kAXPositionAttribute, type: .cgPoint)
                let size: CGSize? = reader.wrapped(element, kAXSizeAttribute, type: .cgSize)
                if reader.available, role == kAXWindowRole, let position, let size,
                   WindowGeometry.matches(CGRect(origin: position, size: size), settled, tolerance: 1),
                   let server = WindowUtil.getWindowFrame(id: id), WindowGeometry.matches(server, settled, tolerance: 1) {
                    identity = WindowSizeLimitIdentity(bundleID: bundleID, appVersion: version, pid: key.pid,
                        launch: key.launch, session: session, windowID: id, identifier: identifier,
                        role: role, subrole: subrole, structure: structure.sorted())
                }
            }
            let verifiedIdentity = identity
            let verifiedReported = reported
            DispatchQueue.main.async { [weak self] in
                guard let self, self.identityRequests[key] == request else { return }
                self.identityRequests.removeValue(forKey: key)
                guard self.remembers, self.observationGeneration == generation,
                      WindowProcessIdentity.launchTime(for: key.pid) == key.launch,
                      let identity = verifiedIdentity else { return }
                let now = Date.timeIntervalSinceReferenceDate
                if let old = self.observationIdentities[key], old != identity {
                    self.store.remove(key)
                    if let descriptor = self.descriptors[key] { self.archive.remove(id: descriptor.record.id) }
                }
                self.observationIdentities[key] = identity
                if self.observationIdentities.count > 128, let oldest = self.observationIdentities.keys.first(where: { $0 != key }) {
                    self.observationIdentities.removeValue(forKey: oldest)
                }
                let previous = self.store.entries[key]
                self.store.observe(for: key, reported: verifiedReported, before: before.size, requested: requested.size,
                    first: settled.size, settled: settled.size, now: now, verifiedClamp: true, operation: generation)
                guard previous != self.store.entries[key], let evidence = self.store.entries[key] else { return }
                let id = self.archive.match(identity)?.id ?? self.descriptors[key]?.record.id ?? UUID()
                self.descriptors[key] = Descriptor(record: WindowSizeLimitRecord(id: id, identity: identity,
                    appName: name, evidence: evidence))
                self.synchronizeRecord(key)
            }
        }
    }

    private func key(for window: AccessibilityElement) -> Key? {
        guard let pid = window.pid, let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, let launch = WindowProcessIdentity.launchTime(for: pid) else { return nil }
        return Key(element: window, pid: pid, launch: launch)
    }

    func minimum(for window: AccessibilityElement, reported: CGSize?) -> CGSize? {
        synchronizePreference()
        guard remembers else { return reported }
        guard let key = key(for: window) else { return reported }
        let previous = store.entries[key]
        let result = store.minimum(for: key, reported: reported, current: .zero,
                                   now: Date.timeIntervalSinceReferenceDate)
        if previous != store.entries[key] { synchronizeRecord(key) }
        return result
    }

    /// Historical evidence guides animation, previews, and divider bounds.
    /// Placement must still be verified against the live app.
    func rememberedMinimum(for window: AccessibilityElement) -> CGSize? {
        synchronizePreference()
        guard remembers else { return nil }
        guard let key = key(for: window) else { return nil }
        if store.entries[key] == nil { restoreRememberedHint(window, key: key) }
        // Most windows have no learned hint. Do not make extra AX requests on
        // every preview just to ask an empty store for one.
        guard let previous = store.entries[key] else { return nil }
        let result = store.hint(for: key, reported: window.reportedMinimumSize,
                                current: window.size ?? .zero, now: Date.timeIntervalSinceReferenceDate)
        if previous != store.entries[key] { synchronizeRecord(key) }
        return result
    }

    /// Main-thread snapshot for asynchronous animation setup. Identity checks
    /// use local process metadata; missing persisted hints restore asynchronously.
    func rememberedMinimumSnapshot(for window: AccessibilityElement) -> WindowSizeHintSnapshot? {
        synchronizePreference()
        guard remembers, let key = key(for: window) else { return nil }
        if store.entries[key] == nil { restoreRememberedHint(window, key: key) }
        return store.hintSnapshot(for: key, cancellation: observationCancellation)
    }

    /// Reconcile worker observations only if neither the action nor its evidence
    /// changed while the optional metadata was read. Call on the main thread.
    func reconcileRememberedMinimum(for window: AccessibilityElement, snapshot: WindowSizeHintSnapshot,
                                    reported: CGSize?, current: CGSize) {
        guard remembers, snapshot.isCurrent, let key = key(for: window),
              store.entries[key] == snapshot.evidence else { return }
        _ = store.hint(for: key, reported: reported, current: current, now: Date.timeIntervalSinceReferenceDate)
        if store.entries[key] != snapshot.evidence { synchronizeRecord(key) }
    }

    private func restoreRememberedHint(_ window: AccessibilityElement, key: Key) {
        guard remembers, identityRequests[key] == nil else { return }
        let candidates = archive.records.filter {
            $0.identity.pid == key.pid && $0.identity.launch == key.launch && $0.identity.session == session
        }
        guard !candidates.isEmpty, let app = NSRunningApplication(processIdentifier: key.pid) else { return }
        let bundleID = app.bundleIdentifier
        let bundleURL = app.bundleURL
        let preferred = window.axElement
        let request = UUID()
        identityRequests[key] = request
        let cancellation = observationCancellation
        identityQueue.addOperation { [weak self] in
            var identity: WindowSizeLimitIdentity?
            var matchingRecord: WindowSizeLimitRecord?
            let reader = AccessibilityReadBatch(budget: 0.15, isCurrent: { cancellation.isCurrent })
            if let id = reader.windowID(preferred),
               let record = candidates.first(where: { $0.identity.windowID == id && $0.identity.bundleID == bundleID }) {
                // Reading another app's Info.plist is optional persistence work,
                // and must not delay keyboard animation setup on the main queue.
                let info = bundleURL.flatMap(Bundle.init(url:))?.infoDictionary
                let version = [info?["CFBundleShortVersionString"] as? String, info?["CFBundleVersion"] as? String]
                    .compactMap { $0 }.joined(separator: "/")
                let elements = record.identity.appVersion == version
                    ? reader.value(AXUIElementCreateApplication(key.pid), kAXWindowsAttribute) as? [AXUIElement] ?? [] : []
                if let element = elements.first(where: { reader.windowID($0) == id }) {
                    var candidate = record.identity
                    candidate.identifier = reader.value(element, kAXIdentifierAttribute) as? String
                    candidate.role = reader.value(element, kAXRoleAttribute) as? String ?? ""
                    candidate.subrole = reader.value(element, kAXSubroleAttribute) as? String ?? ""
                    var structure: [String] = []
                    if let children = reader.value(element, kAXChildrenAttribute) as? [AXUIElement], children.count <= 32 {
                        for child in children where reader.available {
                            structure.append([kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute]
                                .map { reader.value(child, $0) as? String ?? "" }.joined(separator: "|"))
                        }
                    }
                    candidate.structure = structure.sorted()
                    if reader.available { identity = candidate; matchingRecord = record }
                }
            }
            let checked = identity
            let record = matchingRecord
            DispatchQueue.main.async { [weak self] in
                guard let self, self.identityRequests[key] == request else { return }
                self.identityRequests.removeValue(forKey: key)
                guard self.remembers, self.store.entries[key] == nil,
                      WindowProcessIdentity.launchTime(for: key.pid) == key.launch,
                      let checked, let record, let match = self.archive.match(checked), match == record else { return }
                self.store.restore(match.evidence, for: key, now: Date.timeIntervalSinceReferenceDate)
                self.descriptors[key] = Descriptor(record: match)
            }
        }
    }

    static func animationSize(_ requested: CGSize, origin: CGSize, hint: CGSize?) -> CGSize {
        guard let hint else { return requested }
        func axis(_ requested: CGFloat, _ origin: CGFloat, _ hint: CGFloat) -> CGFloat {
            guard hint.isFinite, hint > 0, hint <= origin + 2, requested < origin else { return requested }
            return max(requested, min(origin, hint))
        }
        return CGSize(width: axis(requested.width, origin.width, hint.width),
                      height: axis(requested.height, origin.height, hint.height))
    }

    func recordSuccessfulPlacement(_ window: AccessibilityElement, frame: CGRect) {
        synchronizePreference()
        guard remembers else { return }
        guard let key = key(for: window), WindowAnimationGeometry.valid(frame) else { return }
        let previous = store.entries[key]
        store.recordSuccess(for: key, size: frame.size)
        // A saved record for this same live window must also be invalidated,
        // even when no hint has been loaded in this Rectangle process yet.
        let id = window.windowId
        var changed = false
        for var record in archive.records where record.identity.pid == key.pid
            && record.identity.launch == key.launch && record.identity.session == session
            && record.identity.windowID == id {
            if frame.width + 2 < record.evidence.learned.width { record.evidence.learned.width = 0; changed = true }
            if frame.height + 2 < record.evidence.learned.height { record.evidence.learned.height = 0; changed = true }
            if record.evidence.isValid { archive.upsert(record) } else { archive.remove(id: record.id) }
        }
        if previous != store.entries[key] { synchronizeRecord(key) }
        else if changed { saveAndNotify() }
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
        synchronizePreference()
        guard remembers else { return }
        guard generation == nil || generation == observationGeneration else { return }
        guard let key = key(for: window), !before.isNull, !requested.isNull,
              WindowGeometry.matches(first, settled, tolerance: 1) else { return }
        guard let id = window.windowId, let server = WindowUtil.getWindowFrame(id: id),
              WindowGeometry.matches(server, settled, tolerance: 1) else { return }
        if WindowGeometry.matches(requested, settled, tolerance: 1) {
            recordSuccessfulPlacement(window, frame: settled)
            return
        }
        guard verifiedClamp else { return }
        observeVerifiedClamp(window, key: key, before: before, requested: requested, settled: settled,
                             generation: generation ?? observationGeneration)
    }

    /// Observe only the user's actual requested resize; never probe by secretly
    /// shrinking a window. A later command or manual grab cancels these samples.
    func observeResize(_ window: AccessibilityElement, before: CGRect, requested: CGRect, replacesEarlierAttempt: Bool = false) {
        synchronizePreference()
        guard remembers else { return }
        guard let key = key(for: window), !before.isNull, !requested.isNull,
              before.size != requested.size else { return }
        let token = UUID()
        let original = Self.observationOrigin(before: before, requested: requested,
            earlierBefore: pending[key]?.before, earlierRequested: pending[key]?.requested,
            replacesEarlierAttempt: replacesEarlierAttempt)
        pending[key] = PendingResize(token: token, before: original, requested: requested)
        guard let id = window.windowId else { pending.removeValue(forKey: key); return }
        let generation = observationGeneration
        let cancellation = observationCancellation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.pending[key]?.token == token else { return }
            self.identityQueue.addOperation { [weak self] in
                var confirmed: CGRect?
                if let element = WindowAccessibilityLookup.resolve(pid: key.pid, id: id, launch: key.launch,
                    preferred: nil, isCurrent: { cancellation.isCurrent }) {
                    let eligibility = AccessibilityReadBatch(budget: 0.15, isCurrent: { cancellation.isCurrent })
                    let eligible = eligibility.value(element, kAXRoleAttribute) as? String == kAXWindowRole
                        && eligibility.value(element, kAXSubroleAttribute) as? String != kAXSystemDialogSubrole
                        && eligibility.settable(element, kAXSizeAttribute) != false && eligibility.available
                    var observation = WindowSizeResizeObservation(before: original, requested: requested)
                    let deadline = ProcessInfo.processInfo.systemUptime + 0.45
                    while eligible, cancellation.isCurrent, ProcessInfo.processInfo.systemUptime < deadline,
                          WindowProcessIdentity.launchTime(for: key.pid) == key.launch {
                        let reader = AccessibilityReadBatch(budget: min(0.1, deadline - ProcessInfo.processInfo.systemUptime),
                            isCurrent: { cancellation.isCurrent })
                        var frame: CGRect?
                        if reader.windowID(element) == id,
                           let position: CGPoint = reader.wrapped(element, kAXPositionAttribute, type: .cgPoint),
                           let size: CGSize = reader.wrapped(element, kAXSizeAttribute, type: .cgSize),
                           reader.available, let server = WindowUtil.getWindowFrame(id: id) {
                            let actual = CGRect(origin: position, size: size)
                            if WindowGeometry.matches(actual, server, tolerance: 1) { frame = actual }
                        }
                        if let settled = observation.observe(frame, at: ProcessInfo.processInfo.systemUptime) {
                            confirmed = settled
                            break
                        }
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                }
                let result = confirmed
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.pending[key]?.token == token else { return }
                    self.pending.removeValue(forKey: key)
                    guard self.observationGeneration == generation,
                          WindowProcessIdentity.launchTime(for: key.pid) == key.launch, let result else { return }
                    self.recordSettledResize(window, before: original, requested: requested,
                        first: result, settled: result, verifiedClamp: true, generation: generation)
                }
            }
        }
    }

    func cancelPendingObservations() {
        observationCancellation.cancel()
        observationCancellation = AccessibilityReadCancellation()
        pending.removeAll()
        identityRequests.removeAll()
        identityQueue.cancelAllOperations()
        observationGeneration = UUID()
        WindowPlacementCoordinator.shared.cancelAll()
        WindowSizeWarning.hideCurrent()
    }

    /// Prefer the coordinator's pre-animation frame. Otherwise, repeated mover
    /// writes keep the first attempt's frame so size-limit detection sees the full resize.
    static func observationOrigin(before: CGRect, requested: CGRect, earlierBefore: CGRect?,
                                  earlierRequested: CGRect?, replacesEarlierAttempt: Bool) -> CGRect {
        guard !replacesEarlierAttempt, let earlierBefore, let earlierRequested,
              WindowGeometry.matches(earlierRequested, requested, tolerance: 1) else { return before }
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
