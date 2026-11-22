import Cocoa

/// Cancellation never holds its lock while an external app handles AX work.
final class AccessibilityReadCancellation {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCurrent: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
}
