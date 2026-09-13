import Cocoa
import Darwin

struct FrostedRestoreDragHeaderNode {
    let role: String
    let subrole: String?
    let frame: CGRect
    let pid: pid_t
    let actions: Set<String>
    let isExpectedWindow: Bool
    var childCount: Int? = nil
    var childFrames: [CGRect]? = nil
}

/// A bounded snapshot of only the window's top-level chrome. Opaque content and
/// controls retain their bounds but are never traversed for admission candidates.
struct FrostedRestoreHeaderLayout {
    let role: String
    let frame: CGRect
    var children: [FrostedRestoreHeaderLayout]? = nil
    var actions: Set<String>? = []
}

/// Legacy header classification retained with its existing regression fixtures.
/// Production restore admission now uses native movement in SnappingManager.
enum FrostedRestoreDragRules {
    static func accessibilityFrame(position: CGPoint, size: CGSize, allowEmpty: Bool = false) -> CGRect? {
        guard [position.x, position.y, size.width, size.height].allSatisfy({ $0.isFinite }),
              size.width >= 0, size.height >= 0,
              allowEmpty || (size.width > 0 && size.height > 0) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func verifiedRegions(probes: [CGPoint], inspect: (CGPoint) -> CGRect?) -> [CGRect] {
        // Retain each independently verified region. A tiny patch under the old
        // pointer must not displace a safe title or another proven blank region.
        // Read each live AX probe once: its result can disappear during a Space change.
        var regions: [CGRect] = []
        for point in probes {
            if let region = inspect(point), !regions.contains(region) { regions.append(region) }
        }
        return regions
    }

    static let handoffMarker: Int64 = 0x52454354454E4444
    static let replayMarker: Int64 = 0x5245435444524147
    static let maximumCacheAge: TimeInterval = 0.25
    static let validationDeadline: TimeInterval = 0.075
    static let dragThreshold: CGFloat = 3
    static let maximumHeaderNodes = 9

    /// Header groups and native toolbars share the same structural proof in every app.
    /// Interactive content ancestors never qualify as window chrome.
    static func isTitlebarBackground(nodes: [FrostedRestoreDragHeaderNode],
                                          windowPID: pid_t, windowFrame: CGRect, point: CGPoint) -> Bool {
        guard nodes.count >= 2, nodes.count <= maximumHeaderNodes,
              let window = nodes.last, window.isExpectedWindow, window.role == kAXWindowRole,
              window.subrole == kAXStandardWindowSubrole, framesMatch(window.frame, windowFrame),
              nodes.allSatisfy({ $0.pid == windowPID }),
              nodes.dropLast().allSatisfy({ !$0.isExpectedWindow }) else { return false }
        guard isHeaderContainer(nodes[0], windowFrame: windowFrame, point: point),
              nodes[0].childCount == 0 || verifiedHeaderGap(node: nodes[0], point: point) != nil else { return false }
        return nodes.dropFirst().dropLast().enumerated().allSatisfy { index, node in
            let enclosesChild = contains(node.frame, nodes[index].frame)
            let header = isHeaderContainer(node, windowFrame: windowFrame, point: point)
            let wrapper = node.role == kAXGroupRole && (node.subrole ?? "").isEmpty
                && framesMatch(node.frame, windowFrame) && node.actions.isSubset(of: [kAXShowMenuAction])
            return enclosesChild && (header || wrapper)
        }
    }

    /// Cache only the horizontal gap left after excluding every direct child.
    /// Missing geometry is not evidence that a control is absent.
    static func verifiedHeaderGap(node: FrostedRestoreDragHeaderNode, point: CGPoint) -> CGRect? {
        guard let count = node.childCount, count > 0, count <= 32,
              let children = node.childFrames, children.count == count,
              node.frame.contains(point) else { return nil }
        var left = node.frame.minX, right = node.frame.maxX
        for child in children {
            guard !child.isNull, !child.isEmpty, !child.isInfinite,
                  [child.minX, child.minY, child.width, child.height].allSatisfy({ $0.isFinite }) else { return nil }
            // Exclude its whole horizontal footprint even if a control is inset vertically.
            if child.maxX <= point.x { left = max(left, child.maxX) }
            else if child.minX > point.x { right = min(right, child.minX) }
            else { return nil }
        }
        let gap = CGRect(x: left, y: node.frame.minY, width: right - left, height: node.frame.height)
        return gap.width > 0 && gap.contains(point) ? gap : nil
    }

    static func isHeaderContainer(_ node: FrostedRestoreDragHeaderNode, windowFrame: CGRect, point: CGPoint) -> Bool {
        [kAXGroupRole, kAXToolbarRole, kAXTabGroupRole].contains(node.role) && (node.subrole ?? "").isEmpty && node.actions.isEmpty
            && (node.role != kAXTabGroupRole || (node.childCount ?? 0) > 0)
            && node.frame.height >= 12 && node.frame.height <= 88 && node.frame.width >= 4
            && abs(node.frame.minY - windowFrame.minY) <= 1
            && contains(windowFrame, node.frame) && node.frame.contains(point)
    }

    private static func framesMatch(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 1 && abs(first.minY - second.minY) <= 1
            && abs(first.width - second.width) <= 1 && abs(first.height - second.height) <= 1
    }

    private static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.minX <= inner.minX + 1 && outer.minY <= inner.minY + 1
            && outer.maxX >= inner.maxX - 1 && outer.maxY >= inner.maxY - 1
    }

    /// WindowServer reports the hardware cursor as a window at the pointer.
    /// Exclude that specific system surface; app panels at any level still occlude.
    static func isInputTransparentFrostSurface(windowID: CGWindowID, ownerPID: pid_t, level: Int,
                                               registered: [CGWindowID: pid_t]) -> Bool {
        registered[windowID] == ownerPID && level == BlurPreviewStyle.movingWindowLevel.rawValue
    }

    static func isSystemCursorSurface(level: Int, ownerName: String?, executablePath: String?) -> Bool {
        guard level == Int(CGWindowLevelForKey(.cursorWindow)), ownerName == "Window Server" else { return false }
        guard let executablePath else { return true }
        return executablePath == "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer"
            || executablePath == "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"
    }

    /// The Dock can publish a display-sized surface whose bounds cover ordinary
    /// windows even where input passes through. Require an exact system identity,
    /// display bounds, and a live AX hit on our window; real Dock controls still block.
    static func isClickThroughDockSurface(level: Int, ownerName: String?, executablePath: String?,
                                         bounds: CGRect, displayBounds: [CGRect], hitMatchesWindow: Bool) -> Bool {
        level == Int(CGWindowLevelForKey(.dockWindow)) && ownerName == "Dock"
            && executablePath == "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
            && displayBounds.contains(bounds) && hitMatchesWindow
    }

    static func verifiedHeaderRegion(at point: CGPoint, band: CGRect, blankFrame: CGRect? = nil) -> CGRect? {
        guard band.contains(point) else { return nil }
        // A proven empty header group is reusable across its blank area. For
        // AXWindow/title hits, nearby controls must not inherit the sampled point.
        let region = (blankFrame ?? CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).intersection(band)
        return !region.isEmpty && !region.isNull && region.contains(point) ? region : nil
    }

    static func verifiedTitleRegion(at point: CGPoint, band: CGRect, titleFrame: CGRect,
                                    role: String?, actions: [String]?, childCount: Int?) -> CGRect? {
        guard role == kAXStaticTextRole, actions?.isEmpty == true, childCount == 0 else { return nil }
        return verifiedHeaderRegion(at: point, band: band.intersection(titleFrame), blankFrame: titleFrame)
    }

    static func uncoveredHeaderRegions(container: CGRect, children: [CGRect], band: CGRect) -> [CGRect] {
        let area = container.intersection(band)
        guard !area.isNull, !area.isEmpty else { return [] }
        var regions = [area]
        for child in children {
            guard !child.isNull, !child.isInfinite,
                  [child.minX, child.minY, child.width, child.height].allSatisfy({ $0.isFinite }) else { return [] }
            regions = regions.flatMap { region -> [CGRect] in
                let cut = region.intersection(child)
                guard !cut.isNull, !cut.isEmpty else { return [region] }
                return [CGRect(x: region.minX, y: region.minY, width: region.width, height: cut.minY - region.minY),
                        CGRect(x: region.minX, y: cut.maxY, width: region.width, height: region.maxY - cut.maxY),
                        CGRect(x: region.minX, y: cut.minY, width: cut.minX - region.minX, height: cut.height),
                        CGRect(x: cut.maxX, y: cut.minY, width: region.maxX - cut.maxX, height: cut.height)]
                    .filter { $0.width >= 4 && $0.height >= 4 }
            }
            guard regions.count <= 64 else { return [] }
        }
        return regions
    }

    /// All regions are established from complete chrome structure. Overlapping
    /// siblings subtract their control footprints, including tab labels and title
    /// buttons. Only complete, inert chrome may be traversed to find those controls.
    static func windowBackgroundRegions(layout: FrostedRestoreHeaderLayout, band: CGRect) -> [CGRect] {
        guard layout.role == kAXWindowRole else { return [] }
        func blockers(_ node: FrostedRestoreHeaderLayout, depth: Int) -> [CGRect] {
            guard depth < maximumHeaderNodes, let children = node.children, children.count <= 32,
                  let actions = node.actions else { return [node.frame] }
            let wrapper = node.role == kAXGroupRole && framesMatch(node.frame, layout.frame)
                && actions.isSubset(of: [kAXShowMenuAction])
            let header = [kAXGroupRole, kAXToolbarRole, kAXTabGroupRole].contains(node.role)
                && node.frame.height >= 12 && node.frame.height <= 88
                && abs(node.frame.minY - layout.frame.minY) <= 1 && contains(layout.frame, node.frame)
                && (actions.isEmpty || (node.role == kAXToolbarRole && actions.isSubset(of: [kAXShowMenuAction])))
                && (node.role != kAXTabGroupRole || !children.isEmpty)
            guard wrapper || header else { return [node.frame] }
            return children.flatMap { blockers($0, depth: depth + 1) }
        }
        func visit(_ node: FrostedRestoreHeaderLayout, depth: Int) -> [CGRect] {
            guard depth < maximumHeaderNodes, let children = node.children, children.count <= 32,
                  let actions = node.actions else { return [] }
            let root = depth == 0 && node.role == kAXWindowRole
            let wrapper = node.role == kAXGroupRole && framesMatch(node.frame, layout.frame)
                && actions.isSubset(of: [kAXShowMenuAction])
            let header = [kAXGroupRole, kAXToolbarRole, kAXTabGroupRole].contains(node.role)
                && node.frame.height >= 12 && node.frame.height <= 88
                && abs(node.frame.minY - layout.frame.minY) <= 1 && contains(layout.frame, node.frame)
                && (actions.isEmpty || (node.role == kAXToolbarRole && actions.isSubset(of: [kAXShowMenuAction])))
                && (node.role != kAXTabGroupRole || !children.isEmpty)
            guard root || wrapper || header else { return [] }
            if !root && !header && children.isEmpty { return [] }
            var regions = uncoveredHeaderRegions(container: node.frame, children: children.map(\.frame), band: band)
            for (index, child) in children.enumerated() where child.frame.intersects(band) {
                let siblingControls = children.enumerated().filter { $0.offset != index }.flatMap { blockers($0.element, depth: depth + 1) }
                for region in visit(child, depth: depth + 1) {
                    regions += uncoveredHeaderRegions(container: region, children: siblingControls, band: band)
                }
                guard regions.count <= 256 else { return [] }
            }
            return regions
        }
        return visit(layout, depth: 0)
    }

    static func isWindowBackgroundProxy(nodes: [FrostedRestoreDragHeaderNode], windowPID: pid_t, windowFrame: CGRect) -> Bool {
        guard nodes.count >= 2, nodes.count <= maximumHeaderNodes, let root = nodes.last,
              root.isExpectedWindow, root.role == kAXWindowRole, root.subrole == kAXStandardWindowSubrole,
              nodes.allSatisfy({ $0.pid == windowPID && framesMatch($0.frame, windowFrame) }),
              nodes[0].childCount == 0, nodes[0].actions.isEmpty else { return false }
        return nodes.dropLast().allSatisfy {
            !$0.isExpectedWindow && $0.role == kAXGroupRole && ($0.subrole ?? "").isEmpty
                && $0.actions.isSubset(of: [kAXShowMenuAction])
        }
    }

    static func headerProbePoints(pointer: CGPoint?, band: CGRect, titleFrame: CGRect?,
                                  layout: FrostedRestoreHeaderLayout? = nil) -> [CGPoint] {
        var points: [CGPoint] = []
        if let pointer, band.contains(pointer) { points.append(pointer) }
        if let titleFrame {
            let title = titleFrame.intersection(band)
            if !title.isNull && !title.isEmpty { points.append(CGPoint(x: title.midX, y: title.midY)) }
        }
        let areas = layout.map { windowBackgroundRegions(layout: $0, band: band) } ?? []
        for area in areas.sorted(by: { $0.width * $0.height > $1.width * $1.height }).prefix(12) {
            let point = CGPoint(x: area.midX, y: area.midY)
            if !points.contains(point) { points.append(point) }
        }
        return points
    }

    static func canCapture(clickCount: Int64, flags: CGEventFlags, point: CGPoint,
                           safeRegions: [CGRect], cachedAt: TimeInterval, now: TimeInterval) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        return clickCount == 1 && flags.intersection(modifiers).isEmpty
            && now >= cachedAt && now - cachedAt <= maximumCacheAge && safeRegions.contains { $0.contains(point) }
    }

    static func crossedThreshold(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= dragThreshold
    }

    static func destination(original: CGRect, restoreSize: CGSize, mouseDown: CGPoint, cursor: CGPoint,
                            screenFrame: CGRect? = nil) -> CGRect {
        var restored = DragRestorePlacement.frame(from: original, size: restoreSize, cursor: mouseDown)
        if let screenFrame, screenFrame.contains(original) {
            // A half-width snap can restore to a wider window. Start that size
            // within its source display, then follow the pointer without clamping.
            if restored.width <= screenFrame.width {
                restored.origin.x = min(max(restored.minX, screenFrame.minX), screenFrame.maxX - restored.width)
            }
            if restored.height <= screenFrame.height {
                restored.origin.y = min(max(restored.minY, screenFrame.minY), screenFrame.maxY - restored.height)
            }
        }
        return restored.offsetBy(dx: cursor.x - mouseDown.x, dy: cursor.y - mouseDown.y)
    }
}

/// Replay is a one-way decision: after an animation accepts the gesture, a later
/// failure recovers geometry and consumes the rest of the gesture, never injects it.
struct FrostedRestoreDragReplayState {
    private(set) var owned = false
    private(set) var decided = false
    mutating func acceptOwnership() { owned = true; decided = true }
    mutating func takeReplay(identityUnchanged: Bool) -> Bool {
        guard !decided else { return false }
        decided = true
        return !owned && identityUnchanged
    }
}

/// AppKit can run nested main-loop callbacks while the first drag creates its
/// overlay. Keep later input queued until that first callback has its token.
final class FrostedRestoreDragEventDrain {
    private var pending: [CGEvent] = []
    private(set) var processing = false

    func enqueue(_ events: [CGEvent], consume: (CGEvent) -> Bool) {
        pending.append(contentsOf: events)
        guard !processing else { return }
        processing = true
        defer { processing = false; pending.removeAll(keepingCapacity: true) }
        var index = 0
        while index < pending.count {
            let event = pending[index]
            index += 1
            guard consume(event) else { return }
        }
    }
}

/// A state source must first prove that it tracked this gesture's held button.
/// A permanently false synthetic source cannot by itself cancel a held drag.
struct FrostedRestoreDragReleaseWatch {
    private(set) var sawHIDDown = false
    private(set) var sawSessionDown = false
    private var firstReleasedAt: TimeInterval?

    mutating func shouldRecover(hidDown: Bool, sessionDown: Bool, now: TimeInterval) -> Bool {
        sawHIDDown = sawHIDDown || hidDown
        sawSessionDown = sawSessionDown || sessionDown
        if hidDown || sessionDown {
            firstReleasedAt = nil
            return false
        }
        guard sawHIDDown || sawSessionDown else { return false }
        guard let firstReleasedAt else {
            self.firstReleasedAt = now
            return false
        }
        return now - firstReleasedAt >= 0.05
    }
}

/// The target can still apply events queued before the tap took ownership.
/// Admit parking only after both frame sources agree and stop changing.
struct FrostedNativeDragSettlement {
    enum Decision: Equatable { case waiting, ready(CGRect), timedOut }
    private let deadline: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(startedAt: TimeInterval, timeout: TimeInterval = 0.15) { deadline = startedAt + timeout }

    mutating func observe(ax: CGRect?, server: CGRect?, at now: TimeInterval) -> Decision {
        guard let ax, let server, WindowRecoveryGeometry.valid(ax), WindowRecoveryGeometry.valid(server),
              WindowRecoveryGeometry.near(ax, server, tolerance: 1) else {
            previous = nil; stableSince = nil
            return now < deadline ? .waiting : .timedOut
        }
        // A slow AX read or a delayed main-queue callback can cross the deadline.
        // Still accept the current confirmation of a previously matching frame;
        // an overdue new, missing, or changed frame must not extend the wait.
        if previous == server, let stableSince, now - stableSince >= 1.0 / 60 { return .ready(server) }
        guard now < deadline else { return .timedOut }
        if previous != server { previous = server; stableSince = now }
        return .waiting
    }
}

/// A native drag can stop in WindowServer while the app retains an older AX
/// position. Reassert only that already displayed position once both readings
/// have stopped changing; parking still requires their subsequent agreement.
struct FrostedNativeDragAlignment {
    private var previousAX: CGRect?
    private var previousServer: CGRect?
    private var stableSince: TimeInterval?
    private var attempted = false

    mutating func positionToReassert(ax: CGRect?, server: CGRect?, expectedSize: CGSize,
                                     at now: TimeInterval) -> CGPoint? {
        guard !attempted else { return nil }
        guard let ax, let server, WindowRecoveryGeometry.valid(ax), WindowRecoveryGeometry.valid(server),
              ax.size == expectedSize, server.size == expectedSize,
              !WindowRecoveryGeometry.near(ax, server, tolerance: 1) else {
            previousAX = nil; previousServer = nil; stableSince = nil
            return nil
        }
        if previousAX != ax || previousServer != server {
            previousAX = ax; previousServer = server; stableSince = now
        }
        guard let stableSince, now - stableSince >= 1.0 / 30 else { return nil }
        attempted = true
        return server.origin
    }
}

struct FrostedRestoreDragCandidate {
    let element: AccessibilityElement
    let rawWindow: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID
    let original: CGRect
    let restoreSize: CGSize
    let safeRegions: [CGRect]
    let cachedAt: TimeInterval
    var historyFrame: CGRect? = nil
}

final class FrostedRestoreDragController {
    private final class Gesture {
        let id = UUID()
        var candidate: FrostedRestoreDragCandidate
        var down: CGPoint
        var events: [CGEvent]
        var released = false
        var cancelled = false
        var releaseEvent: CGEvent?
        var releaseReceivedAt: TimeInterval?
        var discarding = false
        // The remaining properties are used only on the main queue.
        let drain = FrostedRestoreDragEventDrain()
        var validated = false
        var ordinaryFallback = false
        var token: UUID?
        var cursor: CGPoint
        var releaseHandled = false
        var releaseWatch = FrostedRestoreDragReleaseWatch()
        var processedDragCount = 0
        var lastDragTraceAt = -TimeInterval.infinity
        var nativeAlignment = FrostedNativeDragAlignment()

        init(candidate: FrostedRestoreDragCandidate, event: CGEvent) {
            self.candidate = candidate
            down = event.location
            cursor = event.location
            events = [event]
        }
    }

    private weak var owner: SnappingManager?
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var thread: RunLoopThread?
    private var releaseTimer: Timer?
    private let scheduler: WindowFrostScheduler
    private var gesture: Gesture?
    private var nativeDown: CGEvent?
    private var nativeUp: CGEvent?
    private var nativeUpReceivedAt: TimeInterval?
    private var nativeCancelled = false
    private var latestMouseDownTimestamp: CGEventTimestamp = 0
    private var swallowedEscape = false
    private var notificationTokens: [NSObjectProtocol] = []
    private static let tracesInput = !(ProcessInfo.processInfo.environment["RECTANGLE_FROST_TRACE_PATH"] ?? "").isEmpty

    init(owner: SnappingManager, scheduler: WindowFrostScheduler = .main) {
        self.owner = owner
        self.scheduler = scheduler
        for name in [Notification.Name.windowAnimationPreferencesChanged, .configImported] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.invalidateGesture()
            })
        }
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.willTerminateNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.invalidateGesture(clearSurfaces: true)
            })
        }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.invalidateGesture(clearSurfaces: name == NSWorkspace.activeSpaceDidChangeNotification)
            })
        }
    }

    deinit {
        stop()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: frostedRestoreDragTap,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = port
        let thread = RunLoopThread(mode: .default, qualityOfService: .userInteractive, start: true)
        thread.runLoop?.add(port, forMode: .default)
        self.thread = thread
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in self?.checkForLostRelease() }
        releaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        checkForLostRelease()
    }

    func stop() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        invalidateGesture()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            thread?.runLoop?.remove(tap, forMode: .default)
        }
        thread?.cancel()
        thread = nil
        tap = nil
    }

    /// Called on the tap thread. Only copies event data and reads locked memory;
    /// no Accessibility, WindowServer queries, AppKit, or synchronous dispatch.
    func filter(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.invalidateGesture()
                if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return false
        }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        if marker == FrostedRestoreDragRules.handoffMarker { return false }
        lock.lock()
        if type == .keyUp {
            let consume = swallowedEscape && event.getIntegerValueField(.keyboardEventKeycode) == 53
            if consume { swallowedEscape = false }
            lock.unlock()
            return consume
        }
        if let gesture {
            if type == .keyDown {
                let escape = event.getIntegerValueField(.keyboardEventKeycode) == 53
                if escape { swallowedEscape = true; gesture.cancelled = true }
                lock.unlock()
                if escape {
                    DispatchQueue.main.async { [weak self, weak gesture] in
                        guard let self, let gesture, self.isCurrent(gesture) else { return }
                        // Without a token the native window is still settling.
                        // Its queued movement must finish before restoring it.
                        if gesture.token != nil || gesture.ordinaryFallback { self.invalidateGesture() }
                    }
                }
                return escape
            }
            if type == .leftMouseUp {
                gesture.released = true
                gesture.releaseEvent = event.copy()
                gesture.releaseReceivedAt = ProcessInfo.processInfo.systemUptime
            }
            if gesture.discarding {
                let finished = gesture.released
                if finished { self.gesture = nil }
                lock.unlock()
                // Cancellation drains the physical release without sending it
                // to an unrelated window underneath the cursor.
                return true
            }
            if let copy = event.copy() {
                gesture.events.append(copy)
            }
            lock.unlock()
            DispatchQueue.main.async { [weak self, weak gesture] in
                if let gesture {
                    if type == .leftMouseUp {
                        WindowFrostDiagnostics.event("owned-drag-received-up", fields: ["gesture": gesture.id.uuidString,
                                                                                       "windowID": gesture.candidate.windowID])
                    }
                    self?.drain(gesture)
                }
            }
            return true
        }
        if type == .leftMouseDown {
            nativeDown = event.copy()
            nativeUp = nil
            nativeUpReceivedAt = nil
            nativeCancelled = false
            latestMouseDownTimestamp = event.timestamp
        }
        if type == .keyDown, nativeDown != nil, nativeUp == nil, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            nativeCancelled = true
        }
        if type == .leftMouseUp {
            nativeUp = event.copy()
            nativeUpReceivedAt = ProcessInfo.processInfo.systemUptime
        }
        lock.unlock()
        return false
    }

    /// Called only after SnappingManager observed actual movement of the original
    /// window. No titlebar hit testing or speculative mouse-down interception.
    func beginNativeRestore(element target: AccessibilityElement, windowID: CGWindowID,
                            source: CGRect, historyFrame: CGRect, restoreSize: CGSize,
                            referenceCursor: CGPoint, event: CGEvent) -> Bool {
        guard let tap, CGEvent.tapIsEnabled(tap: tap),
              let pid = target.pid,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let raw = Self.element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute),
              AccessibilityElement(raw) == target,
              let sourceEvents = CGEventSource(stateID: .privateState),
              let end = CGEvent(mouseEventSource: sourceEvents, mouseType: .leftMouseUp,
                                mouseCursorPosition: event.location, mouseButton: .left) else { return false }
        lock.lock()
        guard gesture == nil, let down = nativeDown, down.timestamp <= event.timestamp else {
            lock.unlock(); return false
        }
        let candidate = FrostedRestoreDragCandidate(element: target, rawWindow: raw, pid: pid,
            windowID: windowID, original: source, restoreSize: restoreSize, safeRegions: [],
            cachedAt: scheduler.now(), historyFrame: historyFrame)
        guard let start = down.copy() else { lock.unlock(); return false }
        start.location = referenceCursor
        let active = Gesture(candidate: candidate, event: start)
        active.cancelled = nativeCancelled
        active.cursor = nativeUp?.location ?? event.location
        active.events = []
        let alreadyReleased = nativeUp != nil
        active.released = alreadyReleased
        active.releaseEvent = nativeUp
        active.releaseReceivedAt = nativeUpReceivedAt
        self.gesture = active
        nativeDown = nil
        nativeUp = nil
        nativeUpReceivedAt = nil
        lock.unlock()

        // The original down is already routed to this foreground window.
        // End its native drag through WindowServer too: posting only to the PID
        // leaves the session button table down when the physical up is consumed.
        // Our marker bypasses this tap and the ordinary snapping monitor.
        end.flags = event.flags
        end.setIntegerValueField(.mouseEventNumber, value: down.getIntegerValueField(.mouseEventNumber))
        end.setIntegerValueField(.mouseEventClickState, value: down.getIntegerValueField(.mouseEventClickState))
        end.setDoubleValueField(.mouseEventPressure, value: 0)
        end.setIntegerValueField(.eventSourceUserData, value: FrostedRestoreDragRules.handoffMarker)
        if !alreadyReleased { end.post(tap: .cgSessionEventTap) }
        WindowFrostDiagnostics.event("native-drag-handoff", fields: ["windowID": windowID,
            "source": [source.minX, source.minY, source.width, source.height]])
        // Native AX readback can trail WindowServer by several hundred ms.
        // Keep ownership until it settles; ordinary placement during that gap
        // can be overwritten by the target's queued native drag.
        settleNativeHandoff(active, settlement: FrostedNativeDragSettlement(startedAt: scheduler.now(), timeout: 0.5))
        return true
    }

    var ownsGesture: Bool {
        lock.lock(); defer { lock.unlock() }
        return gesture != nil
    }

    var nativeDragCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return nativeCancelled
    }

    func hasMouseDown(after timestamp: CGEventTimestamp) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return latestMouseDownTimestamp > timestamp
    }

    func hasHeldNativeDrag(at timestamp: CGEventTimestamp) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let nativeDown else { return false }
        return nativeDown.timestamp <= timestamp && nativeUp == nil && !nativeCancelled
    }

    private func settleNativeHandoff(_ active: Gesture, settlement: FrostedNativeDragSettlement) {
        guard isCurrent(active) else { return }
        let old = active.candidate
        var settlement = settlement
        let ax = old.element.frame
        let server = WindowUtil.getWindowFrame(id: old.windowID)
        // AX can block while the target is busy. A newly returned frame was
        // observed now, not before that read; never backdate its stable interval.
        let now = scheduler.now()
        if WindowFrostDiagnostics.enabled {
            WindowFrostDiagnostics.event("native-handoff-sample", fields: ["windowID": old.windowID,
                "ax": [ax.minX, ax.minY, ax.width, ax.height],
                "server": server.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? []])
        }
        switch settlement.observe(ax: ax, server: server, at: now) {
        case .ready(let frame):
            if cancelPendingHandoff(active) { return }
            active.down.x += frame.minX - old.original.minX
            active.down.y += frame.minY - old.original.minY
            active.candidate = FrostedRestoreDragCandidate(element: old.element, rawWindow: old.rawWindow,
                pid: old.pid, windowID: old.windowID, original: frame, restoreSize: old.restoreSize,
                safeRegions: [], cachedAt: now, historyFrame: old.historyFrame)
            startNativePreview(active)
        case .timedOut:
            if cancelPendingHandoff(active) { return }
            WindowFrostDiagnostics.event("native-handoff-timeout", fields: ["windowID": old.windowID])
            startOrdinaryFallback(active)
        case .waiting:
            // Escape also waits for the native mouse-up to settle. Writing the
            // original frame here races the target's remaining drag events.
            if let position = active.nativeAlignment.positionToReassert(ax: ax, server: server,
                    expectedSize: old.original.size, at: now),
               NSWorkspace.shared.frontmostApplication?.processIdentifier == old.pid,
               Self.element(AXUIElementCreateApplication(old.pid), kAXFocusedWindowAttribute)
                    .map({ CFEqual($0, old.rawWindow) }) == true,
               old.element.getWindowId() == old.windowID {
                let result = old.element.writeAnimationPosition(position)
                WindowFrostDiagnostics.event("native-handoff-align-position", fields: ["windowID": old.windowID,
                    "position": [position.x, position.y], "result": result.rawValue])
            }
            scheduler.after(1.0 / 120) { [weak self, weak active] in
                guard let self, let active else { return }
                self.settleNativeHandoff(active, settlement: settlement)
            }
        }
    }

    private func startNativePreview(_ active: Gesture) {
        if cancelPendingHandoff(active) { return }
        let candidate = active.candidate
        lock.lock()
        let cursor = active.events.last?.location ?? active.cursor
        lock.unlock()
        WindowFrostDiagnostics.event("native-handoff-settled", fields: ["windowID": candidate.windowID,
            "source": [candidate.original.minX, candidate.original.minY, candidate.original.width, candidate.original.height]])
        let token = owner?.beginOwnedRestore(candidate: candidate, mouseDown: active.down, cursor: cursor) { [weak self, weak active] in
            guard let self, let active, self.isCurrent(active) else { return }
            self.discard(active)
        }
        guard isCurrent(active) else {
            if let token { WindowAnimator.shared.cancelOwnedDrag(token) }
            return
        }
        guard let token else {
            startOrdinaryFallback(active)
            return
        }
        active.token = token
        lock.lock()
        let cancelled = active.cancelled
        lock.unlock()
        if cancelled { invalidateGesture(); return }
        active.validated = true
        _ = observeButtonState(active)
        WindowFrostDiagnostics.event("owned-drag-accepted", fields: ["windowID": candidate.windowID,
            "trigger": "native-movement", "token": token.uuidString])
        drain(active)
    }

    private func cancelPendingHandoff(_ active: Gesture) -> Bool {
        lock.lock()
        let cancelled = active.cancelled
        lock.unlock()
        guard cancelled else { return false }
        let candidate = active.candidate
        candidate.element.setFrame(candidate.historyFrame ?? candidate.original)
        WindowFrostDiagnostics.event("native-handoff-cancelled", fields: ["windowID": candidate.windowID])
        owner?.cancelOwnedRestore()
        discard(active)
        return true
    }

    private func ordinaryDestination(_ active: Gesture, cursor: CGPoint) -> CGRect {
        let candidate = active.candidate
        return FrostedRestoreDragRules.destination(original: candidate.original, restoreSize: candidate.restoreSize,
            mouseDown: active.down, cursor: cursor,
            screenFrame: NSScreen.screens.map { $0.frame.screenFlipped }.first { $0.contains(candidate.original) })
    }

    private func startOrdinaryFallback(_ active: Gesture) {
        guard isCurrent(active) else { return }
        // Ownership has already ended the target's native drag. Keep following
        // and retain the exact mouse-up so a failed preview cannot lose its snap.
        active.ordinaryFallback = true
        active.validated = true
        _ = observeButtonState(active)
        active.candidate.element.setFrame(ordinaryDestination(active, cursor: active.cursor))
        drain(active)
    }

    private func drain(_ gesture: Gesture) {
        guard isCurrent(gesture), gesture.validated else { return }
        lock.lock()
        let events = gesture.events
        gesture.events.removeAll(keepingCapacity: true)
        lock.unlock()
        gesture.drain.enqueue(events) { event in
            guard self.isCurrent(gesture) else { return false }
            gesture.cursor = event.location
            switch event.type {
            case .leftMouseDragged:
                if gesture.ordinaryFallback {
                    gesture.candidate.element.setFrame(self.ordinaryDestination(gesture, cursor: event.location))
                }
                if let token = gesture.token {
                    if Self.tracesInput {
                        gesture.processedDragCount += 1
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - gesture.lastDragTraceAt >= 0.10 {
                            gesture.lastDragTraceAt = now
                            WindowFrostDiagnostics.event("owned-drag-processed", fields: [
                                "gesture": gesture.id.uuidString, "token": token.uuidString,
                                "windowID": gesture.candidate.windowID,
                                "processedDragCount": gesture.processedDragCount,
                                "eventTimestamp": event.timestamp,
                                "cursor": [gesture.cursor.x, gesture.cursor.y]
                            ])
                        }
                    }
                    self.owner?.updateOwnedRestore(token: token, candidate: gesture.candidate, mouseDown: gesture.down, cursor: gesture.cursor, event: event)
                }
            case .leftMouseUp:
                if gesture.token != nil || gesture.ordinaryFallback {
                    self.release(gesture, event: event)
                }
                return false
            default: break
            }
            return true
        }
        guard !gesture.drain.processing else { return }
        // The tap may have received mouse-up while begin/update was inside
        // AppKit, before its queued drain ran. Reconcile that exact copied event.
        lock.lock()
        let releaseEvent = gesture.releaseEvent
        lock.unlock()
        if let releaseEvent, gesture.token != nil || gesture.ordinaryFallback { release(gesture, event: releaseEvent) }
    }

    private func release(_ gesture: Gesture, event: CGEvent) {
        guard isCurrent(gesture), !gesture.releaseHandled else { return }
        lock.lock()
        let cancelled = gesture.cancelled
        let receivedAt = gesture.releaseReceivedAt
        lock.unlock()
        if cancelled { invalidateGesture(); return }
        if gesture.ordinaryFallback {
            gesture.releaseHandled = true
            owner?.finishNativeRestore(element: gesture.candidate.element, windowID: gesture.candidate.windowID,
                frame: ordinaryDestination(gesture, cursor: event.location), release: event)
            owner?.cancelOwnedRestore()
            discard(gesture)
            return
        }
        guard let token = gesture.token else { return }
        gesture.releaseHandled = true
        WindowFrostDiagnostics.event("owned-drag-release", fields: ["gesture": gesture.id.uuidString, "token": token.uuidString,
                                                                    "windowID": gesture.candidate.windowID,
                                                                    "eventTimestamp": event.timestamp,
                                                                    "receivedUptime": receivedAt ?? 0])
        owner?.endOwnedRestore(token: token, candidate: gesture.candidate, mouseDown: gesture.down,
                               cursor: event.location, event: event)
        discard(gesture)
    }

    private func observeButtonState(_ gesture: Gesture) -> Bool {
        gesture.releaseWatch.shouldRecover(hidDown: CGEventSource.buttonState(.hidSystemState, button: .left),
                                            sessionDown: CGEventSource.buttonState(.combinedSessionState, button: .left),
                                            now: ProcessInfo.processInfo.systemUptime)
    }

    private func checkForLostRelease() {
        lock.lock()
        let active = gesture
        let hasRelease = active?.releaseEvent != nil
        lock.unlock()
        guard let active, isCurrent(active), active.token != nil || active.ordinaryFallback,
              !active.drain.processing else { return }
        if hasRelease {
            drain(active)
            return
        }
        guard observeButtonState(active) else { return }
        // Mouse-up may arrive on the tap thread while the state tables are read.
        // Prefer that exact event until the recovery decision is committed.
        lock.lock()
        guard gesture === active, !active.discarding else { lock.unlock(); return }
        if active.releaseEvent != nil {
            lock.unlock()
            drain(active)
            return
        }
        active.released = true
        lock.unlock()
        WindowFrostDiagnostics.event("owned-drag-release-lost", fields: ["gesture": active.id.uuidString,
                                                                         "windowID": active.candidate.windowID])
        // Both source tables confirm that the original button sequence ended.
        // Recover the original frame; do not invent a release target or replay.
        invalidateGesture()
    }

    private func isCurrent(_ gesture: Gesture) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return self.gesture === gesture && !gesture.discarding
    }

    private func discard(_ gesture: Gesture) {
        lock.lock()
        if self.gesture === gesture {
            gesture.events.removeAll()
            if gesture.released { self.gesture = nil } else { gesture.discarding = true }
        }
        lock.unlock()
        checkForLostRelease()
    }

    private func invalidateGesture(clearSurfaces: Bool = false) {
        if clearSurfaces { WindowFrostOverlay.clearIdleSurfaces() }
        lock.lock()
        let active = gesture
        nativeDown = nil
        nativeUp = nil
        nativeUpReceivedAt = nil
        lock.unlock()
        if let active {
            if let token = active.token { WindowAnimator.shared.cancelOwnedDrag(token) }
            if active.ordinaryFallback { active.candidate.element.setFrame(active.candidate.historyFrame ?? active.candidate.original) }
            owner?.cancelOwnedRestore()
            discard(active)

        }
    }

    private static func element(_ object: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(object, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

}

private func frostedRestoreDragTap(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                   refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<FrostedRestoreDragController>.fromOpaque(refcon).takeUnretainedValue()
    return controller.filter(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
