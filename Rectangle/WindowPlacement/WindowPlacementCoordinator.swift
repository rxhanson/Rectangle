import Cocoa

/// Commit placement only when AX and WindowServer agree on the frame.
/// Recheck completed animations; retry other placements within a fixed deadline.
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
                                 acknowledgementTimeout: TimeInterval = 3.4, restoreOnFailure: Bool = true,
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
        let directPlacement = !animated || !WindowAnimator.enabled
        let minimumHint = directPlacement ? window.rememberedMinimumSize : nil
        let verify: (CGRect?) -> Void = { animatedFrame in
            guard !cancellation.isCancelled, isCurrent() else { finish(.cancelled); return }
            let evidence = animatedFrame.flatMap {
                WindowPlacementAnimationEvidence(frame: $0, original: original, target: target,
                    placement: placement, completedAt: ProcessInfo.processInfo.systemUptime)
            }
            let preferred = window.axElement
            WindowAnimator.shared.performPlacementWork {
                let worker = WindowPlacementWorker(pid: pid, id: id, launch: launch,
                    preferred: preferred, cancellation: cancellation)
                let result = worker.place(target, original: original, placement: placement, animationEvidence: evidence,
                    directPlacement: directPlacement, minimumHint: minimumHint,
                    acknowledgementTimeout: acknowledgementTimeout, restoreOnFailure: restoreOnFailure)
                DispatchQueue.main.async { finish(result) }
            }
        }
        if animated && WindowAnimator.enabled {
            WindowAnimator.shared.afterPendingWrites(isCurrent: { !cancellation.isCancelled && isCurrent() },
                onCancelled: { finish(.cancelled) }) {
                WindowAnimator.shared.animate(window, from: original, to: target, placement: placement,
                                              profile: profile) { verify($0.isNull ? nil : $0) }
            }
        } else {
            WindowAnimator.shared.afterPendingWrites { verify(nil) }
        }
        return cancellation
    }
}
