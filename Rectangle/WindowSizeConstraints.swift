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
        func clamp(_ old: CGFloat, _ target: CGFloat, _ actual: CGFloat) -> CGFloat {
            // No size progress can mean an ignored write, even when position
            // succeeded. It is not evidence of a minimum equal to the old size.
            target + 2 < actual && actual < old - 1 ? actual : 0
        }
        let learned = CGSize(width: clamp(before.width, requested.width, settled.width),
                             height: clamp(before.height, requested.height, settled.height))
        // Coupled dimensions may be an aspect ratio or sizing grid, not minima.
        guard (learned.width > 0) != (learned.height > 0),
              learned.width > 0 ? abs(requested.height - settled.height) <= 1
                                : abs(requested.width - settled.width) <= 1 else { return }
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

/// Shared by ordinary snapping, drag previews, Layout Helper and cooperative moves.
final class WindowSizeConstraints {
    static let shared = WindowSizeConstraints()
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
        identityQueue.addOperation { [weak self] in
            let reader = AccessibilityReadBatch(budget: 0.15)
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
                   LayoutHelperLayout.matches(CGRect(origin: position, size: size), settled, tolerance: 1),
                   let server = WindowUtil.getWindowFrame(id: id), LayoutHelperLayout.matches(server, settled, tolerance: 1) {
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
        let previous = store.entries[key]
        let result = store.hint(for: key, reported: window.reportedMinimumSize,
                                current: window.size ?? .zero, now: Date.timeIntervalSinceReferenceDate)
        if previous != store.entries[key] { synchronizeRecord(key) }
        return result
    }

    private func restoreRememberedHint(_ window: AccessibilityElement, key: Key) {
        guard remembers, identityRequests[key] == nil, let id = window.windowId,
              let record = archive.records.first(where: {
                  $0.identity.pid == key.pid && $0.identity.launch == key.launch
                      && $0.identity.session == session && $0.identity.windowID == id
              }), let app = NSRunningApplication(processIdentifier: key.pid) else { return }
        let info = app.bundleURL.flatMap(Bundle.init(url:))?.infoDictionary
        let version = [info?["CFBundleShortVersionString"] as? String, info?["CFBundleVersion"] as? String]
            .compactMap { $0 }.joined(separator: "/")
        guard record.identity.bundleID == app.bundleIdentifier, record.identity.appVersion == version else { return }
        let request = UUID()
        identityRequests[key] = request
        identityQueue.addOperation { [weak self] in
            let reader = AccessibilityReadBatch(budget: 0.15)
            let elements = reader.value(AXUIElementCreateApplication(key.pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
            var identity: WindowSizeLimitIdentity?
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
                if reader.available { identity = candidate }
            }
            let checked = identity
            DispatchQueue.main.async { [weak self] in
                guard let self, self.identityRequests[key] == request else { return }
                self.identityRequests.removeValue(forKey: key)
                guard self.remembers, self.store.entries[key] == nil,
                      WindowProcessIdentity.launchTime(for: key.pid) == key.launch,
                      let checked, let match = self.archive.match(checked), match == record else { return }
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
              LayoutHelperLayout.matches(first, settled, tolerance: 1) else { return }
        guard let id = window.windowId, let server = WindowUtil.getWindowFrame(id: id),
              LayoutHelperLayout.matches(server, settled, tolerance: 1) else { return }
        if LayoutHelperLayout.matches(requested, settled, tolerance: 1) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.pending[key]?.token == token else { return }
            self.identityQueue.addOperation { [weak self] in
                let reader = AccessibilityReadBatch(budget: 0.15)
                let app = AXUIElementCreateApplication(key.pid)
                let windows = reader.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
                var confirmed: CGRect?
                if let element = windows.first(where: { reader.windowID($0) == id }),
                   let position: CGPoint = reader.wrapped(element, kAXPositionAttribute, type: .cgPoint),
                   let size: CGSize = reader.wrapped(element, kAXSizeAttribute, type: .cgSize),
                   reader.available, let server = WindowUtil.getWindowFrame(id: id) {
                    let frame = CGRect(origin: position, size: size)
                    if LayoutHelperLayout.matches(frame, requested, tolerance: 1),
                       LayoutHelperLayout.matches(frame, server, tolerance: 1) { confirmed = frame }
                }
                let result = confirmed
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.pending[key]?.token == token else { return }
                    self.pending.removeValue(forKey: key)
                    guard WindowProcessIdentity.launchTime(for: key.pid) == key.launch, let result else { return }
                    self.recordSuccessfulPlacement(window, frame: result)
                }
            }
        }
    }

    func cancelPendingObservations() {
        pending.removeAll()
        identityRequests.removeAll()
        identityQueue.cancelAllOperations()
        observationGeneration = UUID()
        WindowPlacementCoordinator.shared.cancelAll()
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
