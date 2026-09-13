import Cocoa

/// Pure input ownership policy. Coordinates use CG's top-left display coordinate space.
struct WindowFrostInputPolicy {
    enum Input {
        case down(Int, CGPoint), dragged(Int), up(Int)
        case escapeDown, escapeUp
        case other
    }
    struct Decision: Equatable {
        var consume = false
        var cancel = false
        var previewDrag = false
    }
    var regions: [CGRect]
    var externallyOwnedLeftGesture: Bool
    let ignoresMouseInterruptions: Bool
    private(set) var swallowedButtons: Set<Int> = []
    private(set) var closing = false
    private var swallowedEscape = false
    private var cancelled = false
    private var previewLeftGesture = false
    var isDrained: Bool { swallowedButtons.isEmpty && !swallowedEscape }

    init(regions: [CGRect], externallyOwnedLeftGesture: Bool, ignoresMouseInterruptions: Bool = false) {
        self.regions = regions
        self.externallyOwnedLeftGesture = externallyOwnedLeftGesture
        self.ignoresMouseInterruptions = ignoresMouseInterruptions
    }

    mutating func close() { closing = true }

    mutating func process(_ input: Input, offerPreviewDrag: Bool = false) -> Decision {
        switch input {
        case .dragged(let button):
            return Decision(consume: swallowedButtons.contains(button), previewDrag: button == 0 && previewLeftGesture)
        case .up(let button):
            if button == 0 && externallyOwnedLeftGesture {
                externallyOwnedLeftGesture = false
                return Decision()
            }
            let preview = button == 0 && previewLeftGesture
            if button == 0 { previewLeftGesture = false }
            return Decision(consume: swallowedButtons.remove(button) != nil, previewDrag: preview)
        case .escapeUp:
            let consume = swallowedEscape
            swallowedEscape = false
            return Decision(consume: consume)
        case .down(let button, let point):
            guard !closing else { return Decision() }
            if button == 0 && externallyOwnedLeftGesture { return Decision() }
            if ignoresMouseInterruptions {
                // Automatic frost completes under mouse input. Own only presses
                // on the protected window, and drain them even after it closes.
                let consume = regions.contains { $0.contains(point) }
                if consume { swallowedButtons.insert(button) }
                return Decision(consume: consume)
            }
            if button == 0 && offerPreviewDrag && !cancelled {
                previewLeftGesture = true
                swallowedButtons.insert(button)
                return Decision(consume: true, previewDrag: true)
            }
            let consume = regions.contains { $0.contains(point) }
            if consume { swallowedButtons.insert(button) }
            let cancel = !cancelled
            cancelled = true
            previewLeftGesture = false
            return Decision(consume: consume, cancel: cancel)
        case .escapeDown:
            guard !closing, !cancelled else { return Decision(consume: swallowedEscape) }
            swallowedEscape = true
            let cancel = !cancelled
            cancelled = true
            previewLeftGesture = false
            return Decision(consume: true, cancel: cancel)
        case .other:
            return Decision()
        }
    }
}

enum WindowFrostPreviewDragGeometry {
    /// Only previously verified header space is projected onto the cover. Keep
    /// title-bar height fixed; growing horizontally never expands toward tabs.
    static func regions(_ regions: [CGRect], source: CGRect, presented: CGRect) -> [CGRect] {
        guard source.width > 0, presented.width > 0 else { return [] }
        return regions.map { region in
            CGRect(x: presented.minX + (region.minX - source.minX) * presented.width / source.width,
                   y: presented.minY + region.minY - source.minY,
                   width: region.width * presented.width / source.width, height: region.height)
        }
    }
}

/// The intercepted pointer stream can reach the renderer before the parent has
/// adopted the drag. Keep that latest translation through the size-morph handoff.
struct WindowFrostPreviewPointer {
    let down: CGPoint
    private(set) var offset = CGPoint.zero
    private var crossedThreshold = false

    init(down: CGPoint) { self.down = down }

    mutating func update(_ point: CGPoint, isRelease: Bool = false) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        crossedThreshold = crossedThreshold || (!isRelease && FrostedRestoreDragRules.crossedThreshold(from: down, to: point))
        guard crossedThreshold else { return false }
        let next = CGPoint(x: point.x - down.x, y: point.y - down.y)
        guard next != offset else { return false }
        offset = next
        return true
    }

    func motionOrigin(presented: CGRect) -> CGRect {
        presented.offsetBy(dx: -offset.x, dy: -offset.y)
    }
}

/// Owns its run-loop lifetime until every swallowed mouse/key sequence is drained.
private final class WindowFrostInputTap {
    private let lock = NSLock()
    private var policy: WindowFrostInputPolicy
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var lost = false
    private var stopped = false
    private let cancel: () -> Void
    private let previewDrag: (CGEvent) -> Void
    private var previewRegions: [CGRect] = []

    init?(regions: [CGRect], externallyOwnedDrag: Bool, cancel: @escaping () -> Void,
          previewDrag: @escaping (CGEvent) -> Void) {
        policy = WindowFrostInputPolicy(regions: regions, externallyOwnedLeftGesture: externallyOwnedDrag,
                                       ignoresMouseInterruptions: !externallyOwnedDrag)
        self.cancel = cancel
        self.previewDrag = previewDrag
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: .defaultTap, eventsOfInterest: mask,
                               callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<WindowFrostInputTap>.fromOpaque(context).takeUnretainedValue().receive(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            if let tap { CFMachPortInvalidate(tap) }
            return nil
        }
        let ready = DispatchSemaphore(value: 0)
        // The block retains this owner, including after the visual overlay closes.
        DispatchQueue(label: "com.rectangle.frost-input", qos: .userInteractive).async { [self] in
            let loop = CFRunLoopGetCurrent()
            lock.lock()
            runLoop = loop
            lock.unlock()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        ready.wait()
        guard CGEvent.tapIsEnabled(tap: tap) else { close(); return nil }
    }

    func update(regions: [CGRect], previewRegions: [CGRect] = []) {
        lock.lock(); policy.regions = regions; self.previewRegions = previewRegions; lock.unlock()
    }

    func close() {
        lock.lock()
        policy.close()
        let shouldStop = policy.isDrained
        lock.unlock()
        if shouldStop { stop() }
    }

    private func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let loop = runLoop
        lock.unlock()
        if let loop {
            // Defer invalidation until any callback currently using the opaque context returns.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock(); let report = !lost; lost = true; lock.unlock()
            // Restore sequence draining while the main thread recovers the real window.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if report { DispatchQueue.main.async(execute: cancel) }
            return Unmanaged.passUnretained(event)
        }
        let input: WindowFrostInputPolicy.Input
        switch type {
        case .leftMouseDown: input = .down(0, event.location)
        case .rightMouseDown: input = .down(1, event.location)
        case .otherMouseDown: input = .down(Int(event.getIntegerValueField(.mouseEventButtonNumber)), event.location)
        case .leftMouseDragged: input = .dragged(0)
        case .rightMouseDragged: input = .dragged(1)
        case .otherMouseDragged: input = .dragged(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        case .leftMouseUp: input = .up(0)
        case .rightMouseUp: input = .up(1)
        case .otherMouseUp: input = .up(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        case .keyDown where event.getIntegerValueField(.keyboardEventKeycode) == 53: input = .escapeDown
        case .keyUp where event.getIntegerValueField(.keyboardEventKeycode) == 53: input = .escapeUp
        default: input = .other
        }
        lock.lock()
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        let offer = type == .leftMouseDown && event.getIntegerValueField(.mouseEventClickState) == 1
            && event.flags.intersection(modifiers).isEmpty && previewRegions.contains { $0.contains(event.location) }
        let decision = policy.process(input, offerPreviewDrag: offer)
        let shouldStop = policy.closing && policy.isDrained
        lock.unlock()
        if decision.cancel { DispatchQueue.main.async(execute: cancel) }
        if decision.previewDrag, let copy = event.copy() {
            DispatchQueue.main.async { [previewDrag] in previewDrag(copy) }
        }
        if shouldStop { stop() }
        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }
}

/// Callbacks belonging to one renderer connection; completion may synchronously start another.
final class WindowFrostRendererCallbacks {
    var waiters: [(Bool) -> Void] = []
    var receive: (([String: Any]) -> Void)?
    var disconnected: (() -> Void)?

    private let scheduler: WindowFrostScheduler
    private(set) var connectionID: UUID?
    private var ready = false

    init(scheduler: WindowFrostScheduler = .main) { self.scheduler = scheduler }

    func beginConnection(onTimeout: @escaping () -> Void) -> UUID {
        let id = UUID()
        connectionID = id
        ready = false
        scheduler.after(3) { [weak self] in
            guard let self, self.connectionID == id, !self.ready else { return }
            onTimeout()
        }
        return id
    }

    func deliver(_ message: [String: Any], for id: UUID) {
        guard connectionID == id, ready else { return }
        receive?(message)
    }

    func connected(for id: UUID) {
        guard connectionID == id, !ready else { return }
        ready = true
        let pending = waiters; waiters.removeAll()
        pending.forEach { $0(true) }
    }

    func failed(for id: UUID) {
        guard connectionID == id else { return }
        connectionID = nil
        ready = false
        let pending = waiters; waiters.removeAll()
        // A failed preparation may synchronously finish its transition and start
        // the queued replacement. Detach the failed connection before calling out.
        let oldDisconnected = disconnected
        receive = nil; disconnected = nil
        pending.forEach { $0(false) }
        oldDisconnected?()
    }
}

/// Coalesce only consecutive positions belonging to the same motion. Commands
/// such as release, cover and retarget are barriers and always retain their order.
/// The lock lets a blocked consumer accumulate one latest position instead of a
/// main-queue task for every input sample. Each batch yields before the next one.
final class WindowFrostMessageQueue {
    private let lock = NSLock()
    private let schedule: (@escaping () -> Void) -> Void
    private let consume: ([String: Any]) -> Void
    private var pending: [[String: Any]] = []
    private var scheduled = false
    private var cancelled = false

    init(schedule: @escaping (@escaping () -> Void) -> Void, consume: @escaping ([String: Any]) -> Void) {
        self.schedule = schedule
        self.consume = consume
    }

    func enqueue(_ message: [String: Any]) {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        if let last = pending.last, Self.canCoalesce(last, message) {
            pending[pending.count - 1] = message
        } else { pending.append(message) }
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule { schedule { [weak self] in self?.drain() } }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        pending.removeAll()
    }

    private func drain() {
        lock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
        for message in batch {
            lock.lock(); let stopped = cancelled; lock.unlock()
            guard !stopped else { return }
            consume(message)
        }
        lock.lock()
        let again = !cancelled && !pending.isEmpty
        if !again { scheduled = false }
        lock.unlock()
        if again { schedule { [weak self] in self?.drain() } }
    }

    private static func canCoalesce(_ first: [String: Any], _ next: [String: Any]) -> Bool {
        guard first["command"] as? String == "follow", next["command"] as? String == "follow",
              let id = first["id"] as? String, id == next["id"] as? String,
              let sequence = first["sequence"] as? Int, sequence == next["sequence"] as? Int,
              let a = first["frame"] as? [Double], let b = next["frame"] as? [Double],
              a.count == 4, b.count == 4, a.allSatisfy(\.isFinite), b.allSatisfy(\.isFinite) else { return false }
        return a[2] == b[2] && a[3] == b[3]
    }
}

enum WindowFrostClockPolicy {
    static func needsClock(animating: Bool, compositorActive: Bool, trackingPointer: Bool) -> Bool {
        animating && (!compositorActive || trackingPointer)
    }
}

/// A persistent child isolates native panel commits from Rectangle's menu/UI run loop.
final class WindowFrostRendererConnection {
    static let shared = WindowFrostRendererConnection()
    private var process: Process?
    private var input: FileHandle?
    private let writer = DispatchQueue(label: "Rectangle.blur-writer", qos: .userInteractive)
    private var outbox: WindowFrostMessageQueue?
    private var ready = false
    private let callbacks = WindowFrostRendererCallbacks()
    private var surfaceWindowIDs: Set<CGWindowID> = []
    var inputTransparentSurfaces: [CGWindowID: pid_t] {
        precondition(Thread.isMainThread)
        guard ready, let process, process.isRunning else { return [:] }
        return Dictionary(uniqueKeysWithValues: surfaceWindowIDs.map { ($0, process.processIdentifier) })
    }
    var receive: (([String: Any]) -> Void)? {
        get { callbacks.receive }
        set { callbacks.receive = newValue }
    }
    var disconnected: (() -> Void)? {
        get { callbacks.disconnected }
        set { callbacks.disconnected = newValue }
    }

    func prewarm() {
        guard WindowAnimator.frostedEnabled else { return }
        connect { _ in }
    }
    func connect(_ completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        if ready, process?.isRunning == true { completion(true); return }
        callbacks.waiters.append(completion)
        guard process == nil else { return }
        let child = Process(), toChild = Pipe(), fromChild = Pipe()
        child.executableURL = Bundle.main.executableURL
        child.arguments = ["--rectangle-blur-renderer"]
        child.standardInput = toChild
        child.standardOutput = fromChild
        child.standardError = FileHandle.standardError
        process = child
        let connectionID = callbacks.beginConnection { [weak self, weak child] in
            guard let self, let child, self.process === child else { return }
            self.fail()
        }
        input = toChild.fileHandleForWriting
        _ = fcntl(toChild.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let handle = toChild.fileHandleForWriting
        outbox = WindowFrostMessageQueue(schedule: { [writer] work in writer.async(execute: work) }) { [weak self, weak child] message in
            guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
            data.append(10)
            if !frostWrite(data, to: handle.fileDescriptor) {
                DispatchQueue.main.async {
                    guard let self, let child, self.process === child else { return }
                    self.fail()
                }
            }
        }
        child.terminationHandler = { [weak self, weak child] _ in
            DispatchQueue.main.async {
                guard let self, let child, self.process === child else { return }
                self.fail()
            }
        }
        do { try child.run() } catch { fail(); return }
        // Blocking reads belong only to this private transport queue.
        DispatchQueue(label: "Rectangle.blur-reader", qos: .userInteractive).async { [weak self, weak child] in
            var buffer = Data()
            while true {
                let data = fromChild.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                if buffer.count > 1_048_576 { break }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    DispatchQueue.main.async {
                        guard let self, let child, self.process === child else { return }
                        if message["event"] as? String == "ready" {
                            self.ready = true
                            self.callbacks.connected(for: connectionID)
                        } else {
                            if let surfaces = message["surfaces"] as? [[String: Any]] {
                                self.surfaceWindowIDs = Set(surfaces.compactMap { ($0["windowNumber"] as? NSNumber)?.uint32Value })
                            }
                            self.callbacks.deliver(message, for: connectionID)
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, let child, self.process === child else { return }
                self.fail()
            }
        }
    }
    func send(_ message: [String: Any]) {
        guard process?.isRunning == true else { return }
        outbox?.enqueue(message)
    }
    private func fail() {
        let child = process
        process = nil; ready = false; surfaceWindowIDs.removeAll()
        outbox?.cancel(); outbox = nil
        // Close on the writer after its in-flight write, before a replacement
        // connection can reuse this descriptor for queued old messages.
        if let input { writer.async { try? input.close() } }
        input = nil
        if child?.isRunning == true { child?.terminate() }
        if let id = callbacks.connectionID { callbacks.failed(for: id) }
    }
}

final class WindowFrostOverlay {
    static func clearIdleSurfaces() { WindowFrostRendererConnection.shared.send(["command": "clear"]) }
    static func clearPendingDismissal() { WindowFrostRendererConnection.shared.send(["command": "clear-dismissal"]) }
    private let id = UUID().uuidString
    var diagnosticID: String? { id }
    private let source: CGRect
    private var owned: Bool
    private let restoring: Bool
    private let onCancel: () -> Void
    private var destination: CGRect
    private var input: WindowFrostInputTap?
    private var closed = false
    private var sequence = 0
    private var prepared: ((Bool) -> Void)?
    private var covered: ((Bool) -> Void)?
    private var arrived: (() -> Void)?
    private var released = false
    private var resizingUnderCover = false
    private var displayCommand = false
    var previewHeaderRegions: [CGRect] = []
    var previewAvailable = false { didSet { updateInput() } }
    var beginPreviewGesture: (() -> Bool)?
    var previewGesture: ((CGEvent, CGRect) -> Void)?
    private var previewEvents: [CGEvent] = []
    private var previewFrame: CGRect?
    private var previewPointerOwned = false
    private(set) var currentFrame: CGRect
    private var connection: WindowFrostRendererConnection { .shared }

    init?(source: CGRect, destination: CGRect, externallyOwnedDrag: Bool = false, restoring: Bool = false,
          releasedSnap: Bool = false, displayCommand: Bool = false, onCancel: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        let displays = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(id.uint32Value)
        }
        guard !source.isEmpty, !destination.isEmpty,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              (releasedSnap || displayCommand ? WindowFrostSurfaceGeometry.canStartReleasedSnap(source: source, destination: destination,
                                                                             displays: displays)
               : displays.contains(where: {
                   WindowFrostSurfaceGeometry.canStart(source: source, destination: destination,
                                                       display: $0, ownedDrag: externallyOwnedDrag)
               })) else { return nil }
        self.source = source; self.destination = destination; currentFrame = source
        owned = externallyOwnedDrag; self.restoring = restoring; self.onCancel = onCancel
        self.displayCommand = displayCommand
        guard let tap = WindowFrostInputTap(regions: [source, destination], externallyOwnedDrag: externallyOwnedDrag,
                                          cancel: onCancel, previewDrag: { [weak self] event in
            self?.handlePreviewEvent(event)
        }) else { return nil }
        input = tap
        connection.receive = { [weak self] message in self?.receive(message) }
        connection.disconnected = { [weak self] in
            guard let self, !self.closed else { return }
            if let callback = self.prepared { self.prepared = nil; callback(false) }
            else if let callback = self.covered { self.covered = nil; callback(false) }
            else { self.onCancel() }
        }
    }
    func show() { prepare { _ in } }
    private func updateInput() {
        // Frame reports can be 50 ms old while the cover is growing. Offer a
        // protected press to the renderer, which verifies the blank header
        // against its current presentation before granting drag ownership.
        let regions = [source, currentFrame, destination]
        input?.update(regions: regions, previewRegions: previewAvailable ? regions : [])
    }
    private func handlePreviewEvent(_ event: CGEvent) {
        guard !closed else { return }
        if event.type == .leftMouseDown {
            guard beginPreviewGesture?() == true else { onCancel(); return }
            previewEvents = [event]; previewFrame = nil
            previewPointerOwned = true
            owned = true; released = false; sequence += 1; arrived = nil
            send("grab", fields: ["pointer": [event.location.x, event.location.y],
                "headerSource": Self.values(source), "headerRegions": previewHeaderRegions.map(Self.values),
                "inputTime": Double(event.timestamp) / 1_000_000_000])
            let expected = sequence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, !self.closed, self.sequence == expected, self.previewFrame == nil else { return }
                self.onCancel()
            }
        } else {
            if previewPointerOwned {
                // Forward live input before the grab ACK or drag adoption. The
                // buffered ownership callbacks must not replay older positions.
                send("preview-follow", fields: ["pointer": [event.location.x, event.location.y],
                    "released": event.type == .leftMouseUp,
                    "inputTime": Double(event.timestamp) / 1_000_000_000])
            }
            if let previewFrame { previewGesture?(event, previewFrame) }
            else { previewEvents.append(event) }
        }
    }
    func resumeAutomatic() {
        owned = false; released = false; previewFrame = nil; previewEvents.removeAll()
        previewPointerOwned = false
        send("automatic")
    }
    func prepare(completion: @escaping (Bool) -> Void) {
        guard !closed else { completion(false); return }
        prepared = completion
        connection.connect { [weak self] ready in
            guard let self, !self.closed else { return }
            guard ready else { let callback = self.prepared; self.prepared = nil; callback?(false); return }
            self.send("show", fields: ["frame": Self.values(self.source), "ownedDrag": self.owned,
                                       "blurAppearance": Defaults.blurAppearance.value.rawValue,
                                       "released": self.released, "restoring": self.restoring, "resizingUnderCover": self.resizingUnderCover])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, !self.closed, let callback = self.prepared else { return }
                self.prepared = nil; callback(false)
            }
        }
    }
    func animate(to frame: CGRect, duration: TimeInterval, curve: @escaping (Double) -> CGFloat,
                 offset: @escaping () -> CGPoint = { .zero }, completion: @escaping () -> Void) {
        sendMotion("animate", to: frame, duration: duration, curve: curve, offset: offset, completion: completion)
    }
    func retarget(to frame: CGRect, duration: TimeInterval, completion: @escaping () -> Void) {
        sendMotion("retarget", to: frame, duration: duration, curve: WindowAnimationCurve.value,
                   offset: { .zero }, completion: completion)
    }
    func enableDisplayCommand() { displayCommand = true }
    private func sendMotion(_ command: String, to frame: CGRect, duration: TimeInterval,
                            curve: @escaping (Double) -> CGFloat, offset: () -> CGPoint,
                            completion: @escaping () -> Void) {
        guard !closed else { return }
        destination = frame; sequence += 1; arrived = completion
        let delta = offset()
        send(command, fields: ["frame": Self.values(frame), "duration": duration,
                                  "curve": (0...60).map { Double(curve(Double($0) / 60)) },
                                  "offset": [delta.x, delta.y],
                                  "displayCommand": displayCommand,
                                  "follow": owned && !released])
        let expected = sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2, duration + 1)) { [weak self] in
            guard let self, !self.closed, self.sequence == expected, self.arrived != nil else { return }
            self.onCancel()
        }
    }
    func cover(frame: CGRect, completion: @escaping (Bool) -> Void) {
        guard !closed else { completion(false); return }
        sequence += 1; arrived = nil; covered = completion; currentFrame = frame
        send("cover", fields: ["frame": Self.values(frame)])
        let expected = sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.closed, self.sequence == expected, let callback = self.covered else { return }
            self.covered = nil; callback(false)
        }
    }
    func follow(frame: CGRect) {
        guard !closed else { return }
        destination = frame
        guard !previewPointerOwned else { return }
        send("follow", fields: ["frame": Self.values(frame)])
    }
    func release() {
        guard !closed, owned, !released else { return }
        released = true
        previewPointerOwned = false
        // This message does not invalidate an in-flight geometry acknowledgement.
        // A release before connection readiness is also carried by the show command.
        send("release")
    }
    func configureFinalMaterial(resizingUnderCover: Bool) {
        guard !closed else { return }
        self.resizingUnderCover = resizingUnderCover
        // Persist this choice for show if renderer startup is still pending.
        send("material", fields: ["resizingUnderCover": resizingUnderCover])
    }
    func update(frame: CGRect) {
        guard !closed else { return }
        sequence += 1; arrived = nil; currentFrame = frame
        send("update", fields: ["frame": Self.values(frame)])
        updateInput()
    }
    func freeze() {
        guard !closed else { return }
        sequence += 1; arrived = nil
        // The renderer has a newer pointer/presentation position than the parent.
        // Freeze there rather than jumping to a potentially 50 ms old frame report.
        send("freeze")
    }
    func close() { end(command: "close") }
    func dismiss() { end(command: "dismiss") }
    private func end(command: String) {
        guard !closed else { return }
        closed = true; prepared = nil; covered = nil; arrived = nil
        previewEvents.removeAll(); previewFrame = nil
        previewPointerOwned = false
        send(command)
        input?.close(); input = nil
        connection.receive = nil; connection.disconnected = nil
    }
    private func send(_ command: String, fields: [String: Any] = [:]) {
        var message = fields; message["command"] = command; message["id"] = id; message["sequence"] = sequence
        if command == "follow", WindowFrostDiagnostics.enabled {
            message["sentUptime"] = ProcessInfo.processInfo.systemUptime
        }
        connection.send(message)
    }
    private func receive(_ message: [String: Any]) {
        guard !closed, message["id"] as? String == id, message["sequence"] as? Int == sequence else { return }
        if let values = message["frame"] as? [Double], values.count == 4 {
            currentFrame = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            updateInput()
        }
        switch message["event"] as? String {
        case "grabbed":
            previewFrame = currentFrame
            let frozenFrame = currentFrame
            let events = previewEvents; previewEvents.removeAll()
            for event in events {
                guard !closed else { break }
                previewGesture?(event, frozenFrame)
            }
        case "shown": let callback = prepared; prepared = nil; callback?(true)
        case "covered": let callback = covered; covered = nil; callback?(true)
        case "arrived" where message["sequence"] as? Int == sequence:
            let callback = arrived; arrived = nil; callback?()
        case "failed": onCancel()
        default: break
        }
    }
    private static func values(_ frame: CGRect) -> [Double] { [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)] }
    deinit { input?.close() }
}

private final class WindowFrostPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum WindowFrostSurfaceGeometry {
    static func canStartReleasedSnap(source: CGRect, destination: CGRect, displays: [CGRect]) -> Bool {
        // A restored window may be wholly on the source screen at release. Its
        // source and destination covers need not intersect the same display.
        displays.contains { intersects(source, display: $0) }
            && displays.contains { intersects(destination, display: $0) }
    }

    static func canStart(source: CGRect, destination: CGRect, display: CGRect, ownedDrag: Bool) -> Bool {
        // Each display clips the same global shape. The parking planner checks
        // reachable endpoints separately, so a clipped source needs only its
        // visible portion covered here.
        intersects(source, display: display) && (ownedDrag || intersects(destination, display: display))
    }

    static func intersects(_ frame: CGRect, display: CGRect) -> Bool {
        guard !frame.isNull, [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy({ $0.isFinite }) else { return false }
        let overlap = display.intersection(frame)
        return !overlap.isNull && !overlap.isEmpty
    }

    static func localFrame(_ frame: CGRect, display: CGRect) -> CGRect {
        CGRect(x: frame.minX - display.minX, y: display.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }
}

/// Held drags keep their current material even after their restore animation ends.
/// Commands start the final material near arrival; destination coverage is the
/// mandatory readiness gate if a timer tick is delayed or motion is forced to finish.
enum WindowFrostMaterialTiming {
    static let fadeDuration: TimeInterval = 0.08

    static func tintAlpha(resizingUnderCover: Bool) -> CGFloat { resizingUnderCover ? 0.9 : 0.5 }

    static func shouldBeginFinalMaterial(ownedDrag: Bool, remaining: TimeInterval) -> Bool {
        !ownedDrag && remaining <= fadeDuration
    }
}

/// Motion of the disposable preview only. The real window's placement is unchanged.
enum WindowFrostMotion {
    static let response: TimeInterval = 0.76
    static let dampingRatio: Double = 1
    static let sampleRate: Double = 120
    static let angularFrequency = 2 * Double.pi / response
    // Wave's 0.0001 settling threshold and critically damped 1.25 multiplier,
    // rounded to the first completed sample, just as its display driver does.
    static let sampledDuration = ceil((-log(0.0001) / angularFrequency * 1.25) * sampleRate) / sampleRate
    static let playbackRate: Double = 4.5
    static let automaticDuration = sampledDuration / playbackRate
    static let defaultSamples = samples(initialVelocity: 0)
    // An interrupted preview is already in the user's hand. Start shrinking
    // immediately, then brake continuously to rest over the requested duration.
    static let previewRestoreSamples = (0...60).map { index in
        1 - pow(1 - Double(index) / 60, 3)
    }

    enum Profile: String {
        case wave = "wave-response-0.76-damping-1-4.5x"
        case deceleration = "strong-deceleration-260ms"
        case previewRestore = "preview-restore-ease-out"
    }

    static func profile(from source: CGRect, to destination: CGRect, restoring: Bool = false,
                        previewDrag: Bool = false) -> Profile {
        if previewDrag { return .previewRestore }
        if restoring { return .wave }
        // Area defines the direction of mixed width/height changes. A tiny size
        // rounding difference must not turn an ordinary move into a shrink.
        let tolerance = max(source.width, source.height, destination.width, destination.height)
        return source.width * source.height - destination.width * destination.height > tolerance ? .wave : .deceleration
    }

    static func duration(requested: TimeInterval, profile: Profile, restoringDrag: Bool = false) -> TimeInterval {
        guard requested > 0 else { return 0 }
        if profile == .previewRestore { return requested }
        let duration = profile == .wave ? automaticDuration : WindowPreviewDeceleration.duration
        return restoringDrag ? duration / WindowAnimationCurve.unsnapPlaybackRate : duration
    }

    /// Same semi-implicit Euler spring update as Wave, sampled on a fixed clock
    /// so application scheduling stalls cannot interrupt compositor playback.
    /// See docs/frosted-window-transitions.md for the upstream reference and limits.
    static func samples(initialVelocity: Double) -> [Double] {
        let dt = 1 / sampleRate, stiffness = angularFrequency * angularFrequency
        let damping = 2 * dampingRatio * angularFrequency
        var position = 0.0, velocity = min(angularFrequency, max(0, initialVelocity))
        var result = [position]
        for _ in 0..<Int((sampledDuration * sampleRate).rounded()) {
            velocity += (stiffness * (1 - position) - damping * velocity) * dt
            position = min(1, max(position, position + velocity * dt))
            result.append(position)
        }
        result[result.count - 1] = 1 // Wave resolves exactly at its settling deadline.
        return result
    }

    static func releaseVelocity(from source: CGRect, to destination: CGRect, pointerVelocity: CGPoint) -> Double {
        let dx = destination.midX - source.midX, dy = destination.midY - source.midY
        let squaredDistance = dx * dx + dy * dy
        guard squaredDistance > 1 else { return 0 }
        // Project onto the requested path and use the fixture's no-overshoot cap.
        return min(angularFrequency, max(0, Double((pointerVelocity.x * dx + pointerVelocity.y * dy) / squaredDistance)))
    }

    static func progress(at time: Double) -> CGFloat {
        let index = min(1, max(0, time)) * Double(defaultSamples.count - 1)
        let lower = Int(index), upper = min(lower + 1, defaultSamples.count - 1)
        return CGFloat(defaultSamples[lower] + (defaultSamples[upper] - defaultSamples[lower]) * (index - Double(lower)))
    }

    static func frame(from source: CGRect, to destination: CGRect, progress: Double,
                      eased: CGFloat, offset: CGPoint = .zero, ownedDrag: Bool) -> CGRect {
        if progress <= 0 { return source.offsetBy(dx: offset.x, dy: offset.y) }
        if progress >= 1 { return destination.offsetBy(dx: offset.x, dy: offset.y) }
        let t = min(1, max(0, eased))
        // All four edges are convex combinations of the requested endpoints.
        // Screen-aligned endpoints therefore cannot overshoot the screen, even
        // while changing size. No decorative stretch may cross a stopping edge.
        return CGRect(x: source.minX + (destination.minX - source.minX) * t + offset.x,
                      y: source.minY + (destination.minY - source.minY) * t + offset.y,
                      width: source.width + (destination.width - source.width) * t,
                      height: source.height + (destination.height - source.height) * t)
    }

}

/// AppKit hosts these layers but does not lay them out during automatic travel.
/// Every display receives the same geometry samples and a common media-time origin.
final class WindowFrostCompositorSurface {
    static let motionKey = "rectangle.geometry"
    let tracking = CALayer()
    let root = CALayer()
    let clip = CALayer()
    let backdrop: CALayer
    let tint = CALayer()
    let shadow: BlurPreviewShadow
    var geometryLayers: [CALayer] { [root, clip, backdrop, tint] }

    init(backdrop: CALayer, radius: CGFloat, color: NSColor, borderColor: NSColor,
         borderWidth: CGFloat, shadowOpacity: Float) {
        self.backdrop = backdrop
        shadow = BlurPreviewShadow(cornerRadius: radius)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in [tracking] + geometryLayers {
            layer.anchorPoint = .zero
            layer.position = .zero
            layer.autoresizingMask = []
            layer.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) { layer.preferredDynamicRange = .standard }
            else if #available(macOS 14, *) { layer.wantsExtendedDynamicRangeContent = false }
        }
        shadow.shape.shadowOpacity = shadowOpacity
        clip.cornerRadius = radius; clip.masksToBounds = true
        tint.cornerRadius = radius; tint.backgroundColor = color.cgColor
        tint.borderColor = borderColor.cgColor; tint.borderWidth = borderWidth
        tracking.addSublayer(root)
        root.addSublayer(clip); clip.addSublayer(backdrop); clip.addSublayer(tint)
        // Composite the hollow shadow above the backdrop so it cannot tint the glass.
        root.addSublayer(shadow.container)
        CATransaction.commit()
    }

    func setFrame(_ frame: CGRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tracking.position = .zero
        if root.position != frame.origin { root.position = frame.origin }
        let bounds = CGRect(origin: .zero, size: frame.size)
        if root.bounds != bounds {
            geometryLayers.forEach { $0.bounds = bounds }
            shadow.setSize(frame.size)
        }
        CATransaction.commit()
    }

    /// Mouse translation lives outside the animated geometry. Updating it never
    /// replaces size/anchor keyframes or rebuilds the backdrop and shadow bounds.
    func trackPointer(delta: CGPoint) {
        guard tracking.position != delta else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tracking.position = delta
        CATransaction.commit()
    }

    var presentationFrame: CGRect? {
        guard let shape = root.presentation() else { return nil }
        let delta = tracking.presentation()?.position ?? tracking.position
        return shape.frame.offsetBy(dx: delta.x, dy: delta.y)
    }

    func animate(frames: [CGRect], duration: TimeInterval, beginTime: CFTimeInterval,
                 timingFunction: CAMediaTimingFunction? = nil, opacities: [Double]? = nil) {
        install(prepareMotion(frames: frames, duration: duration, timingFunction: timingFunction, opacities: opacities),
                beginTime: beginTime)
    }

    func prepareMotion(frames: [CGRect], duration: TimeInterval,
                       timingFunction: CAMediaTimingFunction? = nil, opacities: [Double]? = nil) -> [(CALayer, CAAnimationGroup)] {
        guard let last = frames.last, frames.count > 1 else { return [] }
        setFrame(last) // Explicit animations leave the model at its exact destination.
        root.opacity = 1
        let bounds = frames.map { NSValue(rect: CGRect(origin: .zero, size: $0.size)) }
        let times = frames.indices.map { NSNumber(value: Double($0) / Double(frames.count - 1)) }
        func keyframes(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values; animation.keyTimes = times
            animation.calculationMode = .linear; animation.duration = duration
            return animation
        }
        let geometry = geometryLayers.map { layer -> (CALayer, CAAnimationGroup) in
            var animations: [CAAnimation] = [keyframes("bounds", bounds)]
            if layer === root {
                animations.append(keyframes("position", frames.map { NSValue(point: $0.origin) }))
                if let opacities { animations.append(keyframes("opacity", opacities)) }
            }
            let group = CAAnimationGroup()
            group.animations = animations; group.duration = duration
            group.timingFunction = timingFunction
            return (layer, group)
        }
        return geometry + shadow.prepareAnimations(sizes: frames.map(\.size), duration: duration, timingFunction: timingFunction)
    }

    func install(_ animations: [(CALayer, CAAnimationGroup)], beginTime: CFTimeInterval) {
        for (layer, group) in animations {
            group.beginTime = layer.convertTime(beginTime, from: nil)
            layer.add(group, forKey: Self.motionKey)
        }
    }

    func stop() {
        geometryLayers.forEach { $0.removeAnimation(forKey: Self.motionKey) }
        shadow.stop(key: Self.motionKey)
    }

    func setTint(_ color: NSColor, duration: TimeInterval) {
        let previous = tint.presentation()?.backgroundColor ?? tint.backgroundColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tint.backgroundColor = color.cgColor
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previous; animation.toValue = color.cgColor
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        tint.add(animation, forKey: "rectangle.tint")
        CATransaction.commit()
    }
}

/// Owns one stationary blur surface per display. Held size motion plays in
/// the compositor while the drag owner supplies event-derived translation.
final class WindowFrostRenderer: NSObject {
    private struct Surface {
        let screen: NSScreen
        let displayID: CGDirectDisplayID
        let bounds: CGRect
        let panel: WindowFrostPanel
        let shape: NSView
        let clipped: NSView
        let tint: NSBox?
        let tintColor: NSColor
        let customBackdrop: Bool
        let compositor: WindowFrostCompositorSurface?
        let fallbackShadow: BlurPreviewShadow?
    }
    private var surfaces: [Surface] = []
    private var id = ""
    private var sequence = 0
    private var frame = CGRect.zero
    private var origin = CGRect.zero
    private var target = CGRect.zero
    private var lastPointerUpdate: TimeInterval = 0
    private var offset = CGPoint.zero
    private var duration: TimeInterval = 0
    private var start: TimeInterval = 0
    private var animating = false
    private var following = false
    private var lastTick: TimeInterval = 0
    private var maxGap: TimeInterval = 0
    private var lastReport: TimeInterval = 0
    private let dismissal = WindowFrostDismissal()
    private var dismissalID: UUID? { dismissal.token }
    private var dismissalMonitor: Any?
    private var timer: Timer?
    private var stopDisplayLink: (() -> Void)?
    private var clockDisplayID: CGDirectDisplayID?
    private var ownedDrag = false
    private var blurAppearance = BlurAppearance.system
    private var resizingUnderCover = false
    private var finalMaterialToken: UUID?
    private var finalMaterialReady = false
    private var pendingCover: (() -> Void)?
    private var automaticMotion = false
    private var motionProfile = WindowFrostMotion.Profile.wave
    private var restoring = false
    private var initialOwnedRestore = false
    private var automaticSamples = WindowFrostMotion.defaultSamples
    private var continuationFrames: [CGRect]?
    private var continuationOpacities: [Double]?
    private var dragVelocity = CGPoint.zero
    private var dragVelocityTime: TimeInterval = 0
    private var compositorToken: UUID?
    private var compositorTracksPointer = false
    private var compositorPointerOffset = CGPoint.zero
    private var previewPointer: WindowFrostPreviewPointer?
    private var pendingFrameReport: UUID?
    private lazy var inbox = WindowFrostMessageQueue(schedule: { work in DispatchQueue.main.async(execute: work) }) { [weak self] message in
        self?.handle(message)
    }

    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let renderer = WindowFrostRenderer()
        renderer.startReading()
        renderer.reply("ready")
        app.run()
        exit(0)
    }
    private func startReading() {
        let inbox = self.inbox
        DispatchQueue(label: "Rectangle.blur-commands", qos: .userInteractive).async { [self] in
            var buffer = Data()
            while true {
                let data = FileHandle.standardInput.availableData
                if data.isEmpty { break }
                buffer.append(data)
                if buffer.count > 1_048_576 { break }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    inbox.enqueue(message)
                }
            }
            DispatchQueue.main.async { inbox.cancel(); self.closePanels(reason: "transport-eof"); exit(0) }
        }
    }
    private func handle(_ message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        if command != "follow" && command != "preview-follow" && command != "update" {
            WindowFrostDiagnostics.event("overlay.command", fields: ["command": command,
                "id": message["id"] as? String ?? "", "activeID": id,
                "sequence": message["sequence"] as? Int ?? 0])
        }
        if command == "clear-dismissal" {
            if dismissalID != nil { closePanels(reason: command) }
            return
        }
        if command == "clear" { closePanels(reason: command); animating = false; following = false; return }
        guard let incomingID = message["id"] as? String else { return }
        if command == "show" {
            closePanels(reason: "replacement-show"); animating = false; following = false
            id = incomingID
        } else if incomingID != id { return }
        sequence = message["sequence"] as? Int ?? 0
        if command == "close" { closePanels(reason: command); animating = false; following = false; return }
        if command == "dismiss" { beginDismissal(); return }
        if command == "material" {
            configureFinalMaterial(resizingUnderCover: message["resizingUnderCover"] as? Bool == true)
            return
        }
        if command == "release" {
            // The drag owner consumed mouse-down, so combined-session button
            // state can remain false throughout a valid held gesture. Its
            // explicit release (including the existing release watchdog) is
            // authoritative for both motion and material.
            if following { tick() }
            following = false
            previewPointer = nil
            if !animating { stopClock() }
            beginFinalMaterial(trigger: "parent")
            return
        }
        if command == "freeze" {
            stopCompositorMotion()
            animating = false; following = false; stopClock()
            reply("frame")
            return
        }
        if command == "grab" {
            let presented = compositorFrame() ?? frame
            let pointer = point(message["pointer"])
            guard let reference = message["headerSource"] as? [Double], reference.count == 4,
                  let headerValues = message["headerRegions"] as? [[Double]],
                  reference.allSatisfy(\.isFinite), reference[2] > 0, reference[3] > 0 else {
                reply("failed"); return
            }
            let referenceFrame = CGRect(x: reference[0], y: reference[1], width: reference[2], height: reference[3])
            let headers = headerValues.compactMap { values -> CGRect? in
                guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0 else { return nil }
                return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            }
            let accepted = WindowFrostPreviewDragGeometry.regions(headers, source: referenceFrame,
                presented: presented).contains { $0.contains(pointer) }
            WindowFrostDiagnostics.event("overlay.previewHit", fields: ["id": id, "sequence": sequence,
                "accepted": accepted, "pointer": [pointer.x, pointer.y],
                "frame": [presented.minX, presented.minY, presented.width, presented.height],
                "inputTime": message["inputTime"] as? Double ?? 0])
            guard accepted else { reply("failed"); return }
            stopCompositorMotion()
            continuationFrames = nil; continuationOpacities = nil
            animating = false; following = true; ownedDrag = true
            restoring = true; initialOwnedRestore = false; automaticMotion = false
            origin = frame; target = frame; offset = .zero
            previewPointer = WindowFrostPreviewPointer(down: pointer)
            dragVelocity = .zero; dragVelocityTime = 0
            // A near-complete maximize may already be fading its material.
            // Invalidate that callback while this same cover becomes held.
            finalMaterialToken = nil; finalMaterialReady = false
            stopClock()
            reply("grabbed")
            return
        }
        if command == "preview-follow" {
            guard ownedDrag, following,
                  previewPointer?.update(point(message["pointer"]), isRelease: message["released"] as? Bool == true) == true,
                  let pointer = previewPointer else { return }
            updatePointerOffset(pointer.offset)
            tick()
            if !animating { reportHeldFrame() }
            WindowFrostDiagnostics.event("overlay.previewPointer", fields: ["id": id, "sequence": sequence,
                "inputTime": message["inputTime"] as? Double ?? 0,
                "offset": [offset.x, offset.y], "morphing": animating,
                "frame": [frame.minX, frame.minY, frame.width, frame.height]])
            return
        }
        if command == "automatic" {
            ownedDrag = false; following = false; restoring = false
            previewPointer = nil
            return
        }
        guard let values = message["frame"] as? [Double], values.count == 4, values.allSatisfy(\.isFinite),
              values[2] > 0, values[3] > 0 else { reply("failed"); return }
        let next = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        switch command {
        case "show":
            blurAppearance = BlurAppearance(rawValue: message["blurAppearance"] as? Int ?? 0) ?? .system
            ownedDrag = message["ownedDrag"] as? Bool == true
            dragVelocity = .zero; dragVelocityTime = 0
            restoring = message["restoring"] as? Bool == true
            initialOwnedRestore = ownedDrag
            resizingUnderCover = message["resizingUnderCover"] as? Bool == true
            // Only the parent knows the released snap target and whether its
            // placement requires covered growth. It selects the tint before
            // release; an independent mouse-up monitor would race that choice.
            guard createPanels(frame: next) else { reply("failed"); return }
            render(next)
            for surface in surfaces { surface.panel.orderFrontRegardless(); surface.panel.displayIfNeeded() }
            CATransaction.flush()
            if message["released"] as? Bool == true { beginFinalMaterial(trigger: "early-release") }
            // Allow the native surface a run-loop presentation opportunity before parking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [self] in
                guard id == incomingID, !surfaces.isEmpty, surfaces.allSatisfy({ $0.panel.isVisible }) else { return }
                reply("shown")
            }
        case "animate", "retarget":
            let incomingVelocity = motionVelocity()
            let initialOpacity = Double(surfaces.first?.compositor?.root.presentation()?.opacity ?? 1)
            stopCompositorMotion()
            continuationFrames = nil
            continuationOpacities = nil
            origin = frame; target = next
            offset = point(message["offset"])
            following = message["follow"] as? Bool == true
            if following, let pointer = previewPointer {
                // The presentation already includes live translation. Remove it
                // from the morph origin before applying the newest pointer once.
                origin = pointer.motionOrigin(presented: frame)
                offset = pointer.offset
            }
            automaticMotion = !ownedDrag || !following
            motionProfile = WindowFrostMotion.profile(from: origin, to: target, restoring: restoring || initialOwnedRestore,
                previewDrag: following && previewPointer != nil)
            duration = WindowFrostMotion.duration(requested: message["duration"] as? Double ?? 0,
                profile: motionProfile, restoringDrag: ownedDrag && (following || initialOwnedRestore))
            initialOwnedRestore = false
            let releaseVelocity = motionProfile == .wave && ownedDrag && automaticMotion && ProcessInfo.processInfo.systemUptime - dragVelocityTime <= 0.1
                ? WindowFrostMotion.releaseVelocity(from: origin.offsetBy(dx: offset.x, dy: offset.y),
                    to: target.offsetBy(dx: offset.x, dy: offset.y), pointerVelocity: dragVelocity) : 0
            automaticSamples = motionProfile == .previewRestore ? WindowFrostMotion.previewRestoreSamples
                : WindowFrostMotion.samples(initialVelocity: releaseVelocity)
            if command == "retarget" {
                let continuation = WindowFrostRetargetMotion.plan(from: origin, to: target,
                    velocity: incomingVelocity, requested: message["duration"] as? Double ?? 0)
                continuationFrames = continuation.frames
                duration = continuation.duration
            }
            if message["displayCommand"] as? Bool == true,
               let sourceDisplay = WindowDisplayTransition.display(containing: origin, displays: surfaces.map(\.bounds)),
               let destinationDisplay = WindowDisplayTransition.display(containing: target, displays: surfaces.map(\.bounds)) {
                let route = WindowDisplayTransition.route(from: sourceDisplay, to: destinationDisplay)
                if route == .fade && duration > 0 {
                    duration = 0.28
                    let times = (0...40).map { Double($0) / 40 }
                    continuationFrames = times.map { WindowDisplayTransition.fadeFrame(from: origin, to: target, progress: $0) }
                    continuationOpacities = times.map { WindowDisplayTransition.fadeOpacity(progress: $0, initial: initialOpacity) }
                }
                WindowFrostDiagnostics.event("overlay.displayTransition", fields: ["id": id, "sequence": sequence,
                    "route": route.rawValue, "source": [origin.minX, origin.minY, origin.width, origin.height],
                    "target": [target.minX, target.minY, target.width, target.height]])
            }
            if continuationOpacities == nil, initialOpacity < 0.999 {
                // A shortcut can interrupt a fade. Reveal its new continuation
                // from the current opacity instead of flashing fully opaque.
                let count = continuationFrames?.count ?? (motionProfile != .deceleration ? automaticSamples.count : 2)
                continuationOpacities = (0..<count).map { initialOpacity + (1 - initialOpacity) * Double($0) / Double(count - 1) }
            }
            WindowFrostDiagnostics.event("overlay.motionPlan", fields: ["ownedDrag": ownedDrag,
                "following": following, "automaticMotion": automaticMotion,
                "requestedMilliseconds": (message["duration"] as? Double ?? 0) * 1000,
                "durationMilliseconds": duration * 1000,
                "initialVelocity": releaseVelocity,
                "profile": motionProfile.rawValue])
            if command == "retarget" {
                WindowFrostDiagnostics.event("overlay.retarget", fields: ["id": id, "sequence": sequence,
                    "source": [origin.minX, origin.minY, origin.width, origin.height],
                    "target": [target.minX, target.minY, target.width, target.height],
                    "durationMilliseconds": duration * 1000])
            }
            start = ProcessInfo.processInfo.systemUptime; lastTick = start; lastPointerUpdate = start; maxGap = 0; animating = true
            if duration > 0 && !surfaces.isEmpty && surfaces.allSatisfy({ $0.compositor != nil }) {
                startCompositorMotion(trackingPointer: !automaticMotion)
            } else { tick() }
        case "cover":
            stopCompositorMotion()
            setMotionOpacity(1)
            animating = false; following = false; stopClock(); render(next)
            // Every successful path must establish the final material before placing
            // the real window, including forced finishes and zero-duration motion.
            beginFinalMaterial(trigger: "destination-cover")
            let expectedSequence = sequence
            CATransaction.flush()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [self] in
                guard id == incomingID, sequence == expectedSequence, !surfaces.isEmpty, surfaces.allSatisfy({ $0.panel.isVisible }) else { return }
                let acknowledge = { [weak self] in
                    guard let self, self.id == incomingID, self.sequence == expectedSequence,
                          !self.surfaces.isEmpty, self.surfaces.allSatisfy({ $0.panel.isVisible }) else { return }
                    self.reply("covered")
                }
                if !finalMaterialReady { pendingCover = acknowledge }
                else { acknowledge() }
            }
        case "update": stopCompositorMotion(); animating = false; following = false; stopClock(); render(next)
        case "follow":
            // The owner has the actual intercepted drag events. A global cursor
            // query can remain at the first point while those events are withheld.
            // Keep this stream authoritative both during and after the size morph.
            guard ownedDrag, following, next.size == target.size else { return }
            if let sent = message["sentUptime"] as? Double {
                WindowFrostDiagnostics.event("overlay.followLatency", fields: ["id": id, "sequence": sequence,
                    "milliseconds": max(0, ProcessInfo.processInfo.systemUptime - sent) * 1000])
            }
            let nextOffset = CGPoint(x: next.minX - target.minX, y: next.minY - target.minY)
            updatePointerOffset(nextOffset)
            tick()
            if !animating { reportHeldFrame() }
        default: break
        }
    }
    private func point(_ object: Any?) -> CGPoint {
        guard let values = object as? [Double], values.count == 2 else { return .zero }
        return CGPoint(x: values[0], y: values[1])
    }
    private func updatePointerOffset(_ next: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastPointerUpdate
        if dt > 0, next != offset {
            dragVelocity = CGPoint(x: (next.x - offset.x) / dt, y: (next.y - offset.y) / dt)
            dragVelocityTime = now
        }
        offset = next; lastPointerUpdate = now
    }
    private func tick() {
        guard animating || following else { stopClock(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let tickDuration = now - lastTick
        maxGap = max(maxGap, tickDuration); lastTick = now
        if compositorToken != nil, compositorTracksPointer {
            let delta = CGPoint(x: offset.x - compositorPointerOffset.x, y: -(offset.y - compositorPointerOffset.y))
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for surface in surfaces { surface.compositor?.trackPointer(delta: delta) }
            CATransaction.commit()
            if let current = compositorFrame() {
                frame = current
                updateSurfaceVisibility(for: current)
            }
            if now - lastReport > 0.05 { lastReport = now; reply("frame") }
            updateClock()
            return
        }
        let progress = animating && duration > 0 ? min(1, (now - start) / duration) : 1
        if animating && WindowFrostMaterialTiming.shouldBeginFinalMaterial(ownedDrag: ownedDrag,
                                                                           remaining: duration - (now - start)) {
            beginFinalMaterial(trigger: "motion-tail")
        }
        let t = motionProfile != .deceleration ? Self.sample(automaticSamples, progress: progress) : WindowPreviewDeceleration.value(at: progress)
        let next = continuationFrames.map { WindowFrostRetargetMotion.frame($0, progress: progress) }
            ?? WindowFrostMotion.frame(from: origin, to: target, progress: progress, eased: t,
                                      offset: offset, ownedDrag: ownedDrag)
        render(next)
        if let continuationOpacities { setMotionOpacity(Float(Self.sample(continuationOpacities, progress: progress))) }
        if animating && progress >= 1 {
            animating = false
            WindowFrostDiagnostics.event("overlay.motionTiming", fields: ["requestedMilliseconds": duration * 1000,
                "elapsedMilliseconds": (now - start) * 1000, "maximumTickGapMilliseconds": maxGap * 1000])
            reply("arrived")
        } else if animating && now - lastReport > 0.05 { lastReport = now; reply("frame") }
        updateClock()
    }

    /// Publish the last input even when it arrives inside the report throttle.
    /// A single trailing reply replaces the old indefinitely running idle clock.
    private func reportHeldFrame() {
        guard following, !animating else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReport >= 0.05 {
            pendingFrameReport = nil; lastReport = now; reply("frame")
            return
        }
        guard pendingFrameReport == nil else { return }
        let token = UUID(), expectedID = id, expectedSequence = sequence
        pendingFrameReport = token
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.05 - (now - lastReport))) { [weak self] in
            guard let self, self.pendingFrameReport == token else { return }
            self.pendingFrameReport = nil
            guard self.id == expectedID, self.sequence == expectedSequence, self.following, !self.animating else { return }
            self.lastReport = ProcessInfo.processInfo.systemUptime
            self.reply("frame")
        }
    }

    private func compositorFrame() -> CGRect? {
        guard let surface = surfaces.first(where: { $0.compositor?.presentationFrame != nil }),
              let local = surface.compositor?.presentationFrame else { return nil }
        return CGRect(x: local.minX + surface.bounds.minX, y: surface.bounds.maxY - local.maxY,
                      width: local.width, height: local.height)
    }

    private func setMotionOpacity(_ opacity: Float) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for surface in surfaces {
            if let compositor = surface.compositor { compositor.root.opacity = opacity }
            else { surface.shape.alphaValue = CGFloat(opacity) }
        }
        CATransaction.commit()
    }

    private func motionVelocity() -> [CGFloat] {
        guard animating, duration > 0 else { return [0, 0, 0, 0] }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let lower = max(0, elapsed - 0.001), upper = min(duration, elapsed + 0.001)
        guard upper > lower else { return [0, 0, 0, 0] }
        func at(_ time: Double) -> CGRect {
            let progress = time / duration
            if let continuationFrames { return WindowFrostRetargetMotion.frame(continuationFrames, progress: progress) }
            let eased = motionProfile != .deceleration ? Self.sample(automaticSamples, progress: progress)
                : WindowPreviewDeceleration.value(at: progress)
            return WindowFrostMotion.frame(from: origin, to: target, progress: progress, eased: eased,
                                          offset: offset, ownedDrag: ownedDrag)
        }
        let a = at(lower), b = at(upper), dt = CGFloat(upper - lower)
        return [(b.minX - a.minX) / dt, (b.minY - a.minY) / dt,
                (b.width - a.width) / dt, (b.height - a.height) / dt]
    }

    private func stopCompositorMotion() {
        guard compositorToken != nil else { return }
        if let current = compositorFrame() { frame = current }
        compositorToken = nil; compositorTracksPointer = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for surface in surfaces {
            if let compositor = surface.compositor {
                compositor.root.opacity = compositor.root.presentation()?.opacity ?? compositor.root.opacity
            }
            surface.compositor?.setFrame(WindowFrostSurfaceGeometry.localFrame(frame, display: surface.bounds))
            surface.compositor?.stop()
        }
        CATransaction.commit()
    }

    private func startCompositorMotion(trackingPointer: Bool) {
        let preparedAt = ProcessInfo.processInfo.systemUptime
        if !trackingPointer { stopClock() }
        let token = UUID(), destination = target
        compositorToken = token
        compositorTracksPointer = trackingPointer
        compositorPointerOffset = offset
        let samples = motionProfile != .deceleration ? automaticSamples : [0, 1]
        let frames = continuationFrames ?? samples.enumerated().map { index, eased in
            WindowFrostMotion.frame(from: origin, to: target,
                progress: Double(index) / Double(samples.count - 1),
                eased: CGFloat(eased), offset: offset, ownedDrag: false)
        }
        let swept = frames.reduce(CGRect.null) { $0.union($1) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.compositorToken == token else { return }
            self.compositorToken = nil; self.compositorTracksPointer = false; self.animating = false
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.surfaces.forEach { $0.compositor?.stop() }
            self.render(destination.offsetBy(dx: self.offset.x, dy: self.offset.y))
            CATransaction.commit()
            if !trackingPointer { self.beginFinalMaterial(trigger: "compositor-arrival") }
            WindowFrostDiagnostics.event("overlay.motionTiming", fields: ["driver": trackingPointer ? "core-animation-with-pointer" : "core-animation",
                "requestedMilliseconds": self.duration * 1000,
                "elapsedMilliseconds": (ProcessInfo.processInfo.systemUptime - self.start) * 1000])
            self.reply("arrived")
        }
        let prepared = surfaces.compactMap { surface -> (WindowFrostCompositorSurface, [(CALayer, CAAnimationGroup)])? in
            guard let compositor = surface.compositor else { return nil }
            // A neighboring display needs actual glass content, not just its shadow.
            let visibleFrame = trackingPointer ? frame : swept
            compositor.root.isHidden = !WindowFrostSurfaceGeometry.intersects(visibleFrame, display: surface.bounds)
            let animations = compositor.prepareMotion(frames: frames.map {
                WindowFrostSurfaceGeometry.localFrame($0, display: surface.bounds)
            }, duration: duration, timingFunction: continuationFrames != nil || motionProfile != .deceleration
                ? CAMediaTimingFunction(name: .linear) : WindowPreviewDeceleration.timingFunction,
                opacities: continuationOpacities)
            return (compositor, animations)
        }
        let beginTime = CACurrentMediaTime()
        start = ProcessInfo.processInfo.systemUptime; lastTick = start
        for (compositor, animations) in prepared { compositor.install(animations, beginTime: beginTime) }
        CATransaction.commit()
        let committedAt = ProcessInfo.processInfo.systemUptime
        WindowFrostDiagnostics.event("overlay.compositorMotion", fields: ["id": id, "sequence": sequence,
            "sampleCount": frames.count, "surfaceCount": surfaces.count, "durationMilliseconds": duration * 1000,
            "trackingPointer": trackingPointer, "preparationMilliseconds": (start - preparedAt) * 1000,
            "installationMilliseconds": (committedAt - start) * 1000])
        if WindowFrostDiagnostics.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
                guard let self, self.compositorToken == token, let sampled = self.compositorFrame() else { return }
                // This is a presentation-layer observation, not proof of a physical refresh.
                WindowFrostDiagnostics.event("overlay.firstPresentationSample", fields: ["id": self.id, "sequence": self.sequence,
                    "sinceCommitMilliseconds": (ProcessInfo.processInfo.systemUptime - committedAt) * 1000,
                    "frame": [sampled.minX, sampled.minY, sampled.width, sampled.height]])
            }
        }
        if trackingPointer {
            updateClock()
            return // Held material changes remain owned by the parent's release message.
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, duration - WindowFrostMaterialTiming.fadeDuration)) { [weak self] in
            guard let self, self.compositorToken == token else { return }
            self.beginFinalMaterial(trigger: "compositor-brake")
        }
        reportCompositorFrame(token)
    }

    private func reportCompositorFrame(_ token: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.compositorToken == token else { return }
            if let current = self.compositorFrame() { self.frame = current }
            self.reply("frame") // Input coverage follows the presentation, never the final model frame.
            self.reportCompositorFrame(token)
        }
    }

    @objc private func displayTick(_ sender: AnyObject) { tick() }

    private func updateClock() {
        guard WindowFrostClockPolicy.needsClock(animating: animating, compositorActive: compositorToken != nil,
                                               trackingPointer: compositorTracksPointer) else { stopClock(); return }
        if #available(macOS 14, *), let largest = surfaces.max(by: {
            let a = $0.bounds.intersection(frame), b = $1.bounds.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }) {
            var selected = largest
            if let current = surfaces.first(where: { $0.displayID == clockDisplayID }) {
                let oldArea = current.bounds.intersection(frame), newArea = largest.bounds.intersection(frame)
                // Avoid repeatedly replacing the clock during tiny seam crossings.
                if !oldArea.isNull && oldArea.width * oldArea.height * 1.1 >= newArea.width * newArea.height {
                    selected = current
                }
            }
            guard selected.displayID != clockDisplayID || stopDisplayLink == nil else { return }
            stopClock()
            let link = selected.screen.displayLink(target: self, selector: #selector(displayTick(_:)))
            let maximum = Float(max(1, selected.screen.maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            stopDisplayLink = { link.invalidate() }
            clockDisplayID = selected.displayID
            WindowFrostDiagnostics.event("overlay.clock", fields: ["kind": "display-link", "displayID": selected.displayID,
                "maximumFramesPerSecond": maximum])
        } else if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopClock() {
        stopDisplayLink?(); stopDisplayLink = nil; clockDisplayID = nil
        timer?.invalidate(); timer = nil
    }
    static func sample(_ curve: [Double], progress: Double) -> CGFloat {
        guard curve.count >= 2 else { return CGFloat(min(1, max(0, progress))) }
        let index = min(1, max(0, progress)) * Double(curve.count - 1)
        let lower = Int(index), upper = min(curve.count - 1, lower + 1)
        return CGFloat(min(1, max(0, curve[lower] + (curve[upper] - curve[lower]) * (index - Double(lower)))))
    }
    private func configureFinalMaterial(resizingUnderCover: Bool) {
        guard self.resizingUnderCover != resizingUnderCover else { return }
        self.resizingUnderCover = resizingUnderCover
        if finalMaterialToken != nil {
            // A final prepared-size readback may refine an earlier plan. Retarget
            // the tint and invalidate readiness until the new fade is presented.
            beginFinalMaterial(trigger: "placement-plan-changed", retarget: true)
        }
    }
    private func beginFinalMaterial(trigger: String, retarget: Bool = false) {
        guard finalMaterialToken == nil || retarget, !surfaces.isEmpty else { return }
        let token = UUID(), started = ProcessInfo.processInfo.systemUptime
        finalMaterialToken = token
        finalMaterialReady = false
        let tintAlpha = WindowFrostMaterialTiming.tintAlpha(resizingUnderCover: resizingUnderCover)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : WindowFrostMaterialTiming.fadeDuration
        WindowFrostDiagnostics.event("overlay.finalMaterial", fields: ["phase": "begin", "id": id,
            "trigger": trigger, "radius": 96, "tintAlpha": tintAlpha, "resizingUnderCover": resizingUnderCover,
            "durationMilliseconds": duration * 1000,
            "customSurfaceCount": surfaces.filter(\.customBackdrop).count, "surfaceCount": surfaces.count])
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for surface in surfaces {
                let color = surface.tintColor.withAlphaComponent(tintAlpha)
                surface.compositor?.setTint(color, duration: duration)
                surface.tint?.animator().fillColor = color
            }
        } completionHandler: { [weak self] in
            guard let self, self.finalMaterialToken == token, !self.surfaces.isEmpty else { return }
            // Motion and release now use the same live backdrop. Keep it intact;
            // stacking two translucent tints would briefly darken/lighten it.
            CATransaction.flush()
            // Do not let a short-circuited animation completion expose the real
            // window before the material has had its presentation opportunity.
            let remaining = max(0, started + duration - ProcessInfo.processInfo.systemUptime)
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 1.0 / 60) { [weak self] in
                guard let self, self.finalMaterialToken == token, !self.surfaces.isEmpty else { return }
                self.finalMaterialReady = true
                WindowFrostDiagnostics.event("overlay.finalMaterial", fields: ["phase": "ready", "id": self.id,
                    "tintAlpha": tintAlpha, "resizingUnderCover": self.resizingUnderCover,
                    "elapsedMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000])
                let acknowledge = self.pendingCover; self.pendingCover = nil
                acknowledge?()
            }
        }
    }
    /// The real window is already verified and its input/recovery ownership released.
    /// Fade only the disposable visuals; a new transition or input can remove them.
    private func beginDismissal() {
        stopCompositorMotion()
        animating = false; following = false; stopClock()
        guard !surfaces.isEmpty, dismissalID == nil else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { closePanels(reason: "accessibility-dismissal"); return }
        dismissal.begin(fade: { [weak self] duration, completion in
            guard let self else { return }
            self.traceDismissal("fade")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for surface in self.surfaces { surface.panel.animator().alphaValue = 0 }
            } completionHandler: { completion() }
        }, finish: { [weak self] timedOut in
            guard let self else { return }
            self.traceDismissal(timedOut ? "interrupted" : "complete")
            self.closePanels(reason: timedOut ? "dismissal-timeout" : "dismissal-complete")
        })
        let token = dismissalID
        traceDismissal("hold")
        dismissalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] _ in
            guard let self, self.dismissalID == token else { return }
            self.closePanels(reason: "dismissal-input")
        }
    }
    private func traceDismissal(_ phase: String) {
        WindowFrostDiagnostics.event("overlay.dismissal", fields: ["phase": phase, "id": id,
            "elapsedMilliseconds": (ProcessInfo.processInfo.systemUptime - dismissal.started) * 1000,
            "surfaceCount": surfaces.count])
    }
    private func closePanels(reason: String) {
        stopCompositorMotion()
        stopClock()
        if !surfaces.isEmpty {
            WindowFrostDiagnostics.event("overlay.close", fields: ["id": id, "sequence": sequence,
                "reason": reason, "windows": surfaces.map { $0.panel.windowNumber }])
        }
        if dismissalID != nil { traceDismissal("interrupted") }
        dismissal.invalidate()
        if let dismissalMonitor { NSEvent.removeMonitor(dismissalMonitor) }
        dismissalMonitor = nil
        ownedDrag = false; resizingUnderCover = false; finalMaterialToken = nil; finalMaterialReady = false; pendingCover = nil
        previewPointer = nil
        pendingFrameReport = nil
        surfaces.forEach { $0.panel.close() }
        surfaces.removeAll()
    }
    private func createPanels(frame: CGRect) -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        let displays = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (screen, number.uint32Value)
        }
        guard displays.contains(where: { WindowFrostSurfaceGeometry.intersects(frame, display: CGDisplayBounds($0.1)) }) else { return false }
        for (screen, displayID) in displays {
            let displayFrame = CGDisplayBounds(displayID)
            let panel = WindowFrostPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.appearance = blurAppearance.appearance
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.colorSpace = .sRGB
            panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false; panel.level = BlurPreviewStyle.movingWindowLevel
            panel.collectionBehavior = [.transient, .ignoresCycle]; panel.animationBehavior = .none
            let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
            root.appearance = blurAppearance.appearance
            root.wantsLayer = true; root.layer?.masksToBounds = true
            root.layer?.cornerRadius = BlurPreviewStyle.cornerRadius
            let dark = root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let color = (Defaults.footprintColor.typedValue?.nsColor ?? (dark ? .black : .white)).withAlphaComponent(0.5)
            let host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let shape = NSView(frame: .zero)
            shape.wantsLayer = true
            shape.layer?.contentsFormat = .RGBA8Uint
            if #available(macOS 26, *) { shape.layer?.preferredDynamicRange = .standard }
            else if #available(macOS 14, *) { shape.layer?.wantsExtendedDynamicRangeContent = false }
            host.addSubview(shape); shape.addSubview(root)
            panel.contentView = host
            var compositor: WindowFrostCompositorSurface?
            var fallbackShadow: BlurPreviewShadow?
            var fallbackTint: NSBox?
            var customBackdrop = true
            if let backdrop = RectangleCreateFrostBackdropLayer(root.bounds, 96) {
                compositor = WindowFrostCompositorSurface(backdrop: backdrop,
                    radius: root.layer?.cornerRadius ?? 5, color: color,
                    borderColor: BlurPreviewStyle.borderColor(isDark: dark), borderWidth: BlurPreviewStyle.borderWidth,
                    shadowOpacity: BlurPreviewStyle.shadowOpacity(isDark: dark))
                host.wantsLayer = true
                host.layer?.addSublayer(compositor!.tracking)
                shape.isHidden = true
            } else {
                let material = makeMaterial(frame: root.bounds, cornerRadius: root.layer?.cornerRadius ?? 5, dark: dark)
                root.addSubview(material.view)
                prepareSDR(root)
                fallbackTint = material.tint
                customBackdrop = material.custom
                let shadow = BlurPreviewShadow()
                shadow.shape.shadowOpacity = BlurPreviewStyle.shadowOpacity(isDark: dark)
                shape.layer?.addSublayer(shadow.container)
                fallbackShadow = shadow
            }
            surfaces.append(Surface(screen: screen, displayID: displayID, bounds: displayFrame, panel: panel, shape: shape, clipped: root,
                                    tint: fallbackTint, tintColor: color, customBackdrop: customBackdrop, compositor: compositor,
                                    fallbackShadow: fallbackShadow))
        }
        self.frame = .zero
        WindowFrostDiagnostics.event("overlay.surfacePreparation", fields: ["id": id, "surfaceCount": surfaces.count,
            "fallbackMaterialCount": surfaces.filter { $0.tint != nil }.count,
            "elapsedMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000])
        return !surfaces.isEmpty
    }
    private func makeMaterial(frame: CGRect, cornerRadius: CGFloat, dark: Bool) -> (view: NSView, tint: NSBox, custom: Bool) {
        let container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        prepareSDR(container)
        let custom = RectangleCreateFrostBackdrop(container.bounds, 96)
        let effect = custom ?? NSVisualEffectView(frame: container.bounds)
        if custom == nil {
            effect.material = .fullScreenUI; effect.blendingMode = .behindWindow; effect.state = .active
        }
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)
        let tint = NSBox(frame: container.bounds)
        tint.boxType = .custom; tint.cornerRadius = cornerRadius
        tint.borderColor = BlurPreviewStyle.borderColor(isDark: dark)
        tint.borderWidth = BlurPreviewStyle.borderWidth
        tint.fillColor = (Defaults.footprintColor.typedValue?.nsColor ?? (dark ? .black : .white)).withAlphaComponent(0.5)
        tint.autoresizingMask = [.width, .height]
        prepareSDR(tint)
        container.addSubview(tint)
        return (container, tint, custom != nil)
    }
    private func prepareSDR(_ view: NSView) {
        view.wantsLayer = true; view.layer?.contentsFormat = .RGBA8Uint
        if #available(macOS 26, *) { view.layer?.preferredDynamicRange = .standard }
        else if #available(macOS 14, *) { view.layer?.wantsExtendedDynamicRangeContent = false }
    }
    private func render(_ frame: CGRect) {
        // An animation can start at its current frame; it still needs its clock.
        defer { updateClock() }
        guard self.frame != frame, !surfaces.isEmpty else { return }
        self.frame = frame
        // Each host remains on its own display. All fragments share one global
        // shape frame and one transaction, preserving corners across the seam.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateSurfaceVisibility(for: frame)
        for surface in surfaces {
            if let compositor = surface.compositor {
                compositor.setFrame(WindowFrostSurfaceGeometry.localFrame(frame, display: surface.bounds))
                continue
            }
            let shape = surface.shape, clipped = surface.clipped
            shape.frame = WindowFrostSurfaceGeometry.localFrame(frame, display: surface.bounds)
            if clipped.frame.size != shape.bounds.size {
                clipped.frame = shape.bounds
            }
            surface.fallbackShadow?.setSize(shape.bounds.size)
        }
        CATransaction.commit()
    }

    private func updateSurfaceVisibility(for frame: CGRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for surface in surfaces {
            let hidden = !WindowFrostSurfaceGeometry.intersects(frame, display: surface.bounds)
            if let compositor = surface.compositor { compositor.root.isHidden = hidden }
            else { surface.shape.isHidden = hidden }
        }
        CATransaction.commit()
    }
    private func reply(_ event: String) {
        var message: [String: Any] = ["event": event, "id": id, "sequence": sequence,
                                    "frame": [frame.minX, frame.minY, frame.width, frame.height]]
        if let first = surfaces.first { message["windowNumber"] = first.panel.windowNumber }
        if event == "frame" || event == "grabbed" {
            WindowFrostDiagnostics.event("overlay.presentation", fields: message)
        }
        if event == "shown" || event == "covered" {
            let fragments: [[String: Any]] = surfaces.map { surface in
                ["displayID": surface.displayID, "windowNumber": surface.panel.windowNumber,
                 "displayFrame": [surface.bounds.minX, surface.bounds.minY, surface.bounds.width, surface.bounds.height],
                 "visible": surface.panel.isVisible,
                 "contentVisible": !(surface.compositor?.root.isHidden ?? surface.shape.isHidden)]
            }
            message["surfaces"] = fragments
            WindowFrostDiagnostics.event("overlay.surfaces", fields: ["eventKind": event, "id": id,
                "sequence": sequence, "surfaces": fragments,
                "globalFrame": [frame.minX, frame.minY, frame.width, frame.height]])
        }
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10)
        if !frostWrite(data, to: STDOUT_FILENO) { exit(0) }
    }
}

private func frostWrite(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return true }
        var offset = 0
        while offset < buffer.count {
            let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
            if written < 0 && errno == EINTR { continue }
            guard written > 0 else { return false }
            offset += written
        }
        return true
    }
}
