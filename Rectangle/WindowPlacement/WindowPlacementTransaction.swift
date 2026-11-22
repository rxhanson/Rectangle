import Cocoa

/// Native operations shared by conditional placement and its recovery.
struct WindowPlacementServices {
    var animate: (AccessibilityElement, WindowMoveAnimation?, (() -> Void)?, @escaping (CGRect?) -> Void) -> Void
    var drainWrites: ([AccessibilityElement], @escaping () -> Void) -> Void
    var destination: (AccessibilityElement) -> CGRect?
    var confirmsRollback: (AccessibilityElement, CGWindowID?, CGRect) -> Bool

    init(animator: WindowAnimator) {
        animate = { animator.place($0, animation: $1, cancellation: $2, completion: $3) }
        drainWrites = { animator.drainWrites(for: $0, completion: $1) }
        destination = { animator.destination(for: $0) }
        confirmsRollback = { window, id, frame in
            guard WindowGeometry.near(window.frame, frame) else { return false }
            guard let id else { return true }
            return WindowUtil.getWindowFrame(id: id).map { WindowGeometry.near($0, frame) } == true
        }
    }
}

/// Owns a conditional move's lifetime and recovery. A cancelled AX call may still
/// return, so recovery waits for issued writes and checks ownership again.
final class WindowPlacementTransaction {
    private enum Phase { case preparing, animating, draining, settling, finished }
    private let condition: WindowPlacementCondition
    private let result: ResultParameters
    private let history: WindowHistory
    private let previousAction: RectangleAction?
    private let previousRestore: CGRect?
    private let services: WindowPlacementServices
    private var phase: Phase = .preparing
    private var originalFrame: CGRect?
    private var invalidated = false
    private var mayHaveWritten = false
    private var monitoring = false
    private var isCurrent: (() -> Bool)?
    private var ownsWindow: (() -> Bool)?
    private var onEnd: (() -> Void)?
    private var onCancel: ((Bool) -> Void)?

    init(condition: WindowPlacementCondition, result: ResultParameters, history: WindowHistory,
         previousAction: RectangleAction?, previousRestore: CGRect?, services: WindowPlacementServices) {
        self.condition = condition
        self.result = result
        self.history = history
        self.previousAction = previousAction
        self.previousRestore = previousRestore
        self.services = services
    }

    func isValid() -> Bool {
        if !invalidated { invalidated = !condition.isValid() }
        return !invalidated
    }

    func start(animated: Bool, isCurrent: @escaping () -> Bool, ownsWindow: @escaping () -> Bool,
               onEnd: @escaping () -> Void, onCancel: @escaping (Bool) -> Void,
               perform: @escaping (@escaping () -> Void) -> Void) {
        self.isCurrent = isCurrent
        self.ownsWindow = ownsWindow
        self.onEnd = onEnd
        self.onCancel = onCancel
        let begin = {
            guard isCurrent() else { return onEnd() }
            let origin = self.result.windowElement.frame
            guard WindowGeometry.valid(origin) else { return onCancel(true) }
            self.originalFrame = origin
            guard self.isValid() else { return self.rollback() }
            guard isCurrent() else { return onEnd() }
            if animated {
                self.mayHaveWritten = true
                self.phase = .animating
                self.monitoring = true
                self.condition.whilePending { [weak self] _ in self?.drainInvalidatedAnimation() }
                guard self.phase == .animating else { return }
            }
            perform { self.animationCancelled(animated: animated) }
        }
        // The retiring writer may change the frame after planning. Its final
        // physical position is the only safe origin for a later rollback.
        if services.destination(result.windowElement) != nil {
            services.drainWrites([result.windowElement], begin)
        } else {
            begin()
        }
    }

    func beginSettlement() -> Bool {
        guard phase == .preparing || phase == .animating else { return false }
        phase = .settling
        stopMonitoring()
        guard validate() else { return false }
        mayHaveWritten = true
        return true
    }

    func validate() -> Bool {
        guard isCurrent?() == true else { onEnd?(); return false }
        guard isValid() else { rollback(); return false }
        return true
    }

    func canCommit(_ frame: CGRect) -> Bool {
        guard isCurrent?() == true else { onEnd?(); return false }
        guard isValid(), WindowGeometry.valid(frame),
              frame != originalFrame || WindowGeometry.near(frame, result.calcResult.rect.screenFlipped)
        else { rollback(); return false }
        guard isCurrent?() == true else { onEnd?(); return false }
        return true
    }

    func observeEnvironmentDuringRetry() -> (() -> Void)? {
        condition.observeEnvironmentDuringRetry()
    }

    /// The terminal callback can be delivered by both an animator and a monitor.
    /// Releasing once prevents a late callback from completing a new operation.
    func finish() -> Bool {
        guard phase != .finished else { return false }
        phase = .finished
        stopMonitoring()
        isCurrent = nil
        ownsWindow = nil
        onEnd = nil
        onCancel = nil
        return true
    }

    private func stopMonitoring() {
        guard monitoring else { return }
        monitoring = false
        condition.stopMonitoring()
    }

    private func animationCancelled(animated: Bool) {
        guard animated else {
            onCancel?(false)
            return
        }
        // Animator and condition notifications can arrive in either order.
        // Let both classify the event before deciding whether to recover.
        DispatchQueue.main.async {
            guard self.phase == .animating else { return }
            guard self.ownsWindow?() == true else {
                self.onCancel?(false)
                return
            }
            if self.condition.invalidation != nil || !self.isValid() {
                self.drainInvalidatedAnimation()
            } else {
                self.retireInterruptedPlacement(conditionFailed: false)
            }
        }
    }

    private func drainInvalidatedAnimation() {
        guard phase == .animating else { return }
        guard ownsWindow?() == true else {
            onCancel?(true)
            return
        }
        phase = .draining
        invalidated = true
        services.drainWrites([result.windowElement]) {
            DispatchQueue.main.async {
                guard self.phase == .draining else { return }
                self.rollback()
            }
        }
    }

    private func retireInterruptedPlacement(conditionFailed: Bool) {
        // A changed desktop can make the original coordinates unsafe. Keep a
        // useful manual Restore origin without issuing another frame write.
        if ownsWindow?() == true, let origin = originalFrame, let id = result.windowId {
            history.lastRectangleActions.removeValue(forKey: id)
            history.restoreRects[id] = origin
        }
        onCancel?(conditionFailed)
    }

    private func rollback() {
        guard let origin = originalFrame, ownsWindow?() == true else {
            onCancel?(true)
            return
        }
        if condition.invalidation == .environmentChanged {
            return retireInterruptedPlacement(conditionFailed: true)
        }
        let window = result.windowElement
        let current = window.frame
        if mayHaveWritten, WindowGeometry.valid(current), !WindowGeometry.near(current, origin), ownsWindow?() == true {
            window.setFrame(origin)
        }
        let restored = services.confirmsRollback(window, result.windowId, origin)
        if let id = result.windowId, ownsWindow?() == true {
            history.lastRectangleActions[id] = restored ? previousAction : nil
            history.restoreRects[id] = restored ? previousRestore : origin
        }
        onCancel?(true)
    }
}
