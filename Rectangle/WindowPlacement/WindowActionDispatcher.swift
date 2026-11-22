import Cocoa

/// Holds commands until an external writer has published its achieved frames.
/// The intended window is resolved before waiting, so later focus changes cannot redirect it.
final class WindowActionDispatcher {
    private let fence: WindowWriteFence

    init(fence: WindowWriteFence = .shared) {
        self.fence = fence
    }

    func prepare(_ parameters: ExecutionParameters, perform: @escaping (ExecutionParameters) -> Void) {
        if MultiWindowManager.handles(parameters.action), !MultiWindowManager.writesFrames(parameters.action) {
            perform(parameters)
            return
        }
        guard MultiWindowManager.writesFrames(parameters.action) || TodoManager.handles(parameters.action) else {
            dispatchMember(parameters, perform: perform)
            return
        }
        guard !fence.externalTargets.isEmpty || fence.hasPendingSharedLayout else { perform(parameters); return }
        let target = resolveTarget(parameters)
        let resolved = ExecutionParameters(parameters.action, updateRestoreRect: parameters.updateRestoreRect,
            screen: parameters.screen, windowElement: target.element, windowId: target.windowID,
            source: parameters.source, preservesFocus: parameters.preservesFocus, completion: parameters.completion,
            cancellation: parameters.cancellation, isDisplayCycle: parameters.isDisplayCycle, identity: parameters.identity)
        if !fence.deferExternalWrites(discard: parameters.completion, resume: { perform(resolved) }) {
            perform(resolved)
        }
    }

    private func resolveTarget(_ parameters: ExecutionParameters) -> WindowWriteTarget {
        if let window = parameters.windowElement {
            return WindowWriteTarget(element: window, windowID: parameters.windowId ?? window.getWindowId())
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let reserved = Self.reservedTarget(frontPID: pid,
                windows: WindowUtil.getWindowList(forceRefresh: true, cacheResult: false),
                reservations: fence.externalTargets) {
            return WindowWriteTarget(element: reserved.element, windowID: parameters.windowId ?? reserved.windowID)
        }
        let window = AccessibilityElement.getFrontWindowElement()
        return WindowWriteTarget(element: window, windowID: parameters.windowId ?? window?.getWindowId())
    }

    /// Reuse the known AX element only when the front app's foremost window
    /// is reserved. Asking that busy app for its focused window would block main.
    static func reservedTarget(frontPID: pid_t, windows: [WindowInfo], reservations: [WindowWriteTarget]) -> WindowWriteTarget? {
        guard let front = windows.first(where: { $0.pid == frontPID && $0.isOnScreen && $0.alpha > 0 }),
              front.level == 0 else { return nil }
        return reservations.first { $0.windowID == front.id && $0.element?.pid == frontPID }
    }

    private func dispatchMember(_ parameters: ExecutionParameters, perform: @escaping (ExecutionParameters) -> Void) {
        guard !fence.externalTargets.isEmpty || fence.hasPendingSharedLayout else { perform(parameters); return }
        let target = resolveTarget(parameters)
        guard let window = target.element else { perform(parameters); return }
        let id = target.windowID
        func resolved(resumed: Bool) -> ExecutionParameters {
            ExecutionParameters(parameters.action, updateRestoreRect: parameters.updateRestoreRect,
                screen: parameters.screen, windowElement: window, windowId: id, source: parameters.source,
                preservesFocus: parameters.preservesFocus, completion: parameters.completion,
                cancellation: parameters.cancellation, isDisplayCycle: parameters.isDisplayCycle, identity: parameters.identity,
                preservesUnrelatedActions: resumed)
        }
        if fence.deferPlanningIfNeeded(for: [.init(element: window, windowID: id)],
                                      discard: parameters.completion, resume: { perform(resolved(resumed: true)) }) {
            DiagnosticTrace.event("window-action-deferred", fields: ["action": parameters.action.name,
                "windowID": id.map { Int($0) } ?? 0])
        } else {
            perform(resolved(resumed: false))
        }
    }
}
