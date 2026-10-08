import Cocoa

/// Owns AX references created on a worker. The main owner only reads copied
/// minima; no shared AccessibilityElement changes its timeout during a drag.
struct WindowDividerPreparedPair {
    struct Input {
        let id: CGWindowID
        let pid: pid_t
        let launch: TimeInterval
        let bundle: String?
        init?(id: CGWindowID, pid: pid_t) {
            guard let launch = WindowProcessIdentity.launchTime(for: pid) else { return nil }
            self.id = id; self.pid = pid; self.launch = launch
            bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        var isCurrent: Bool { WindowProcessIdentity.launchTime(for: pid) == launch }
    }
    struct Window {
        let input: Input
        let element: AXUIElement
        let minimum: CGSize?
    }
    let left: Window
    let right: Window

    init?(left: Input, right: Input) {
        guard let l = Self.read(left), let r = Self.read(right) else { return nil }
        self.left = l; self.right = r
    }

    static func read(_ input: Input) -> Window? {
        guard input.isCurrent else { return nil }
        let reader = AccessibilityReadBatch(budget: 0.2)
        guard let windows = reader.value(AXUIElementCreateApplication(input.pid), kAXWindowsAttribute) as? [AXUIElement],
              let element = windows.first(where: { reader.windowID($0) == input.id }),
              reader.value(element, kAXRoleAttribute) as? String == kAXWindowRole,
              reader.value(element, kAXSubroleAttribute) as? String != kAXSystemDialogSubrole,
              reader.value(element, kAXMinimizedAttribute) as? Bool != true,
              reader.settable(element, kAXSizeAttribute) != false else { return nil }
        let minimum: CGSize? = reader.wrapped(element, "AXMinSize", type: .cgSize)
            ?? reader.wrapped(element, "AXMinimumSize", type: .cgSize)
        guard reader.available, input.isCurrent else { return nil }
        return Window(input: input, element: element, minimum: minimum)
    }

    /// Called on the placement/observation worker, never from pointer tracking.
    static func passiveCaptureOverlayIDs(in infos: [WindowInfo], at point: CGPoint?, ownedPIDs: Set<pid_t>) -> Set<CGWindowID> {
        guard let point else { return [] }
        let capturePIDs = Set(infos.filter { $0.isOnScreen && $0.frame.contains(point) }.compactMap { info in
            NSRunningApplication(processIdentifier: info.pid)?.bundleIdentifier == "com.apple.screencaptureui" ? info.pid : nil
        })
        guard !capturePIDs.isEmpty else { return [] }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)
        var hit: AXUIElement?
        var pid: pid_t = 0
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit, AXUIElementGetPid(hit, &pid) == .success else { return [] }
        return WindowDividerGeometry.passiveCaptureOverlayIDs(in: infos, at: point, hitPID: pid,
            ownedPIDs: ownedPIDs, capturePIDs: capturePIDs)
    }

    func place(left originalLeft: CGRect, right originalRight: CGRect, axis: WindowSplitAxis, divider: CGFloat,
               minimumLeft: CGFloat, minimumRight: CGFloat, remembered: (left: CGFloat?, right: CGFloat?)?,
               ignoring: Set<CGWindowID>, hoverFrame: CGRect, policy: EnhancedUI, assistive: Bool,
               cancellation: WindowPlacementCoordinator.Cancellation) -> WindowDividerPlacement.Result? {
        let valid = { !cancellation.isCancelled && self.left.input.isCurrent && self.right.input.isCurrent }
        guard valid() else { return nil }
        let infos = WindowUtil.getWindowList(forceRefresh: true, cacheResult: false)
        let passive = Self.passiveCaptureOverlayIDs(in: infos, at: CGEvent(source: nil)?.location,
            ownedPIDs: [left.input.pid, right.input.pid, getpid()])
        guard WindowDividerGeometry.unobscured(left: left.input.id, right: right.input.id,
            in: infos, near: hoverFrame, ignoring: ignoring.union(passive)),
              WindowGeometry.matches(infos.first { $0.id == left.input.id && $0.pid == left.input.pid }?.frame ?? .null, originalLeft),
              WindowGeometry.matches(infos.first { $0.id == right.input.id && $0.pid == right.input.pid }?.frame ?? .null, originalRight), valid() else { return nil }
        let l = PlacementWindowElement(left.element, windowID: left.input.id)
        let r = PlacementWindowElement(right.element, windowID: right.input.id)
        guard WindowGeometry.matches(l.frame, originalLeft), valid(),
              WindowGeometry.matches(r.frame, originalRight), valid() else { return nil }
        var restores: [() -> Void] = []
        defer { restores.reversed().forEach { $0() } }
        // Capture AppKit policy on the main owner; AX preparation and cleanup
        // share the placement worker and its bounded application references.
        var preparedPIDs = Set<pid_t>()
        for window in [left, right] where preparedPIDs.insert(window.input.pid).inserted {
            guard valid() else { return nil }
            let app = AXUIElementCreateApplication(window.input.pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            restores.append(policy.beginWindowAdjustment(bundleIdentifier: window.input.bundle,
                builtInAssistiveTechnologyEnabled: assistive,
                readEnhancedUI: {
                    var value: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value) == .success else { return nil }
                    return value as? Bool
                }, writeEnhancedUI: { enabled in
                    _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString,
                        enabled ? kCFBooleanTrue : kCFBooleanFalse)
                }))
        }
        guard valid(), let placement = WindowDividerPlacement(left: originalLeft, right: originalRight,
            axis: axis, divider: divider, minimumLeft: minimumLeft, minimumRight: minimumRight,
            rememberedMinimumLeft: remembered?.left, rememberedMinimumRight: remembered?.right,
            write: { isLeft, frame, attribute in
                guard valid() else { return false }
                let window = isLeft ? l : r
                return cancellation.write {
                    attribute == .size ? window.writeSize(frame.size) : window.writePosition(frame.origin)
                } == .success
            }, read: { isLeft in valid() ? (isLeft ? l : r).frame : .null },
            acknowledged: { isLeft, expected in
                guard valid(), let actual = WindowUtil.getWindowFrame(id: isLeft ? left.input.id : right.input.id) else { return false }
                return WindowGeometry.matches(actual, expected, tolerance: 1)
            }) else { return nil }
        return placement.settle(isCurrent: valid)
    }
}
