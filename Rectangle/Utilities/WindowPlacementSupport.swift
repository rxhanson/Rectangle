import Cocoa
import Darwin

enum WindowProcessIdentity {
    /// Launch Services may omit launchDate for apps started by an executable.
    /// Kernel start time still distinguishes a reused PID without an AX query.
    static func launchTime(for pid: pid_t) -> TimeInterval? {
        var info = proc_bsdinfo()
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size {
            return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
                .timeIntervalSinceReferenceDate
        }
        return NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSinceReferenceDate
    }
}

enum WindowAccessibilityLookup {
    static func resolve(pid: pid_t, id: CGWindowID, launch: TimeInterval,
                        preferred: AXUIElement?, isCurrent: () -> Bool) -> AXUIElement? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        func valid() -> Bool { isCurrent() && WindowProcessIdentity.launchTime(for: pid) == launch }
        while valid(), ProcessInfo.processInfo.systemUptime < deadline {
            let reader = AccessibilityReadBatch(budget: deadline - ProcessInfo.processInfo.systemUptime)
            // Activation can stall AXWindows even while the selected window responds.
            if let preferred {
                var owner: pid_t = 0
                if AXUIElementGetPid(preferred, &owner) == .success, owner == pid,
                   reader.windowID(preferred) == id, valid() { return preferred }
            }
            if reader.available,
               let windows = reader.value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement],
               let window = windows.first(where: { reader.windowID($0) == id }),
               reader.available, valid() { return window }
            guard reader.timedOut, valid() else { return nil }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { Thread.sleep(forTimeInterval: min(0.02, remaining)) }
        }
        return nil
    }
}

/// All attribute reads share one deadline. Stop on timeout; skip unsupported
/// optional attributes without extending the deadline.
final class AccessibilityReadBatch {
    private let deadline: TimeInterval
    private var failed = false
    var timedOut: Bool { failed }
    init(budget: TimeInterval) { deadline = ProcessInfo.processInfo.systemUptime + budget }
    var available: Bool { !failed && ProcessInfo.processInfo.systemUptime < deadline }
    private func prepare(_ element: AXUIElement) -> Bool {
        guard available else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(0.05, max(0.001, deadline - ProcessInfo.processInfo.systemUptime))))
        return true
    }
    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard prepare(element) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        if status == .cannotComplete { failed = true }
        return status == .success ? result : nil
    }
    func windowID(_ element: AXUIElement) -> CGWindowID? {
        guard prepare(element) else { return nil }
        var id: CGWindowID = 0
        let status = _AXUIElementGetWindow(element, &id)
        if status == .cannotComplete { failed = true }
        return status == .success && id != 0 ? id : nil
    }
    func wrapped<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> T? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(value as! AXValue, type, pointer) ? pointer.pointee : nil
    }
    func settable(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard prepare(element) else { return nil }
        var result = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute as CFString, &result)
        if status == .cannotComplete { failed = true }
        return status == .success ? result.boolValue : nil
    }
    func observe(_ observer: AXObserver, _ element: AXUIElement, _ notification: String,
                 context: UnsafeMutableRawPointer) {
        guard prepare(element) else { return }
        if AXObserverAddNotification(observer, element, notification as CFString, context) == .cannotComplete {
            failed = true
        }
    }
}

// Placement workers serialize AX writes; callbacks return to the main run loop.
extension WindowAnimator {
    private static let placementQueue = DispatchQueue(label: "com.knollsoft.Rectangle.placement")
    private static var pendingPlacements = 0

    func performPlacementWork(_ body: @escaping () -> Void) {
        Self.pendingPlacements += 1
        Self.placementQueue.async {
            body()
            DispatchQueue.main.async { Self.pendingPlacements -= 1 }
        }
    }

    func afterPendingWrites(isCurrent: @escaping () -> Bool = { true },
                            onCancelled: @escaping () -> Void = {},
                            _ body: @escaping () -> Void) {
        let resume = {
            guard isCurrent() else { onCancelled(); return }
            body()
        }
        if Self.pendingPlacements == 0 { resume(); return }
        Self.placementQueue.async { DispatchQueue.main.async(execute: resume) }
    }
}
