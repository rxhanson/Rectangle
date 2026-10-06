import Cocoa

enum WindowAccessibilityLookup {
    enum Result {
        case found(AXUIElement)
        case unavailable
        case timedOut
        case cancelled
    }

    static func resolve(pid: pid_t, id: CGWindowID, launch: TimeInterval,
                        preferred: AXUIElement?, isCurrent: @escaping () -> Bool) -> AXUIElement? {
        if case .found(let element) = resolveResult(pid: pid, id: id, launch: launch,
            preferred: preferred, isCurrent: isCurrent) { return element }
        return nil
    }

    static func resolveResult(pid: pid_t, id: CGWindowID, launch: TimeInterval,
                              preferred: AXUIElement?, isCurrent: @escaping () -> Bool) -> Result {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        func valid() -> Bool { isCurrent() && WindowProcessIdentity.launchTime(for: pid) == launch }
        while valid(), ProcessInfo.processInfo.systemUptime < deadline {
            let reader = AccessibilityReadBatch(budget: deadline - ProcessInfo.processInfo.systemUptime, isCurrent: valid)
            // Activation can stall AXWindows even while the selected window responds.
            if let preferred {
                var owner: pid_t = 0
                if AXUIElementGetPid(preferred, &owner) == .success, owner == pid,
                   reader.windowID(preferred) == id, valid() { return .found(preferred) }
            }
            if reader.available,
               let windows = reader.value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement],
               let window = windows.first(where: { reader.windowID($0) == id }),
               reader.available, valid() { return .found(window) }
            guard valid() else { return .cancelled }
            guard reader.timedOut else { return reader.available ? .unavailable : .timedOut }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { Thread.sleep(forTimeInterval: min(0.02, remaining)) }
        }
        return valid() ? .timedOut : .cancelled
    }
}
