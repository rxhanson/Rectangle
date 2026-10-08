import Cocoa

/// Activate the selected window without raising its application siblings.
extension AccessibilityElement {
    func activateAndRaiseWindow(isCurrent: @escaping () -> Bool,
                                completion: @escaping (AXError, AXError, AXError) -> Void) {
        guard isCurrent() else { return }
        guard let pid else { completion(.invalidUIElement, .invalidUIElement, .invalidUIElement); return }
        let workspace = NSWorkspace.shared
        func canContinue(after error: AXError) -> Bool {
            error != .cannotComplete && error != .invalidUIElement
        }
        func raiseSelected(activation: AXError) {
            guard isCurrent() else { return }
            guard workspace.frontmostApplication?.processIdentifier == pid else {
                completion(activation, .cannotComplete, .cannotComplete)
                return
            }
            let main = AXUIElementSetAttributeValue(axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            guard isCurrent() else { return }
            guard canContinue(after: main) else {
                completion(activation, main, main)
                return
            }
            let raise = AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
            completion(activation, main, raise)
        }
        if workspace.frontmostApplication?.processIdentifier == pid {
            raiseSelected(activation: .success)
            return
        }
        // A failed AX request to an unresponsive app must not be followed by
        // more synchronous requests (or a later timeout that retries them).
        let selectedMain = AXUIElementSetAttributeValue(axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        guard isCurrent() else { return }
        guard canContinue(after: selectedMain) else {
            completion(selectedMain, selectedMain, selectedMain)
            return
        }
        let selectedRaise = AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
        guard isCurrent() else { return }
        guard canContinue(after: selectedRaise) else {
            completion(selectedRaise, selectedMain, selectedRaise)
            return
        }
        var observer: NSObjectProtocol?
        var timeout: DispatchWorkItem?
        var finished = false
        var activation = AXError.success
        let finish = {
            guard !finished else { return }
            finished = true
            if let registered = observer { workspace.notificationCenter.removeObserver(registered) }
            observer = nil
            timeout?.cancel(); timeout = nil
            guard canContinue(after: activation) else {
                completion(activation, .cannotComplete, .cannotComplete)
                return
            }
            raiseSelected(activation: activation)
        }
        observer = workspace.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { note in
                guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == pid else { return }
                DispatchQueue.main.async(execute: finish)
            }
        let deadline = DispatchWorkItem(block: finish)
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: deadline)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard isCurrent() else { finish(); return }
        if selectedMain == .success, selectedRaise == .success,
           let app = NSRunningApplication(processIdentifier: pid), app.activate(options: []) {
            activation = .success
        } else {
            // Some applications refuse background main-window changes. Retain
            // application activation as the fallback for an otherwise unusable selection.
            activation = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        if activation != .success || workspace.frontmostApplication?.processIdentifier == pid { finish() }
    }
}
