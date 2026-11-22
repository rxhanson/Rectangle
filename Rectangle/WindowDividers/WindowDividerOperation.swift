import Foundation

/// Escape asks the current writer to restore the pair. A new owner instead
/// invalidates the lease, so even rollback must stop between AX calls.
final class WindowDividerOperation {
    let lease: WindowWriteFence.Lease
    private let lock = NSLock()
    private var rollback = false

    init(lease: WindowWriteFence.Lease) {
        self.lease = lease
    }

    func requestRollback() {
        lock.lock()
        rollback = true
        lock.unlock()
    }

    var rollbackRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rollback
    }
}
