import Cocoa

/// Render candidates from copied metadata without waiting for app replies.
/// Selection refreshes the snapshot and AX reference before placement.
struct LayoutHelperWindowSnapshot {
    let id: CGWindowID
    let pid: pid_t
    let launch: TimeInterval
    let bundleID: String
    let title: String
    let frame: CGRect
    let reportedMinimum: CGSize?
    let resizable: Bool?
    let element: AXUIElement?
    let observedAt: TimeInterval
    var isMinimized = false
    var desktopDisplays = Set<CGDirectDisplayID>()
    var isMainWindow: Bool?

    var previewKey: LayoutHelperPreviewKey {
        LayoutHelperPreviewKey(id: id, pid: pid, launch: launch,
                               width: Int(frame.width.rounded()), height: Int(frame.height.rounded()))
    }
    func accessibilityElement() -> AccessibilityElement? {
        element.map { AccessibilityElement($0, messagingTimeout: 0.05, windowID: id) }
    }
}

/// Main-thread scheduling, at most three application batches, one per PID.
/// Refreshes replace demand instead of accumulating scans behind a slow app.
final class LayoutHelperWindowCatalog {
    private struct Application {
        let pid: pid_t
        let launch: TimeInterval
        let bundle: String
        let name: String
        let infos: [WindowInfo]
        let desktopDisplays: [CGWindowID: Set<CGDirectDisplayID>]
    }
    private struct Batch {
        let windows: [LayoutHelperWindowSnapshot]
        let checked: Set<CGWindowID>
        let timedOut: Bool
        var observer: AXObserver?
    }
    private(set) var snapshots: [CGWindowID: LayoutHelperWindowSnapshot] = [:]
    private var applications: [pid_t: Application] = [:]
    private var order: [CGWindowID] = []
    private var waiting: [pid_t] = []
    private var continuations: [pid_t: Application] = [:]
    private var running = Set<pid_t>()
    private var failures: [pid_t: (count: Int, retryAt: TimeInterval)] = [:]
    private var demands: [CGWindowID: [(LayoutHelperWindowSnapshot?) -> Void]] = [:]
    private var rejected = Set<CGWindowID>()
    private var generation = 0
    private var observers: [pid_t: AXObserver] = [:]
    private var invalidation: DispatchWorkItem?
    private var updateDelivery: DispatchWorkItem?
    private var refreshID = 0
    private var enumerating = false
    private var enumerationRunning = false
    private var refreshAgain = false
    private var cancellation = Cancellation()
    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    }
    private let windowList: () -> [WindowInfo]
    private let desktopWindows: ([String: CGDirectDisplayID], Bool) -> [CGWindowID: Set<CGDirectDisplayID>]
    private(set) var isSuspended = false
    var didUpdate: (() -> Void)?
    var isRefreshing: Bool { enumerating || !running.isEmpty || !waiting.isEmpty }

    init(windowList: @escaping () -> [WindowInfo] = {
        WindowUtil.getWindowList(all: true, forceRefresh: true, cacheResult: false)
    }, desktopWindows: @escaping ([String: CGDirectDisplayID], Bool) -> [CGWindowID: Set<CGDirectDisplayID>] = LayoutHelperDesktopScope.read) {
        self.windowList = windowList
        self.desktopWindows = desktopWindows
    }

    func stop() {
        isSuspended = false
        discardPendingWork()
        didUpdate = nil
    }

    /// Keep the picker snapshots, but release observers and discard in-flight
    /// results while placement owns the selected window's Accessibility calls.
    func suspendForPlacement() {
        guard !isSuspended else { return }
        isSuspended = true
        discardPendingWork()
    }

    func resumeAfterPlacement() {
        guard isSuspended else { return }
        isSuspended = false
        refresh()
    }

    private func discardPendingWork() {
        generation += 1
        refreshID += 1; enumerating = false; refreshAgain = false
        cancellation.cancel(); cancellation = Cancellation()
        updateDelivery?.cancel(); updateDelivery = nil
        waiting.removeAll(); continuations.removeAll(); demands.removeAll()
        invalidation?.cancel(); invalidation = nil
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
    }

    func windows(on screen: NSScreen) -> [LayoutHelperWindowSnapshot] {
        let detection = ScreenDetection()
        // Only physical NSScreen instances expose device information. Synthetic
        // screens used by calculations need no minimized-window membership.
        let physical = NSScreen.screens.first { $0 === screen || $0.frame == screen.frame }
        let display = (physical?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        return order.compactMap { snapshots[$0] }.filter { snapshot in
            Self.matchesScreen(detection.screenContaining(snapshot.frame, screens: NSScreen.screens), requested: screen)
                && (!snapshot.isMinimized || display.map { snapshot.desktopDisplays.contains($0) } == true)
        }
    }

    static func matchesScreen(_ candidate: NSScreen?, requested: NSScreen) -> Bool {
        guard let candidate else { return false }
        // NSScreen's equality requires AppKit's internal display identity, which
        // calculation-only screen instances do not have. Match their geometry.
        return candidate === requested || candidate.frame == requested.frame
    }

    func refresh() {
        guard !isSuspended else { return }
        // A WindowServer request cannot be cancelled. Keep its slot until it
        // returns, including across stop/resume, and replace follow-up demand.
        guard !enumerationRunning else { refreshAgain = true; enumerating = true; return }
        enumerationRunning = true
        WindowAnimationDiagnostics.event("helper-catalog-refresh")
        let ignored = Set((Defaults.disabledApps.typedValue ?? []) + (Defaults.fullIgnoreBundleIds.typedValue ?? []))
        let excludedTodo = Defaults.todo.userEnabled ? TodoManager.cachedWindowID : nil
        // AppKit state is copied on its owning thread before background enumeration.
        let appInfo = NSWorkspace.shared.runningApplications.reduce(into: [pid_t: (TimeInterval, String, String)]()) { result, app in
            guard !app.isTerminated, !app.isHidden, app.activationPolicy == .regular,
                  !ignored.contains(app.bundleIdentifier ?? ""), let launch = WindowProcessIdentity.launchTime(for: app.processIdentifier) else { return }
            result[app.processIdentifier] = (launch, app.bundleIdentifier ?? "", app.localizedName ?? "Window")
        }
        refreshID += 1
        let request = refreshID
        let epoch = generation
        let cancellation = cancellation
        let windowList = windowList
        let desktopWindows = desktopWindows
        let displays = NSScreen.screens.reduce(into: [String: CGDirectDisplayID]()) { result, screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return }
            result[CFUUIDCreateString(nil, uuid) as String] = number.uint32Value
        }
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        enumerating = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scope = cancellation.isCancelled ? [:] : desktopWindows(displays, separateSpaces)
            let infos = (cancellation.isCancelled ? [] : windowList()).filter {
                ($0.isOnScreen || scope[$0.id] != nil) && $0.level == 0 && $0.pid != getpid() && WindowAnimationGeometry.valid($0.frame) && $0.id != excludedTodo
            }
            let applications = Dictionary(grouping: infos, by: \.pid).reduce(into: [pid_t: Application]()) { result, group in
                guard let app = appInfo[group.key] else { return }
                result[group.key] = Application(pid: group.key, launch: app.0, bundle: app.1, name: app.2, infos: group.value, desktopDisplays: scope)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.enumerationRunning = false
                self.enumerating = false
                let refreshAgain = self.refreshAgain
                self.refreshAgain = false
                if self.generation == epoch, self.refreshID == request, !self.isSuspended {
                    self.apply(infos: infos, applications: applications)
                }
                if refreshAgain { self.refresh() }
            }
        }
    }

    private func apply(infos: [WindowInfo], applications: [pid_t: Application]) {
        self.applications = applications
        order = infos.filter { applications[$0.pid] != nil }.map(\.id)
        for (pid, observer) in observers where applications[pid] == nil {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers.removeValue(forKey: pid)
        }
        let live = Set(order)
        rejected.formIntersection(live)
        snapshots = snapshots.filter { live.contains($0.key) && applications[$0.value.pid]?.launch == $0.value.launch }
        for application in applications.values {
            for info in application.infos where info.isOnScreen && snapshots[info.id] == nil && !rejected.contains(info.id) {
                snapshots[info.id] = LayoutHelperWindowSnapshot(id: info.id, pid: info.pid, launch: application.launch,
                    bundleID: application.bundle, title: application.name, frame: info.frame,
                    reportedMinimum: nil, resizable: nil, element: nil, observedAt: 0)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        var seen = Set<pid_t>()
        waiting = infos.map(\.pid).filter { pid in
            applications[pid] != nil && !running.contains(pid) && seen.insert(pid).inserted
                && (failures[pid]?.retryAt ?? 0) <= now
        }
        scheduleUpdate()
        pump()
    }

    /// A click gets one fresh batch for its application, never a desktop rescan.
    func resolve(_ id: CGWindowID, completion: @escaping (LayoutHelperWindowSnapshot?) -> Void) {
        WindowAnimationDiagnostics.event("helper-resolve-request", fields: ["windowID": id,
            "snapshot": snapshots[id] != nil, "suspended": isSuspended])
        guard !isSuspended, let snapshot = snapshots[id], applications[snapshot.pid] != nil else { completion(nil); return }
        demands[id, default: []].append(completion)
        failures[snapshot.pid] = nil
        if !running.contains(snapshot.pid) {
            waiting.removeAll { $0 == snapshot.pid }
            waiting.insert(snapshot.pid, at: 0)
        }
        pump()
    }

    private func pump() {
        guard !isSuspended else { return }
        while running.count < 3, !waiting.isEmpty {
            let pid = waiting.removeFirst()
            guard let application = continuations.removeValue(forKey: pid) ?? applications[pid],
                  running.insert(pid).inserted else { continue }
            let epoch = generation
            let cancellation = cancellation
            let observe = observers[pid] == nil
            let context = Unmanaged.passUnretained(self).toOpaque()
            let preferred = demands.keys.first(where: { snapshots[$0]?.pid == pid }).flatMap { snapshots[$0]?.element }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let batch = Self.scan(application, observe: observe, context: context, preferred: preferred, cancellation: cancellation)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.running.remove(pid)
                    guard self.applications[pid]?.launch == application.launch else { self.pump(); return }
                    guard epoch == self.generation else {
                        if !self.isSuspended, self.didUpdate != nil, !self.waiting.contains(pid) { self.waiting.append(pid) }
                        self.pump()
                        return
                    }
                    let live = Set(self.order)
                    let found = Set(batch.windows.map(\.id))
                    if !batch.timedOut {
                        self.failures[pid] = nil
                        for id in batch.checked where !found.contains(id) {
                            self.snapshots.removeValue(forKey: id); self.rejected.insert(id)
                        }
                    } else {
                        let count = min(5, (self.failures[pid]?.count ?? 0) + 1)
                        self.failures[pid] = (count, ProcessInfo.processInfo.systemUptime + min(10, pow(2, Double(count - 1))))
                    }
                    for window in batch.windows where live.contains(window.id) {
                        self.snapshots[window.id] = window; self.rejected.remove(window.id)
                    }
                    if epoch == self.generation {
                        if let observer = batch.observer, self.observers[pid] == nil {
                            self.observers[pid] = observer
                            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                        }
                        for id in application.infos.map(\.id) where batch.checked.contains(id) || batch.timedOut || batch.checked.isEmpty {
                            let callbacks = self.demands.removeValue(forKey: id) ?? []
                            let fresh = batch.windows.first { $0.id == id }
                            if !callbacks.isEmpty {
                                WindowAnimationDiagnostics.event("helper-resolve-result", fields: ["windowID": id,
                                    "found": fresh != nil, "timedOut": batch.timedOut,
                                    "checked": batch.checked.contains(id), "checkedCount": batch.checked.count])
                            }
                            callbacks.forEach { $0(fresh) }
                        }
                        self.scheduleUpdate()
                    }
                    let remaining = application.infos.filter { !batch.checked.contains($0.id) && live.contains($0.id) }
                    if epoch == self.generation, !batch.timedOut, !batch.checked.isEmpty, !remaining.isEmpty {
                        self.continuations[pid] = Application(pid: pid, launch: application.launch,
                            bundle: application.bundle, name: application.name, infos: remaining, desktopDisplays: application.desktopDisplays)
                        if !self.waiting.contains(pid) { self.waiting.append(pid) }
                    } else if self.demands.keys.contains(where: { self.snapshots[$0]?.pid == pid }) {
                        if !self.waiting.contains(pid) { self.waiting.insert(pid, at: 0) }
                    }
                    self.pump()
                }
            }
        }
    }

    private func scheduleUpdate() {
        guard updateDelivery == nil else { return }
        let epoch = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == epoch else { return }
            self.updateDelivery = nil
            self.didUpdate?()
        }
        updateDelivery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
    }

    private func invalidate() {
        guard !isSuspended, didUpdate != nil, invalidation == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.invalidation = nil
            if self.didUpdate != nil { self.refresh() }
        }
        invalidation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    static func admits(onScreen: Bool, minimized: Bool?, desktopDisplays: Set<CGDirectDisplayID>) -> Bool {
        minimized == true ? !desktopDisplays.isEmpty : onScreen
    }

    private static func scan(_ application: Application, observe: Bool, context: UnsafeMutableRawPointer,
                             preferred: AXUIElement?, cancellation: Cancellation) -> Batch {
        guard !cancellation.isCancelled else { return Batch(windows: [], checked: [], timedOut: false) }
        let reader = AccessibilityReadBatch(budget: 0.15)
        let app = AXUIElementCreateApplication(application.pid)
        guard let elements = reader.value(app, kAXWindowsAttribute) as? [AXUIElement] else {
            return Batch(windows: [], checked: [], timedOut: true)
        }
        var result: [LayoutHelperWindowSnapshot] = []
        var checked = Set<CGWindowID>()
        var matched = Set<CGWindowID>()
        let ordered = preferred.map { preferred in [preferred] + elements.filter { !CFEqual($0, preferred) } } ?? elements
        for element in ordered {
            guard reader.available, !cancellation.isCancelled else { break }
            // ID lookup is an application RPC too and shares the batch budget.
            let id = reader.windowID(element)
            guard let info = application.infos.first(where: { $0.id == id }) else { continue }
            matched.insert(info.id)
            // Mark rejected roles only after a successful read. A timeout is
            // not evidence that a still-visible window has disappeared.
            defer { if reader.available { checked.insert(info.id) } }
            guard reader.value(element, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
            let subrole = reader.value(element, kAXSubroleAttribute) as? String
            if subrole == kAXSystemDialogSubrole || subrole == kAXFloatingWindowSubrole { continue }
            let minimized = reader.value(element, kAXMinimizedAttribute) as? Bool
            guard Self.admits(onScreen: info.isOnScreen, minimized: minimized,
                              desktopDisplays: application.desktopDisplays[info.id] ?? []) else { continue }
            if reader.value(element, "AXFullScreen") as? Bool == true { continue }
            guard let position: CGPoint = reader.wrapped(element, kAXPositionAttribute, type: .cgPoint),
                  let size: CGSize = reader.wrapped(element, kAXSizeAttribute, type: .cgSize) else { continue }
            let frame = CGRect(origin: position, size: size)
            guard WindowAnimationGeometry.valid(frame) else { continue }
            let title = reader.value(element, kAXTitleAttribute) as? String
            let minimum: CGSize? = reader.wrapped(element, "AXMinSize", type: .cgSize)
                ?? reader.wrapped(element, "AXMinimumSize", type: .cgSize)
            let resizable = reader.settable(element, kAXSizeAttribute)
            let isMainWindow = reader.value(element, kAXMainAttribute) as? Bool
            guard reader.available, !cancellation.isCancelled else { break }
            result.append(LayoutHelperWindowSnapshot(id: info.id, pid: application.pid, launch: application.launch,
                bundleID: application.bundle, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? application.name,
                frame: frame, reportedMinimum: minimum, resizable: resizable, element: element,
                observedAt: ProcessInfo.processInfo.systemUptime, isMinimized: minimized == true,
                desktopDisplays: application.desktopDisplays[info.id] ?? [], isMainWindow: isMainWindow))
        }
        if reader.available {
            checked.formUnion(application.infos.map(\.id).filter { !matched.contains($0) })
        }
        var observer: AXObserver?
        if observe, reader.available, !cancellation.isCancelled {
            let callback: AXObserverCallback = { _, _, _, context in
                guard let context else { return }
                Unmanaged<LayoutHelperWindowCatalog>.fromOpaque(context).takeUnretainedValue().invalidate()
            }
            if AXObserverCreate(application.pid, callback, &observer) == .success, let observer {
                for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                                     kAXWindowMovedNotification, kAXWindowResizedNotification] where reader.available {
                    reader.observe(observer, app, notification, context: context)
                }
            }
        }
        return Batch(windows: result, checked: checked, timedOut: reader.timedOut, observer: observer)
    }
}


/// Query each active desktop once, including its minimized windows. Ordinary
/// onscreen candidates do not depend on these optional WindowServer symbols.
/// This scope is deliberately read-only: the helper never moves a window to a Space.
enum LayoutHelperDesktopScope {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Displays = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias Windows = @convention(c) (UInt32, Int32, CFArray, UInt32,
        UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)

    private static func lookup<T>(_ names: [String], as type: T.Type) -> T? {
        guard let library else { return nil }
        for name in names {
            if let address = dlsym(library, name) { return unsafeBitCast(address, to: type) }
        }
        return nil
    }

    static func read(displays: [String: CGDirectDisplayID], separateSpaces: Bool) -> [CGWindowID: Set<CGDirectDisplayID>] {
        guard let connection = lookup(["SLSMainConnectionID", "CGSMainConnectionID"], as: Connection.self),
              let displayList = lookup(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: Displays.self),
              let windows = lookup(["SLSCopyWindowsWithOptionsAndTags", "CGSCopyWindowsWithOptionsAndTags"], as: Windows.self),
              let rows = displayList(connection())?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        let desktops = activeDesktops(rows, displays: displays, separateSpaces: separateSpaces)
        var result: [CGWindowID: Set<CGDirectDisplayID>] = [:]
        for (space, screens) in desktops {
            var requiredTags: UInt64 = 0, excludedTags: UInt64 = 0
            // 0x7 includes minimized windows; scope remains the selected desktop.
            guard let list = windows(connection(), 0, [NSNumber(value: space)] as CFArray,
                                     0x7, &requiredTags, &excludedTags)?.takeRetainedValue() as? [NSNumber] else { continue }
            for number in list where number.uint32Value != 0 {
                result[number.uint32Value, default: []].formUnion(screens)
            }
        }
        return result
    }

    static func activeDesktops(_ rows: [[String: Any]], displays: [String: CGDirectDisplayID],
                               separateSpaces: Bool) -> [UInt64: Set<CGDirectDisplayID>] {
        var result: [UInt64: Set<CGDirectDisplayID>] = [:]
        for row in rows {
            guard let current = row["Current Space"] as? [String: Any],
                  let number = current["id64"] as? NSNumber, number.uint64Value > 0,
                  (current["type"] as? NSNumber)?.intValue == 0,
                  let name = row["Display Identifier"] as? String else { continue }
            let screens: Set<CGDirectDisplayID>
            if !separateSpaces || name == "Main" { screens = Set(displays.values) }
            else if let display = displays[name] { screens = [display] }
            else { continue }
            result[number.uint64Value, default: []].formUnion(screens)
        }
        return result
    }
}
