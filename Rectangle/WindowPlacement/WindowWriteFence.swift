import Cocoa

/// Arbitrates ownership on main. A superseded worker keeps its reservation
/// until it returns, because invalidating its lease cannot recall an issued AX call.
final class WindowWriteFence {
    static let shared = WindowWriteFence()

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
        let targets: [WindowWriteTarget]
        let onSuperseded: (() -> Void)?
        let isExternal: Bool
        var workInFlight = false
        var ready: (() -> Void)?

        func overlaps(_ otherTargets: [WindowWriteTarget]) -> Bool {
            targets.contains { target in otherTargets.contains(where: target.overlaps) }
        }
    }

    private struct PendingPlan {
        let targets: [WindowWriteTarget]
        let order: Int
        let isShared: Bool
        let discard: (() -> Void)?
        let resume: () -> Void

        func overlaps(_ otherTargets: [WindowWriteTarget]) -> Bool {
            targets.contains { target in otherTargets.contains(where: target.overlaps) }
        }
    }

    private let workQueue = DispatchQueue(label: "Rectangle.WindowPlacement", qos: .userInteractive,
                                         attributes: .concurrent)
    private var entries: [Entry] = []
    private var pendingPlans: [PendingPlan] = []
    private var planOrder = 0

    var hasPendingSharedLayout: Bool { pendingPlans.contains { $0.isShared } }

    var externalTargets: [WindowWriteTarget] {
        entries.filter { $0.isExternal && ($0.workInFlight || $0.lease.isCurrent) }.flatMap(\.targets)
    }

    func hasConflictingExternalWork(for targets: [WindowWriteTarget]) -> Bool {
        externalTargets.contains { external in targets.contains(where: external.overlaps) }
    }

    /// Shared layouts form an ordering boundary for later member commands.
    /// Wait for all issued writes, commit the shared layout, then apply newer commands.
    func deferExternalWrites(discard: (() -> Void)? = nil, resume: @escaping () -> Void) -> Bool {
        let targets = [WindowWriteTarget(element: nil, windowID: nil)]
        guard hasIssuedWork(for: targets) else { return false }
        planOrder += 1
        let order = planOrder
        let plan = PendingPlan(targets: targets, order: order, isShared: true, discard: discard) { [self] in
            let lease = claim(targets, isExternal: false, supersedingPlansBefore: order)
            resume()
            finish(lease)
        }
        pendingPlans.append(plan)
        return true
    }

    func hasPendingPlans(overlapping targets: [WindowWriteTarget]) -> Bool {
        pendingPlans.contains { $0.overlaps(targets) }
    }

    func deferPlanningIfNeeded(for targets: [WindowWriteTarget], discard: (() -> Void)?,
                               resume: @escaping () -> Void) -> Bool {
        guard hasIssuedWork(for: targets) || hasPendingSharedLayout else { return false }
        planOrder += 1
        pendingPlans.append(PendingPlan(targets: targets, order: planOrder, isShared: false,
                                        discard: discard, resume: resume))
        return true
    }

    func hasIssuedWork(for targets: [WindowWriteTarget]) -> Bool {
        entries.contains { $0.workInFlight && $0.overlaps(targets) }
    }

    private func hasIssuedWork(for plan: PendingPlan) -> Bool {
        hasIssuedWork(for: plan.targets)
    }

    private func resumeDrainedPlans() {
        while true {
            let ready = pendingPlans.indices.filter { index in
                let plan = pendingPlans[index]
                return !hasIssuedWork(for: plan) && !pendingPlans.contains {
                    $0.isShared && (!plan.isShared || $0.order < plan.order)
                }
            }
            let shared = ready.filter { pendingPlans[$0].isShared }.min {
                pendingPlans[$0].order < pendingPlans[$1].order
            }
            // Between shared layouts, the latest member request gets first refusal.
            guard let index = shared ?? ready.last else { return }
            pendingPlans.remove(at: index).resume()
        }
    }

    /// Every participant is claimed before an old owner is notified, so a
    /// two-window operation can never take ownership of just one member.
    func claim(_ targets: [WindowWriteTarget], isExternal: Bool = true, supersedingPlansBefore: Int? = nil, onSuperseded: (() -> Void)? = nil) -> Lease {
        precondition(!targets.isEmpty)
        let superseded = entries.filter { $0.lease.isCurrent && $0.overlaps(targets) }
        let discarded = removePendingPlans(overlapping: targets, before: supersedingPlansBefore)
        for entry in superseded { entry.lease.invalidate() }
        let lease = Lease()
        entries.append(Entry(lease: lease, targets: targets, onSuperseded: onSuperseded, isExternal: isExternal))
        entries.removeAll { !$0.workInFlight && !$0.lease.isCurrent }
        for entry in superseded { entry.onSuperseded?() }
        for plan in discarded { plan.discard?() }
        return lease
    }

    private func removePendingPlans(overlapping targets: [WindowWriteTarget], before order: Int?) -> [PendingPlan] {
        func superseded(_ plan: PendingPlan) -> Bool {
            guard !plan.isShared, plan.overlaps(targets) else { return false }
            return order.map { plan.order < $0 } ?? true
        }
        let discarded = pendingPlans.filter(superseded)
        pendingPlans.removeAll(where: superseded)
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
                // Publish both achieved frames and their history before a queued
                // command takes over one member of the pair.
                completion(result)
                resumeDrainedPlans()
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
