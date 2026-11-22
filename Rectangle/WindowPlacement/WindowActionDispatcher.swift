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
        let window = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement()
        let resolved = ExecutionParameters(parameters.action, updateRestoreRect: parameters.updateRestoreRect,
            screen: parameters.screen, windowElement: window, windowId: parameters.windowId ?? window?.getWindowId(),
            source: parameters.source, preservesFocus: parameters.preservesFocus, completion: parameters.completion,
            cancellation: parameters.cancellation, isDisplayCycle: parameters.isDisplayCycle, identity: parameters.identity)
        if !fence.deferExternalWrites(discard: parameters.completion, resume: { perform(resolved) }) {
            perform(resolved)
        }
    }

    private func dispatchMember(_ parameters: ExecutionParameters, perform: @escaping (ExecutionParameters) -> Void) {
        guard !fence.externalTargets.isEmpty || fence.hasPendingSharedLayout,
              let window = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement() else {
            perform(parameters)
            return
        }
        let id = parameters.windowId ?? window.getWindowId()
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
