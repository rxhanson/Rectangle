import Cocoa
import QuartzCore

final class WindowAnimationRequest {
    private let lock = NSLock()
    private var terminated = false
    private var cancellation: (() -> Void)?
    private var changed = false
    private var resized = false
    func geometryChanged(resized: Bool = false) { lock.lock(); changed = true; self.resized = self.resized || resized; lock.unlock() }
    func consumeGeometryChange() -> Bool { lock.lock(); defer { lock.unlock() }; let result = changed; changed = false; return result }
    func consumeResizeChange() -> Bool { lock.lock(); defer { lock.unlock() }; let result = resized; resized = false; return result }
    init(cancellation: (() -> Void)? = nil) { self.cancellation = cancellation }
    // Terminal callbacks run on main, separately from placement completion.
    func cancel() {
        lock.lock()
        guard !terminated else { lock.unlock(); return }
        terminated = true
        let callback = cancellation
        cancellation = nil
        lock.unlock()
        callback?()
    }
    func complete() {
        lock.lock()
        terminated = true
        cancellation = nil
        lock.unlock()
    }
    var isCurrent: Bool { lock.lock(); defer { lock.unlock() }; return !terminated }
}
