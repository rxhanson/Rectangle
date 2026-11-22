import Cocoa

/// Coordinates ordinary actions with external operations that reserve several windows.
/// A superseded AX write retains its reservation until the call has returned.
final class WindowPlacementCoordinator {
    struct Access {
        let lease: WindowWriteFence.Lease
        let ordinaryExecutionID: Int?

        var followsExternalWriter: Bool { ordinaryExecutionID == nil }
    }

    private let fence: WindowWriteFence
    private let animator: WindowAnimator
    private var executionID = 0

    init(fence: WindowWriteFence, animator: WindowAnimator) {
        self.fence = fence
        self.animator = animator
    }

    var externalTargets: [WindowWriteFence.Target] { fence.externalTargets }

    func deferPlanningIfNeeded(for targets: [WindowWriteFence.Target], discard: (() -> Void)?,
                               resume: @escaping () -> Void) -> Bool {
        fence.deferPlanningIfNeeded(for: targets, discard: discard, resume: resume)
    }

    func hasConflictingExternalWork(for targets: [WindowWriteFence.Target]) -> Bool {
        fence.hasConflictingExternalWork(for: targets)
    }

    /// An achieved action still takes ownership of its windows. Retire older
    /// writes and recovery on those windows without cancelling unrelated work.
    func acceptAlreadyAchieved(for targets: [WindowWriteFence.Target]) -> Bool {
        guard !fence.hasConflictingExternalWork(for: targets) else { return false }
        retirePreviousAccess(to: targets)
        return true
    }

    /// Execution has already waited for issued writes. Even an empty Restore
    /// takes over before the previous writer can commit its completion history.
    func acceptRestoreWithoutTarget(for target: WindowWriteFence.Target) {
        retirePreviousAccess(to: [target])
    }

    private func retirePreviousAccess(to targets: [WindowWriteFence.Target]) {
        let lease = fence.claim(targets, isExternal: false)
        fence.finish(lease)
    }

    func isCurrent(_ access: Access) -> Bool {
        access.lease.isCurrent && (access.followsExternalWriter || access.ordinaryExecutionID == executionID)
    }

    /// Planning has already waited for every issued conflicting write.
    func begin(to targets: [WindowWriteTarget], hasWaitedForWrites: Bool) -> Access {
        precondition(!fence.hasIssuedWork(for: targets))
        let ordinaryID: Int?
        // A resumed command keeps its window scope while later commands on
        // other windows continue using the shared animator.
        if hasWaitedForWrites || fence.hasConflictingExternalWork(for: targets) {
            ordinaryID = nil
        } else {
            executionID &+= 1
            ordinaryID = executionID
        }
        return Access(lease: fence.claim(targets, isExternal: false), ordinaryExecutionID: ordinaryID)
    }

    func finish(_ access: Access) {
        fence.finish(access.lease)
    }

    func availableAnimation(_ requested: WindowMoveAnimation?, for window: AccessibilityElement,
                            access: Access) -> WindowMoveAnimation? {
        // The single animator may be serving an unrelated window by the time an
        // overlapping external write drains. Place this window independently.
        if access.followsExternalWriter && !animator.isIdle && animator.destination(for: window) == nil {
            return nil
        }
        return requested
    }

    func place(_ window: AccessibilityElement, animation: WindowMoveAnimation?, access: Access,
               cancellation: (() -> Void)?, completion: @escaping (CGRect?) -> Void) {
        if animation == nil, access.followsExternalWriter {
            animator.drainWrites(for: [window]) { completion(nil) }
            return
        }
        guard animation != nil || !animator.isIdle else { return completion(nil) }
        animator.place(window, animation: animation, cancellation: cancellation, completion: completion)
    }
}
