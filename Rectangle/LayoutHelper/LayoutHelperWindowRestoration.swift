import Cocoa
import ScreenCaptureKit

/// Try the target geometry before restoring, then acknowledge the restored
/// state and fresh geometry before the ordinary snap's final verification.
enum LayoutHelperWindowRestoration {
    static func restore(_ window: AccessibilityElement, target: CGRect? = nil, original: CGRect? = nil, isCurrent: @escaping () -> Bool,
                        completion: @escaping (WindowPlacementCoordinator.Outcome) -> Void) -> WindowPlacementCoordinator.Cancellation {
        let cancellation = WindowPlacementCoordinator.Cancellation()
        let timer = Timer(timeInterval: 0.025, repeats: true) { _ in
            if !isCurrent() { cancellation.cancel() }
        }
        cancellation.timer = timer
        cancellation.onCancel = { completion(.cancelled) }
        RunLoop.main.add(timer, forMode: .common)
        guard let pid = window.pid, let id = window.windowId,
              let launch = WindowProcessIdentity.launchTime(for: pid) else {
            timer.invalidate(); cancellation.onCancel = nil
            completion(.failed(restored: false)); return cancellation
        }
        let preferred = window.axElement
        WindowAnimator.shared.performPlacementWork {
            let valid = { !cancellation.isCancelled && WindowProcessIdentity.launchTime(for: pid) == launch }
            let outcome: WindowPlacementCoordinator.Outcome
            if let element = WindowAccessibilityLookup.resolve(pid: pid, id: id, launch: launch,
                preferred: preferred, isCurrent: valid) {
                let worker = AccessibilityElement(element, messagingTimeout: 0.05, windowID: id)
                if let target, worker.isResizable(), worker.isSystemDialog != true {
                    _ = prepare(target: target, isCurrent: valid, minimized: { worker.isMinimized },
                        size: { requested in cancellation.write { worker.writeSize(requested) } ?? .failure },
                        position: { requested in cancellation.write { worker.writePosition(requested) } ?? .failure },
                        frame: { worker.frame })
                }
                let acknowledged = acknowledge(isCurrent: valid, minimized: { worker.isMinimized }, restore: {
                    cancellation.write { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) } ?? .failure
                }, frame: {
                    let frame = worker.frame
                    guard WindowAnimationGeometry.valid(frame), let server = WindowUtil.getWindowFrame(id: id),
                          WindowAnimationGeometry.near(frame, server, tolerance: 1) else { return nil }
                    return frame
                })
                switch acknowledged {
                case .failed, .unresponsive:
                    if let original {
                        _ = rollback(original: original, isCurrent: valid,
                            size: { requested in cancellation.write { worker.writeSize(requested) } ?? .failure },
                            position: { requested in cancellation.write { worker.writePosition(requested) } ?? .failure })
                    }
                case .placed, .cancelled: break
                }
                outcome = acknowledged
            } else { outcome = valid() ? .unresponsive : .cancelled }
            DispatchQueue.main.async {
                timer.invalidate(); cancellation.timer = nil; cancellation.onCancel = nil
                guard !cancellation.isCancelled else { return }
                completion(isCurrent() ? outcome : .cancelled)
            }
        }
        return cancellation
    }

    /// Place the window while it is still in the Dock, so the native restore
    /// animation can end at the target. Refusal or a slow reply falls back to
    /// restoring first; the ordinary placement still verifies the final frame.
    static func prepare(target: CGRect, isCurrent: () -> Bool, minimized: () -> Bool?,
                        size: (CGSize) -> AXError, position: (CGPoint) -> AXError,
                        frame: () -> CGRect?, now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                        pause: () -> Void = { Thread.sleep(forTimeInterval: 0.025) }) -> Bool {
        guard WindowAnimationGeometry.valid(target), isCurrent(), minimized() == true else { return false }
        guard size(target.size) == .success, isCurrent(), minimized() == true else { return false }
        guard position(target.origin) == .success, isCurrent(), minimized() == true else { return false }
        guard size(target.size) == .success else { return false }
        let deadline = now() + 0.3
        while isCurrent(), minimized() == true {
            if let actual = frame(), WindowAnimationGeometry.near(actual, target, tolerance: 1) { return true }
            if now() >= deadline { return false }
            pause()
        }
        return false
    }

    /// Only the current operation may undo preparation. Cancellation retains
    /// the remembered original without issuing writes against a newer action.
    static func rollback(original: CGRect, isCurrent: () -> Bool,
                         size: (CGSize) -> AXError, position: (CGPoint) -> AXError) -> Bool {
        guard WindowAnimationGeometry.valid(original), isCurrent() else { return false }
        guard size(original.size) == .success, isCurrent() else { return false }
        guard position(original.origin) == .success, isCurrent() else { return false }
        return size(original.size) == .success
    }

    static func acknowledge(isCurrent: () -> Bool, minimized: () -> Bool?, restore: () -> AXError,
                            frame: () -> CGRect?, now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                            pause: () -> Void = { Thread.sleep(forTimeInterval: 0.025) }) -> WindowPlacementCoordinator.Outcome {
        guard isCurrent() else { return .cancelled }
        guard let initial = minimized() else { return .unresponsive }
        if initial {
            guard isCurrent() else { return .cancelled }
            let error = restore()
            guard error == .success else { return error == .cannotComplete ? .unresponsive : .failed(restored: false) }
        }
        let deadline = now() + 1.5
        while isCurrent() {
            if minimized() == false, let actual = frame() { return .placed(actual) }
            if now() >= deadline { return .unresponsive }
            pause()
        }
        return .cancelled
    }
}
