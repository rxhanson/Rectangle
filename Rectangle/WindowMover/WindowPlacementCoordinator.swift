import Cocoa

/// Ordinary snap movers and animation share one final readback check. A
/// placement commits only after AX and WindowServer agree on its actual size
/// and snap alignment.
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
            guard !isCancelled else { return nil }
            return body()
        }
    }

    static let shared = WindowPlacementCoordinator()
    private var active: [AccessibilityElement: Cancellation] = [:]
    private let windowManager = WindowManager()

    func cancel(_ window: AccessibilityElement) {
        active.removeValue(forKey: window)?.cancel()
        WindowAnimator.shared.cancel(for: window)
    }

    func cancelAll() {
        for window in Array(active.keys) { cancel(window) }
    }

    @discardableResult func place(_ result: ResultParameters, from original: CGRect,
                                 placement: WindowAnimationPlacement, animated: Bool,
                                 profile: WindowAnimationProfile = .standard,
                                 acknowledgementTimeout: TimeInterval = 3.4, restoreOnFailure: Bool = true,
                                 isCurrent: @escaping () -> Bool,
                                 completion: @escaping (Outcome) -> Void) -> Cancellation {
        let window = result.windowElement
        let target = result.calcResult.rect.screenFlipped
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
        let verify: () -> Void = {
            guard !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
            let preferred = window.axElement
            WindowAnimator.shared.performPlacementWork {
                let worker = WindowPlacementWorker(pid: pid, id: id, launch: launch,
                    preferred: preferred, cancellation: cancellation)
                let outcome = worker.place(target, original: original, placement: placement,
                    acknowledgementTimeout: acknowledgementTimeout, restoreOnFailure: restoreOnFailure)
                DispatchQueue.main.async { finish(outcome) }
            }
        }
        let snap: () -> Void = { [self] in
            guard !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
            // Use the ordinary snap chain for fixed, maximum-size and aspect-ratio
            // windows. Verification accepts the size the application actually allows.
            windowManager.moveWindow(toRect: result.calcResult.rect, result: result)
            verify()
        }
        if animated && WindowAnimator.enabled && !result.isFixedSize {
            WindowAnimator.shared.animate(window, from: original, to: target, placement: placement,
                                          profile: profile) { frame in
                if frame.isNull { WindowAnimator.shared.afterPendingWrites(snap) }
                else { verify() }
            }
        } else {
            WindowAnimator.shared.afterPendingWrites(snap)
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
    let preferred: AXUIElement
    private var window: AccessibilityElement?
    private var timedOut = false

    init(pid: pid_t, id: CGWindowID, launch: TimeInterval, preferred: AXUIElement,
         cancellation: WindowPlacementCoordinator.Cancellation) {
        self.pid = pid; self.id = id; self.launch = launch; self.cancellation = cancellation
        self.preferred = preferred
    }

    private var valid: Bool {
        !cancellation.isCancelled && WindowProcessIdentity.launchTime(for: pid) == launch
    }

    func place(_ target: CGRect, original: CGRect, placement: WindowAnimationPlacement,
               acknowledgementTimeout: TimeInterval = 3.4, restoreOnFailure: Bool = true) -> WindowPlacementCoordinator.Outcome {
        guard valid else { return .cancelled }
        if let element = WindowAccessibilityLookup.resolve(pid: pid, id: id, launch: launch,
            preferred: preferred, isCurrent: { self.valid }) {
            window = AccessibilityElement(element, messagingTimeout: 0.05, windowID: id)
        }
        guard let window else {
            WindowAnimationDiagnostics.event("placement-unresponsive", fields: ["windowID": id,
                "operation": "lookup"])
            return valid ? .unresponsive : .cancelled
        }
        window.setMessagingTimeout(0.05)
        let start = ProcessInfo.processInfo.systemUptime
        if let frame = settle(target, bounds: placement.screenFrame, deadline: start + acknowledgementTimeout,
                              placement: placement) {
            return .placed(frame)
        }
        guard valid else { return .cancelled }
        if timedOut {
            WindowAnimationDiagnostics.event("placement-unresponsive", fields: ["windowID": id,
                "operation": "acknowledgement"])
            return .unresponsive
        }
        guard restoreOnFailure else { return .failed(restored: false) }
        // Restoration has its own finite budget. It is still owned by the same
        // token, so a new drag or command can interrupt it before any next write.
        let restored = settle(original, bounds: placement.screenFrame, deadline: ProcessInfo.processInfo.systemUptime + 2.2) != nil
        guard valid else { return .cancelled }
        return .failed(restored: restored)
    }

    private func agreedFrame() -> CGRect? {
        guard valid, let window else { return nil }
        let frame = window.frame
        if frame.isNull {
            if !timedOut {
                WindowAnimationDiagnostics.event("placement-ack-timeout", fields: ["windowID": id, "operation": "frame-read"])
            }
            timedOut = true; return nil
        }
        timedOut = false
        guard valid, let server = WindowUtil.getWindowFrame(id: id),
              WindowAnimationGeometry.valid(frame), WindowAnimationGeometry.near(frame, server, tolerance: 1) else { return nil }
        return frame
    }

    private func settle(_ target: CGRect, bounds: CGRect, deadline: TimeInterval,
                        placement: WindowAnimationPlacement? = nil) -> CGRect? {
        guard let window else { return nil }
        var state = WindowPlacementAcknowledgement(target: target, startedAt: ProcessInfo.processInfo.systemUptime,
                                                    pendingWrite: false, bounds: bounds, placement: placement)
        while valid && ProcessInfo.processInfo.systemUptime < deadline {
            let now = ProcessInfo.processInfo.systemUptime
            let frame = agreedFrame()
            switch state.observe(frame, at: now) {
            case .complete(let frame): return frame
            case .position(let point):
                guard let result = cancellation.write({ window.writePosition(point) }) else { return nil }
                if result == .cannotComplete {
                    WindowAnimationDiagnostics.event("placement-ack-timeout", fields: ["windowID": id, "operation": "position-write"])
                    timedOut = true
                }
                // A timed-out write may still have been applied. Let readback
                // acknowledge it before the existing bounded retry can resend.
                guard result == .success || result == .cannotComplete else { return nil }
            case .size(let size):
                guard let result = cancellation.write({ window.writeSize(size) }) else { return nil }
                if result == .cannotComplete {
                    WindowAnimationDiagnostics.event("placement-ack-timeout", fields: ["windowID": id, "operation": "size-write"])
                    timedOut = true
                }
                guard result == .success || result == .cannotComplete else { return nil }
            case .failed: return nil
            case .waiting: break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }
}

/// Accept the app's actual size after the mover finishes, including size limits
/// and aspect ratios, then verify snap alignment. Rollback requires the exact
/// original frame.
struct WindowPlacementAcknowledgement {
    enum Decision { case waiting, position(CGPoint), size(CGSize), complete(CGRect), failed }
    let target: CGRect
    let bounds: CGRect?
    private let placement: WindowAnimationPlacement?
    private var waitingUntil: TimeInterval
    private var positionWrites = 0
    private var sizeWrites = 0
    private var stableAt: TimeInterval?
    private var stableFrame: CGRect?

    init(target: CGRect, startedAt: TimeInterval, pendingWrite: Bool, bounds: CGRect? = nil,
         placement: WindowAnimationPlacement? = nil) {
        self.target = target
        self.bounds = bounds
        self.placement = placement
        waitingUntil = startedAt + (pendingWrite ? 0.65 : 0)
    }

    mutating func observe(_ frame: CGRect?, at now: TimeInterval) -> Decision {
        guard let frame, WindowAnimationGeometry.valid(frame) else {
            stableAt = nil; stableFrame = nil
            return .waiting
        }
        let expected = placement?.frame(for: target, actualSize: frame.size, origin: frame, progress: 1) ?? target
        if WindowAnimationGeometry.near(frame, expected, tolerance: 1) {
            if let stableFrame, WindowAnimationGeometry.near(frame, stableFrame, tolerance: 1),
               let stableAt, now - stableAt >= 0.02 { return .complete(frame) }
            if stableFrame.map({ WindowAnimationGeometry.near(frame, $0, tolerance: 1) }) != true {
                stableFrame = frame; stableAt = now
            }
            return .waiting
        }
        stableAt = nil; stableFrame = nil
        guard now >= waitingUntil else { return .waiting }
        let needsPosition = abs(frame.minX - expected.minX) > 1 || abs(frame.minY - expected.minY) > 1
        let needsSize = abs(frame.width - expected.width) > 1 || abs(frame.height - expected.height) > 1
        // Snap verification never resizes. Only an exact rollback can request
        // size, using the same write order as the ordinary immediate mover.
        if needsSize, ImmediateFrameOrder.sizeFirst(from: frame, to: expected,
            bounds: bounds ?? frame.union(expected), acrossScreens: false, preferSizeFirst: true) || !needsPosition {
            guard sizeWrites < 2 else { return .failed }
            sizeWrites += 1; waitingUntil = now + 0.65
            return .size(expected.size)
        }
        if needsPosition {
            guard positionWrites < 2 else { return .failed }
            positionWrites += 1; waitingUntil = now + 0.65
            return .position(expected.origin)
        }
        return .failed
    }
}
