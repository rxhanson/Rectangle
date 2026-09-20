import Cocoa

/// A placement commits only after both window APIs agree. A successful animation
/// hands its verified frame to a short readback check; other paths retry within
/// a bounded acknowledgement phase.
final class WindowPlacementCoordinator {
    enum Outcome {
        case placed(CGRect)
        case unresponsive
        case failed(restored: Bool)
        case cancelled
    }

    final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        var timer: Timer?
        var onCancel: (() -> Void)?
        func cancel() {
            lock.lock(); let wasCancelled = cancelled; cancelled = true; lock.unlock()
            timer?.invalidate(); timer = nil
            if !wasCancelled { onCancel?(); onCancel = nil }
        }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func write(_ body: () -> AXError) -> AXError? {
            lock.lock(); defer { lock.unlock() }
            return cancelled ? nil : body()
        }
    }

    static let shared = WindowPlacementCoordinator()
    private var active: [AccessibilityElement: Cancellation] = [:]

    func cancel(_ window: AccessibilityElement) {
        active.removeValue(forKey: window)?.cancel()
        WindowAnimator.shared.cancel(for: window)
    }

    func cancelAll() {
        for window in Array(active.keys) { cancel(window) }
    }

    @discardableResult func place(_ window: AccessibilityElement, from original: CGRect, to target: CGRect,
                                 placement: WindowAnimationPlacement, animated: Bool,
                                 profile: WindowAnimationProfile = .standard,
                                 isCurrent: @escaping () -> Bool,
                                 completion: @escaping (Outcome) -> Void) -> Cancellation {
        cancel(window)
        let cancellation = Cancellation()
        active[window] = cancellation
        cancellation.onCancel = { completion(.cancelled) }
        guard let pid = window.pid, let id = window.windowId,
              let launch = WindowProcessIdentity.launchTime(for: pid),
              WindowAnimationGeometry.valid(original), WindowAnimationGeometry.valid(target) else {
            active.removeValue(forKey: window)
            completion(.failed(restored: false))
            return cancellation
        }
        // The main owner checks session, input generation, screen geometry and
        // neighbour validity. Workers never read layout or shared AX caches.
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            if !isCurrent() { self?.cancel(window) }
        }
        RunLoop.main.add(timer, forMode: .common)
        cancellation.timer = timer
        let finish: (Outcome) -> Void = { [weak self] result in
            timer.invalidate()
            cancellation.onCancel = nil
            guard let self, self.active[window] === cancellation else { return }
            self.active.removeValue(forKey: window)
            guard !cancellation.isCancelled else { return }
            guard isCurrent() else { completion(.cancelled); return }
            completion(result)
        }
        let verify: (CGRect?) -> Void = { animatedFrame in
            guard !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
            let evidence = animatedFrame.flatMap {
                WindowPlacementAnimationEvidence(frame: $0, original: original, target: target,
                    placement: placement, completedAt: ProcessInfo.processInfo.systemUptime)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let worker = WindowPlacementWorker(pid: pid, id: id, launch: launch,
                    cancellation: cancellation)
                let result = worker.place(target, original: original, placement: placement, animationEvidence: evidence)
                DispatchQueue.main.async { finish(result) }
            }
        }
        if animated && WindowAnimator.enabled {
            WindowAnimator.shared.animate(window, from: original, to: target, placement: placement,
                                          profile: profile) { verify($0) }
        } else {
            verify(nil)
        }
        return cancellation
    }
}

/// Serial writes wait for acknowledgement before advancing to the next property.
/// In particular a delayed size write must not be replaced by a position write
/// built from the app's old size. No observation in this phase learns a minimum.
private final class WindowPlacementWorker {
    let pid: pid_t
    let id: CGWindowID
    let launch: TimeInterval
    let cancellation: WindowPlacementCoordinator.Cancellation
    private var window: AccessibilityElement?
    private var timedOut = false

    init(pid: pid_t, id: CGWindowID, launch: TimeInterval, cancellation: WindowPlacementCoordinator.Cancellation) {
        self.pid = pid; self.id = id; self.launch = launch; self.cancellation = cancellation
    }

    private var valid: Bool {
        !cancellation.isCancelled && WindowProcessIdentity.launchTime(for: pid) == launch
    }

    func place(_ target: CGRect, original: CGRect, placement: WindowAnimationPlacement,
               animationEvidence: WindowPlacementAnimationEvidence? = nil) -> WindowPlacementCoordinator.Outcome {
        guard valid else { return .cancelled }
        let reader = AccessibilityReadBatch(budget: 0.15)
        let application = AXUIElementCreateApplication(pid)
        let elements = reader.value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let element = elements.first(where: { reader.windowID($0) == id }), reader.available {
            window = AccessibilityElement(element, messagingTimeout: 0.05, windowID: id)
        }
        guard let window else { return valid ? .unresponsive : .cancelled }
        window.setMessagingTimeout(0.05)
        let start = ProcessInfo.processInfo.systemUptime
        if let frame = settle(target, bounds: placement.screenFrame, deadline: start + 3.4,
                              placement: placement, original: original, animationEvidence: animationEvidence) {
            return .placed(frame)
        }
        guard valid else { return .cancelled }
        if timedOut { return .unresponsive }
        // Restoration has its own finite budget. It is still owned by the same
        // token, so a new drag or command can interrupt it before any next write.
        let restored = settle(original, bounds: placement.screenFrame, deadline: ProcessInfo.processInfo.systemUptime + 2.2) != nil
        guard valid else { return .cancelled }
        return .failed(restored: restored)
    }

    private func agreedFrame() -> CGRect? {
        guard valid, let window else { return nil }
        let frame = window.frame
        if frame.isNull { timedOut = true; return nil }
        guard valid, let server = WindowUtil.getWindowFrame(id: id),
              WindowAnimationGeometry.valid(frame), WindowAnimationGeometry.near(frame, server, tolerance: 1) else { return nil }
        return frame
    }

    private func settle(_ target: CGRect, bounds: CGRect, deadline: TimeInterval,
                        placement: WindowAnimationPlacement? = nil, original: CGRect? = nil,
                        animationEvidence: WindowPlacementAnimationEvidence? = nil) -> CGRect? {
        guard let window else { return nil }
        var state = WindowPlacementAcknowledgement(target: target, startedAt: ProcessInfo.processInfo.systemUptime,
                                                    pendingWrite: false, bounds: bounds, placement: placement, original: original,
                                                    reportedMinimum: window.reportedMinimumSize, animationEvidence: animationEvidence)
        while valid && ProcessInfo.processInfo.systemUptime < deadline {
            let now = ProcessInfo.processInfo.systemUptime
            let frame = agreedFrame()
            if timedOut { return nil }
            switch state.observe(frame, at: now) {
            case .complete(let frame): return frame
            case .position(let point):
                guard let result = cancellation.write({ window.writeAnimationPosition(point) }) else { return nil }
                if result == .cannotComplete { timedOut = true; return nil }
                guard result == .success else { return nil }
            case .size(let size):
                guard let result = cancellation.write({ window.writeAnimationSize(size) }) else { return nil }
                if result == .cannotComplete { timedOut = true; return nil }
                guard result == .success else { return nil }
            case .failed: return nil
            case .waiting: break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }
}

/// Evidence belongs only to this completed animation and its destination. It
/// never becomes a learned minimum or survives a newer placement operation.
struct WindowPlacementAnimationEvidence {
    let frame: CGRect
    let target: CGRect
    let placement: WindowAnimationPlacement
    let completedAt: TimeInterval

    init?(frame: CGRect, original: CGRect, target: CGRect, placement: WindowAnimationPlacement,
          completedAt: TimeInterval) {
        guard WindowAnimationGeometry.valid(frame), WindowAnimationGeometry.valid(original),
              WindowAnimationGeometry.valid(target), completedAt.isFinite,
              frame.width >= target.width - 1, frame.height >= target.height - 1,
              WindowAnimationGeometry.near(frame,
                placement.frame(for: target, actualSize: frame.size, origin: original, progress: 1), tolerance: 1),
              WindowAnimationGeometry.near(frame, target, tolerance: 1)
                || !WindowAnimationGeometry.near(frame, original, tolerance: 1) else { return nil }
        self.frame = frame; self.target = target; self.placement = placement; self.completedAt = completedAt
    }

    func isCurrent(target: CGRect, placement: WindowAnimationPlacement?, at time: TimeInterval) -> Bool {
        self.target == target && self.placement == placement && time >= completedAt && time - completedAt <= 0.25
    }
}

/// Pure state makes slow acknowledgements and write ordering testable without
/// sleeping or moving a real window. Size requests receive at most two retries;
/// an unchanged size without reported constraints gets one bounded growth probe.
struct WindowPlacementAcknowledgement {
    enum Decision { case waiting, position(CGPoint), size(CGSize), complete(CGRect), failed }
    let target: CGRect
    let bounds: CGRect?
    private var waitingUntil: TimeInterval
    private var pending: Decision = .waiting
    private var positionWrites = 0
    private var sizeWrites = 0
    private var stableAt: TimeInterval?
    private let placement: WindowAnimationPlacement?
    private let original: CGRect?
    private let reportedMinimum: CGSize?
    private var previousSize: CGSize?
    private var sizeStableAt: TimeInterval?
    private var resizeResponded = false
    private var probeAttempted = false
    private var probeSize: CGSize?
    private var probePosition: CGPoint?
    private var acceptedSize: CGSize?
    private var animationEvidence: WindowPlacementAnimationEvidence?

    init(target: CGRect, startedAt: TimeInterval, pendingWrite: Bool, bounds: CGRect? = nil,
         placement: WindowAnimationPlacement? = nil, original: CGRect? = nil, reportedMinimum: CGSize? = nil,
         animationEvidence: WindowPlacementAnimationEvidence? = nil) {
        self.target = target
        self.bounds = bounds
        self.placement = placement
        self.original = original
        self.reportedMinimum = reportedMinimum
        self.animationEvidence = animationEvidence
        waitingUntil = startedAt + (pendingWrite ? 0.65 : 0)
    }

    mutating func observe(_ frame: CGRect?, at now: TimeInterval) -> Decision {
        if let evidence = animationEvidence,
           !evidence.isCurrent(target: target, placement: placement, at: now) {
            animationEvidence = nil
            stableAt = nil
        }
        guard let frame, WindowAnimationGeometry.valid(frame) else {
            stableAt = nil; sizeStableAt = nil; previousSize = nil
            return .waiting
        }
        if let evidence = animationEvidence {
            if WindowAnimationGeometry.near(frame, evidence.frame, tolerance: 1) {
                // observe receives only fresh, agreeing AX/WindowServer frames.
                // Reuse the animation's resize retries instead of repeating them
                // or visibly probing a window that has already settled.
                if let stableAt, now - stableAt >= 0.04 { return .complete(frame) }
                if stableAt == nil { stableAt = now }
                return .waiting
            }
            animationEvidence = nil
            stableAt = nil
        }
        if let original, !sameSize(frame.size, original.size) { resizeResponded = true }
        if let previousSize, !sameSize(frame.size, previousSize) { resizeResponded = true }
        if previousSize.map({ sameSize($0, frame.size) }) != true { sizeStableAt = now }
        previousSize = frame.size
        if let acceptedSize, !sameSize(frame.size, acceptedSize) {
            self.acceptedSize = nil
            stableAt = nil
        }
        if let acceptedSize {
            guard let placement else { return .failed }
            let aligned = placement.frame(for: target, actualSize: acceptedSize, origin: frame, progress: 1)
            if WindowAnimationGeometry.near(frame, aligned, tolerance: 1) {
                if let stableAt, now - stableAt >= 0.02 { return .complete(frame) }
                stableAt = now
                return .waiting
            }
            stableAt = nil
            guard now >= waitingUntil else { return .waiting }
            guard positionWrites < 2 else { return .failed }
            positionWrites += 1
            waitingUntil = now + 0.65
            return .position(aligned.origin)
        }
        let positionMatches = abs(frame.minX - target.minX) <= 1 && abs(frame.minY - target.minY) <= 1
        let sizeMatches = abs(frame.width - target.width) <= 1 && abs(frame.height - target.height) <= 1
        if positionMatches && sizeMatches {
            if let stableAt, now - stableAt >= 0.02 { return .complete(frame) }
            stableAt = now
            return .waiting
        }
        stableAt = nil
        switch pending {
        case .position(let point):
            if abs(frame.minX - point.x) <= 1 && abs(frame.minY - point.y) <= 1 { waitingUntil = now; pending = .waiting }
        case .size(let requested):
            if sameSize(frame.size, requested) {
                if probeSize != nil { resizeResponded = true; probeSize = nil }
                waitingUntil = now; pending = .waiting
            }
        default: break
        }
        guard now >= waitingUntil else { return .waiting }
        if let point = probePosition, let probeSize {
            guard abs(frame.minX - point.x) <= 1, abs(frame.minY - point.y) <= 1 else { return .failed }
            probePosition = nil
            pending = .size(probeSize); waitingUntil = now + 0.65
            return pending
        }
        if probeSize != nil { return .failed }
        var position = target.origin
        if !sizeMatches, let bounds {
            // Reserve room for the larger size on each axis, including growth.
            // This prevents Dock/edge clipping from masquerading as a minimum.
            position.x = min(max(position.x, bounds.minX), max(bounds.minX, bounds.maxX - max(frame.width, target.width)))
            position.y = min(max(position.y, bounds.minY), max(bounds.minY, bounds.maxY - max(frame.height, target.height)))
        }
        let needsPosition = abs(frame.minX - position.x) > 1 || abs(frame.minY - position.y) > 1
        if needsPosition && (positionWrites == 0 || sizeMatches) {
            guard positionWrites < 2 else { return .failed }
            positionWrites += 1
            pending = .position(position)
        } else if !sizeMatches {
            if sizeWrites >= 2 {
                guard let placement, frame.width >= target.width - 1, frame.height >= target.height - 1 else { return .failed }
                guard let sizeStableAt, now - sizeStableAt >= 0.12 else { return .waiting }
                let reported = reportedMinimum.map {
                    (frame.width <= target.width + 1 || abs($0.width - frame.width) <= 1)
                        && (frame.height <= target.height + 1 || abs($0.height - frame.height) <= 1)
                } ?? false
                if !resizeResponded && !reported {
                    // A successful AX return alone does not prove a resize was
                    // honored. Verify responsiveness before accepting a plateau.
                    guard !probeAttempted else { return .failed }
                    let probe = CGSize(width: frame.width + (frame.width > target.width + 1 ? 2 : 0),
                                       height: frame.height + (frame.height > target.height + 1 ? 2 : 0))
                    guard !placement.constrainToScreen
                        || (probe.width <= placement.screenFrame.width
                            && probe.height <= placement.screenFrame.height) else { return .failed }
                    probeAttempted = true; probeSize = probe; sizeWrites = 1
                    var point = frame.origin
                    if placement.constrainToScreen {
                        point.x = min(max(point.x, placement.screenFrame.minX), placement.screenFrame.maxX - probe.width)
                        point.y = min(max(point.y, placement.screenFrame.minY), placement.screenFrame.maxY - probe.height)
                    }
                    if abs(frame.minX - point.x) > 1 || abs(frame.minY - point.y) > 1 {
                        probePosition = point
                        pending = .position(point)
                    } else { pending = .size(probe) }
                    waitingUntil = now + 0.65
                    return pending
                }
                acceptedSize = frame.size
                waitingUntil = now
                return observe(frame, at: now)
            }
            sizeWrites += 1
            pending = .size(target.size)
        } else { return .failed }
        waitingUntil = now + 0.65
        return pending
    }

    private func sameSize(_ first: CGSize, _ second: CGSize) -> Bool {
        abs(first.width - second.width) <= 1 && abs(first.height - second.height) <= 1
    }
}
