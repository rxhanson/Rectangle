import Cocoa
import ScreenCaptureKit

/// Try the target geometry before restoring, then acknowledge the restored
/// state and fresh geometry before the ordinary snap's final verification.
enum LayoutHelperWindowRestoration {
    static func restore(_ window: AccessibilityElement, target: CGRect? = nil, original: CGRect? = nil,
                        observePreparation: @escaping (CGRect) -> Void = { _ in }, isCurrent: @escaping () -> Bool,
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
        WindowWriteQueue.shared.perform {
            let valid = { !cancellation.isCancelled && WindowProcessIdentity.launchTime(for: pid) == launch }
            let outcome: WindowPlacementCoordinator.Outcome
            if let element = WindowAccessibilityLookup.resolve(pid: pid, id: id, launch: launch,
                preferred: preferred, isCurrent: valid) {
                let worker = PlacementWindowElement(element, windowID: id)
                func recordedWrite(_ write: () -> AXError) -> AXError {
                    guard let status = cancellation.write(write) else { return .failure }
                    // Capture actual clamping and partial writes, including the
                    // last write whose reply arrived after cancellation.
                    observePreparation(worker.frame)
                    return status
                }
                if let target, worker.isResizable(), worker.isSystemDialog != true {
                    _ = prepare(target: target, isCurrent: valid, minimized: { worker.isMinimized },
                        size: { requested in recordedWrite { worker.writeSize(requested) } },
                        position: { requested in recordedWrite { worker.writePosition(requested) } },
                        frame: { let frame = worker.frame; observePreparation(frame); return frame })
                }
                let acknowledged = acknowledge(isCurrent: valid, minimized: { worker.isMinimized }, restore: {
                    cancellation.write { AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) } ?? .failure
                }, frame: {
                    let frame = worker.frame
                    observePreparation(frame)
                    guard WindowGeometry.valid(frame), let server = WindowUtil.getWindowFrame(id: id),
                          WindowGeometry.near(frame, server, tolerance: 1) else { return nil }
                    return frame
                })
                switch acknowledged {
                case .failed, .unresponsive:
                    if let original {
                        _ = rollback(original: original, isCurrent: valid,
                            size: { requested in recordedWrite { worker.writeSize(requested) } },
                            position: { requested in recordedWrite { worker.writePosition(requested) } })
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
        guard WindowGeometry.valid(target), isCurrent(), minimized() == true else { return false }
        guard size(target.size) == .success, isCurrent(), minimized() == true else { return false }
        guard position(target.origin) == .success, isCurrent(), minimized() == true else { return false }
        guard size(target.size) == .success else { return false }
        let deadline = now() + 0.3
        while isCurrent(), minimized() == true {
            if let actual = frame(), WindowGeometry.near(actual, target, tolerance: 1) { return true }
            if now() >= deadline { return false }
            pause()
        }
        return false
    }

    /// Only the current operation may undo preparation. Cancellation retains
    /// the remembered original without issuing writes against a newer action.
    static func rollback(original: CGRect, isCurrent: () -> Bool,
                         size: (CGSize) -> AXError, position: (CGPoint) -> AXError) -> Bool {
        guard WindowGeometry.valid(original), isCurrent() else { return false }
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

/// Original geometry survives a failed or cancelled restoration until placement
/// succeeds. Process identity keeps retries from inheriting another app's frame.
struct LayoutHelperRestorationFrames {
    private struct Identity: Hashable {
        let id: CGWindowID
        let pid: pid_t
        let launch: TimeInterval
    }
    /// A worker can finish reading its last write after the main owner cancels.
    /// Keep those observations on the operation record, not in shared manager state.
    private final class Preparation {
        private let lock = NSLock()
        private var frames: [CGRect] = []
        func record(_ frame: CGRect) {
            guard WindowGeometry.valid(frame) else { return }
            lock.lock(); defer { lock.unlock() }
            if !frames.contains(where: { WindowGeometry.matches($0, frame, tolerance: 1) }) { frames.append(frame) }
        }
        func matches(_ frame: CGRect) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return frames.contains { WindowGeometry.matches($0, frame, tolerance: 1) }
        }
    }
    private var frames: [Identity: (original: CGRect, preparation: Preparation)] = [:]
    mutating func original(id: CGWindowID, pid: pid_t, launch: TimeInterval, frame: CGRect, remember: Bool, prepared: CGRect? = nil) -> CGRect {
        let key = Identity(id: id, pid: pid, launch: launch)
        if let stored = frames[key] {
            if stored.preparation.matches(frame) {
                if let prepared { stored.preparation.record(prepared) }
                return stored.original
            }
            frames.removeValue(forKey: key)
        }
        if remember {
            let preparation = Preparation()
            preparation.record(frame)
            if let prepared { preparation.record(prepared) }
            frames[key] = (frame, preparation)
        }
        return frame
    }
    func preparationObserver(id: CGWindowID, pid: pid_t, launch: TimeInterval) -> (CGRect) -> Void {
        let preparation = frames[Identity(id: id, pid: pid, launch: launch)]?.preparation
        return { preparation?.record($0) }
    }
    mutating func remove(windowID: CGWindowID) {
        frames = frames.filter { $0.key.id != windowID }
    }
    mutating func remove(id: CGWindowID, pid: pid_t, launch: TimeInterval) {
        frames.removeValue(forKey: Identity(id: id, pid: pid, launch: launch))
    }
    mutating func prune(live: Set<CGWindowID>) {
        frames = frames.filter { live.contains($0.key.id) && WindowProcessIdentity.launchTime(for: $0.key.pid) == $0.key.launch }
    }
}
