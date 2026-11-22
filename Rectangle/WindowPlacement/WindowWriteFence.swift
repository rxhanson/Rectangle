import Cocoa

/// Arbitrates ownership on main. A superseded worker keeps its reservation
/// until it returns, because invalidating its lease cannot recall an issued AX call.
final class WindowWriteFence {
    static let shared = WindowWriteFence()

    struct Target {
        let element: AccessibilityElement?
        let windowID: CGWindowID?

        fileprivate func overlaps(_ other: Target) -> Bool {
            if let windowID, let otherID = other.windowID { return windowID == otherID }
            if let pid = element?.pid, let otherPID = other.element?.pid, pid != otherPID { return false }
            // Two wrappers in the same app can represent the same window even
            // when macOS temporarily stops providing a window ID.
            return true
        }
    }

    final class Lease {
        private let lock = NSLock()
        private var current = true

        var isCurrent: Bool {
            lock.lock()
            defer { lock.unlock() }
            return current
        }

        fileprivate func invalidate() {
            lock.lock()
            current = false
            lock.unlock()
        }
    }

    private struct Entry {
        let lease: Lease
        let targets: [Target]
        let onSuperseded: (() -> Void)?
        let isExternal: Bool
        var workInFlight = false
        var ready: (() -> Void)?

        func overlaps(_ otherTargets: [Target]) -> Bool {
            targets.contains { target in otherTargets.contains(where: target.overlaps) }
        }
    }

    private struct PendingPlan {
        let targets: [Target]
        let discard: (() -> Void)?
        let resume: () -> Void

        func overlaps(_ otherTargets: [Target]) -> Bool {
            targets.contains { target in otherTargets.contains(where: target.overlaps) }
        }
    }

    private let workQueue = DispatchQueue(label: "Rectangle.WindowPlacement", qos: .userInteractive,
                                         attributes: .concurrent)
    private var entries: [Entry] = []
    private var pendingPlans: [PendingPlan] = []

    var externalTargets: [Target] {
        entries.filter { $0.isExternal && ($0.workInFlight || $0.lease.isCurrent) }.flatMap(\.targets)
    }

    func hasConflictingExternalWork(for targets: [Target]) -> Bool {
        externalTargets.contains { external in targets.contains(where: external.overlaps) }
    }

    /// Let planning read the frame after the issued work. Merely waiting does
    /// not take ownership: a request can still be rejected by its provider.
    func deferPlanningIfNeeded(for targets: [Target], discard: (() -> Void)?,
                               resume: @escaping () -> Void) -> Bool {
        let plan = PendingPlan(targets: targets, discard: discard, resume: resume)
        guard hasIssuedWork(for: plan) else { return false }
        pendingPlans.append(plan)
        return true
    }

    private func hasIssuedWork(for plan: PendingPlan) -> Bool {
        entries.contains { $0.workInFlight && $0.overlaps(plan.targets) }
    }

    private func resumeDrainedPlans() {
        // The latest request gets first refusal. An accepted claim discards
        // older overlapping plans, while a rejection lets them continue.
        while let index = pendingPlans.lastIndex(where: { !hasIssuedWork(for: $0) }) {
            pendingPlans.remove(at: index).resume()
        }
    }

    /// Every participant is claimed before an old owner is notified, so a
    /// two-window operation can never take ownership of just one member.
    func claim(_ targets: [Target], isExternal: Bool = true, onSuperseded: (() -> Void)? = nil) -> Lease {
        precondition(!targets.isEmpty)
        let superseded = entries.filter { $0.lease.isCurrent && $0.overlaps(targets) }
        let discarded = removePendingPlans(overlapping: targets)
        for entry in superseded { entry.lease.invalidate() }
        let lease = Lease()
        entries.append(Entry(lease: lease, targets: targets, onSuperseded: onSuperseded, isExternal: isExternal))
        entries.removeAll { !$0.workInFlight && !$0.lease.isCurrent }
        for entry in superseded { entry.onSuperseded?() }
        for plan in discarded { plan.discard?() }
        return lease
    }

    func discardPendingPlans(overlapping targets: [Target]) {
        for plan in removePendingPlans(overlapping: targets) { plan.discard?() }
    }

    private func removePendingPlans(overlapping targets: [Target]) -> [PendingPlan] {
        let discarded = pendingPlans.filter { $0.overlaps(targets) }
        pendingPlans.removeAll { $0.overlaps(targets) }
        return discarded
    }

    func whenReady(_ lease: Lease, _ body: @escaping () -> Void) {
        guard lease.isCurrent, let index = entries.firstIndex(where: { $0.lease === lease }) else { return }
        entries[index].ready = body
        runReadyEntries()
    }

    func finish(_ lease: Lease) {
        lease.invalidate()
        entries.removeAll { $0.lease === lease && !$0.workInFlight }
        runReadyEntries()
    }

    /// Call from a ready lease. Even on supersession the completion runs to let
    /// the feature release local state. Only a current lease can commit history.
    func perform<T>(_ lease: Lease, work: @escaping () -> T, completion: @escaping (T) -> Void) {
        guard lease.isCurrent, let index = entries.firstIndex(where: { $0.lease === lease }) else { return }
        precondition(!entries[index].workInFlight)
        entries[index].workInFlight = true
        workQueue.async { [self] in
            let result = work()
            DispatchQueue.main.async { [self] in
                if let index = entries.firstIndex(where: { $0.lease === lease }) {
                    entries[index].workInFlight = false
                }
                // A fresh plan must get a chance to supersede the old writer
                // before its completion can enqueue another AX phase.
                resumeDrainedPlans()
                completion(result)
                entries.removeAll { !$0.workInFlight && !$0.lease.isCurrent }
                runReadyEntries()
            }
        }
    }

    private func runReadyEntries() {
        while let index = entries.indices.first(where: canStart) {
            let body = entries[index].ready
            entries[index].ready = nil
            body?()
        }
    }

    private func canStart(_ index: Int) -> Bool {
        let entry = entries[index]
        return entry.lease.isCurrent && !entry.workInFlight && entry.ready != nil && !entries.enumerated().contains { otherIndex, other in
            otherIndex != index && other.workInFlight && other.overlaps(entry.targets)
        }
    }
}
