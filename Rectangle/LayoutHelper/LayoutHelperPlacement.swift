import Cocoa

/// Ordinary snap movers and animation share one final readback check. A
/// placement commits only after AX and WindowServer agree on its actual size
/// and snap alignment.
final class LayoutHelperPlacement {
    typealias Outcome = WindowPlacementCoordinator.Outcome
    typealias Cancellation = WindowPlacementCoordinator.Cancellation

    static let shared = LayoutHelperPlacement()
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
                                 placement: ImmediateWindowPlacement, animated: Bool,
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
              WindowGeometry.valid(original), WindowGeometry.valid(target) else {
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
            WindowWriteQueue.shared.perform {
                let worker = WindowPlacementWorker(pid: pid, id: id, launch: launch,
                    preferred: preferred, cancellation: cancellation)
                let outcome = worker.place(target, original: original, placement: placement,
                    acknowledgementTimeout: acknowledgementTimeout, restoreOnFailure: restoreOnFailure, acceptsSettledSize: true)
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
            WindowAnimator.shared.animate(window, from: original, to: target, placement: WindowAnimationPlacement(screenFrame: placement.screenFrame,
                    sharedEdges: placement.sharedEdges, constrainToScreen: placement.constrainToScreen, gap: placement.gap),
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
