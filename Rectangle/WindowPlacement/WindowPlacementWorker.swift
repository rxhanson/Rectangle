import Cocoa

/// Serial writes wait for acknowledgement before advancing to the next property.
/// In particular a delayed size write must not be replaced by a position write
/// built from the app's old size. No observation in this phase learns a minimum.
final class WindowPlacementWorker {
    let pid: pid_t
    let id: CGWindowID
    let launch: TimeInterval
    let cancellation: WindowPlacementCoordinator.Cancellation
    let preferred: AXUIElement
    private var window: AccessibilityElement?
    private var timedOut = false

    init(pid: pid_t, id: CGWindowID, launch: TimeInterval, preferred: AXUIElement,
         cancellation: WindowPlacementCoordinator.Cancellation) {
        self.pid = pid; self.id = id; self.launch = launch; self.cancellation = cancellation
        self.preferred = preferred
    }

    private var valid: Bool {
        !cancellation.isCancelled && WindowProcessIdentity.launchTime(for: pid) == launch
    }

    func place(_ target: CGRect, original: CGRect, placement: WindowAnimationPlacement,
               animationEvidence: WindowPlacementAnimationEvidence? = nil,
               directPlacement: Bool = false, minimumHint: CGSize? = nil,
               acknowledgementTimeout: TimeInterval = 3.4, restoreOnFailure: Bool = true) -> WindowPlacementCoordinator.Outcome {
        guard valid else { return .cancelled }
        if let element = WindowAccessibilityLookup.resolve(pid: pid, id: id, launch: launch,
            preferred: preferred, isCurrent: { self.valid }) {
            window = AccessibilityElement(element, messagingTimeout: 0.05, windowID: id)
        }
        guard let window else {
            WindowAnimationDiagnostics.event("placement-unresponsive", fields: ["windowID": id,
                "operation": "lookup"])
            return valid ? .unresponsive : .cancelled
        }
        window.setMessagingTimeout(0.05)
        let start = ProcessInfo.processInfo.systemUptime
        if let frame = settle(target, bounds: placement.screenFrame, deadline: start + acknowledgementTimeout,
                              placement: placement, original: original, animationEvidence: animationEvidence,
                              directPlacement: directPlacement, minimumHint: minimumHint) {
            return .placed(frame)
        }
        guard valid else { return .cancelled }
        if timedOut {
            WindowAnimationDiagnostics.event("placement-unresponsive", fields: ["windowID": id,
                "operation": "acknowledgement"])
            return .unresponsive
        }
        guard restoreOnFailure else { return .failed(restored: false) }
        // Restoration has its own finite budget. It is still owned by the same
        // token, so a new drag or command can interrupt it before any next write.
        let restored = settle(original, bounds: placement.screenFrame, deadline: ProcessInfo.processInfo.systemUptime + 2.2) != nil
        guard valid else { return .cancelled }
        return .failed(restored: restored)
    }

    private func agreedFrame() -> CGRect? {
        guard valid, let window else { return nil }
        let frame = window.frame
        if frame.isNull {
            if !timedOut {
                WindowAnimationDiagnostics.event("placement-ack-timeout", fields: ["windowID": id, "operation": "frame-read"])
            }
            timedOut = true; return nil
        }
        timedOut = false
        guard valid, let server = WindowUtil.getWindowFrame(id: id),
              WindowAnimationGeometry.valid(frame), WindowAnimationGeometry.near(frame, server, tolerance: 1) else { return nil }
        return frame
    }

    private func settle(_ target: CGRect, bounds: CGRect, deadline: TimeInterval,
                        placement: WindowAnimationPlacement? = nil, original: CGRect? = nil,
                        animationEvidence: WindowPlacementAnimationEvidence? = nil,
                        directPlacement: Bool = false, minimumHint: CGSize? = nil) -> CGRect? {
        guard let window else { return nil }
        var state = WindowPlacementAcknowledgement(target: target, startedAt: ProcessInfo.processInfo.systemUptime,
                                                    pendingWrite: false, bounds: bounds, placement: placement, original: original,
                                                    reportedMinimum: window.reportedMinimumSize, animationEvidence: animationEvidence,
                                                    directPlacement: directPlacement, minimumHint: minimumHint)
        while valid && ProcessInfo.processInfo.systemUptime < deadline {
            let now = ProcessInfo.processInfo.systemUptime
            let frame = agreedFrame()
            switch state.observe(frame, at: now) {
            case .complete(let frame): return frame
            case .position(let point):
                guard let result = cancellation.write({ window.writePosition(point) }) else { return nil }
                if result == .cannotComplete {
                    WindowAnimationDiagnostics.event("placement-ack-timeout", fields: ["windowID": id, "operation": "position-write"])
                    timedOut = true
                }
                // A timed-out write may still have been applied. Let readback
                // acknowledge it before the existing bounded retry can resend.
                guard result == .success || result == .cannotComplete else { return nil }
            case .size(let size):
                guard let result = cancellation.write({ window.writeSize(size) }) else { return nil }
                if result == .cannotComplete {
                    WindowAnimationDiagnostics.event("placement-ack-timeout", fields: ["windowID": id, "operation": "size-write"])
                    timedOut = true
                }
                guard result == .success || result == .cannotComplete else { return nil }
            case .failed: return nil
            case .waiting: break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }
}
