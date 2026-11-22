import Cocoa

/// Holds commands until an external writer has published its achieved frames.
/// The intended window is resolved before waiting, so later focus changes cannot redirect it.
final class WindowActionDispatcher {
    private let fence: WindowWriteFence
    private let execute: (ExecutionParameters) -> Void

    init(fence: WindowWriteFence = .shared, execute: @escaping (ExecutionParameters) -> Void) {
        self.fence = fence
        self.execute = execute
    }

    func prepare(_ parameters: ExecutionParameters, perform: @escaping (ExecutionParameters) -> Void) {
        guard MultiWindowManager.handles(parameters.action) || TodoManager.handles(parameters.action),
              !fence.externalTargets.isEmpty else { perform(parameters); return }
        let window = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement()
        let resolved = ExecutionParameters(parameters.action, updateRestoreRect: parameters.updateRestoreRect,
            screen: parameters.screen, windowElement: window, windowId: parameters.windowId ?? window?.getWindowId(),
            source: parameters.source, preservesFocus: parameters.preservesFocus, completion: parameters.completion,
            cancellation: parameters.cancellation, isDisplayCycle: parameters.isDisplayCycle, identity: parameters.identity)
        if !fence.deferExternalWrites(discard: parameters.completion, resume: { perform(resolved) }) {
            perform(resolved)
        }
    }

    func dispatch(_ parameters: ExecutionParameters) {
        guard !fence.externalTargets.isEmpty,
              let window = parameters.windowElement ?? AccessibilityElement.getFrontWindowElement() else {
            execute(parameters)
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
        if !fence.deferPlanningIfNeeded(for: [.init(element: window, windowID: id)],
                                       discard: parameters.completion, resume: { [execute] in execute(resolved(resumed: true)) }) {
            execute(resolved(resumed: false))
        }
    }
}
