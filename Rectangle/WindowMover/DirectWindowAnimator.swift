/// DirectWindowAnimator.swift

import Cocoa

/// Animates the actual window through Accessibility frame writes.
final class DirectWindowAnimator {
    private struct PendingRelease {
        let destination: CGRect
        var stability: WindowReleasedSnapStability
        let start: (CGRect) -> Void
        let fallback: () -> Void
    }

    private var window: AccessibilityElement?
    private var animation: WindowFrameAnimation?
    private var pendingRelease: PendingRelease?
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var intent = UUID()
    private let enabled: () -> Bool
    private let clock: () -> TimeInterval
    private let automaticallyAdvances: Bool
    private let environmentIsSafe: () -> Bool
    private let serverFrame: (AccessibilityElement) -> CGRect?
    private let crossesDisplays: (CGRect, CGRect) -> Bool
    private var lastEnvironmentCheck: TimeInterval = 0

    init(enabled: @escaping () -> Bool = { WindowAnimator.enabled && Defaults.windowAnimationStyle.value == .direct },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallyAdvances: Bool = true,
         environmentIsSafe: @escaping () -> Bool = { !WindowFrostInterruptionPolicy.missionControlActive },
         serverFrame: @escaping (AccessibilityElement) -> CGRect? = { element in
             element.windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
         },
         crossesDisplays: @escaping (CGRect, CGRect) -> Bool = { WindowAnimator.crossesDisplays(from: $0, to: $1) }) {
        self.enabled = enabled
        self.clock = clock
        self.automaticallyAdvances = automaticallyAdvances
        self.environmentIsSafe = environmentIsSafe
        self.serverFrame = serverFrame
        self.crossesDisplays = crossesDisplays
    }

    func destination(for element: AccessibilityElement) -> CGRect? {
        window == element ? (pendingRelease?.destination ?? animation?.destination) : nil
    }

    func cancel(for element: AccessibilityElement) {
        if window == element { cancel() }
    }

    func cancel() {
        if pendingRelease != nil { clearPendingRelease() }
        animation?.cancel()
    }
    func cancelIfTargetDiffers(from pid: pid_t?) {
        if let pid, let targetPID = window?.pid, pid != targetPID { cancel() }
    }
    func finish() {
        if let pending = pendingRelease {
            clearPendingRelease()
            pending.fallback()
        } else { animation?.finish() }
    }

    func mouseDown() {
        // A new grab supersedes a released snap that has not started writing.
        if pendingRelease != nil { cancel() }
        else { finish() }
    }

    func advance(at time: TimeInterval) {
        if time - lastEnvironmentCheck >= 0.1 {
            lastEnvironmentCheck = time
            guard environmentIsSafe() else { cancel(); return }
        }
        guard enabled() else { finish(); return }
        if var pending = pendingRelease, let window {
            let ax = window.frame
            let server = serverFrame(window)
            let decision = pending.stability.observe(ax: ax, server: server, at: time)
            if decision == .waiting {
                pendingRelease = pending
                return
            }
            clearPendingRelease()
            WindowFrostDiagnostics.event("direct-released-snap-settled", fields: ["windowID": window.windowId ?? 0,
                "ready": decision == .ready, "milliseconds": (time - pending.stability.startedAt) * 1000])
            if decision == .ready { pending.start(ax) }
            else { pending.fallback() }
            return
        }
        animation?.tick(at: time)
    }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration, resizeOnly: Bool,
                 releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement?, offset: @escaping () -> CGPoint,
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value, completion: @escaping (CGRect) -> Void) {
        let generation = UUID()
        intent = generation
        if window == element { cancel() } else { finish() }
        // Finishing the previous window can synchronously submit a newer request.
        guard intent == generation else { return }
        if releasedSnap && !resizeOnly {
            window = element
            lastEnvironmentCheck = clock()
            pendingRelease = PendingRelease(destination: destination,
                stability: WindowReleasedSnapStability(startedAt: clock()), start: { [weak self] origin in
                    guard let self, self.intent == generation else { return }
                    // Native display adjustments can replay old geometry during
                    // direct motion. Let the caller place a cross-display snap
                    // normally, without issuing intermediate animation frames.
                    if self.crossesDisplays(origin, destination) {
                        WindowFrostDiagnostics.event("direct-cross-display-snap-immediate", fields: [
                            "windowID": element.windowId ?? 0,
                            "source": [origin.minX, origin.minY, origin.width, origin.height],
                            "destination": [destination.minX, destination.minY, destination.width, destination.height]])
                        completion(.null)
                        return
                    }
                    self.startAnimation(element, from: origin, to: destination, duration: duration,
                                        resizeOnly: resizeOnly, placement: placement, offset: offset,
                                        curve: curve, completion: completion)
                }, fallback: { completion(.null) })
            WindowFrostDiagnostics.event("direct-released-snap-wait", fields: ["windowID": element.windowId ?? 0])
            startDriving()
            advance(at: clock())
            return
        }
        startAnimation(element, from: startingFrame, to: destination, duration: duration,
                       resizeOnly: resizeOnly, placement: placement, offset: offset, curve: curve, completion: completion)
    }

    private func startAnimation(_ element: AccessibilityElement, from startingFrame: CGRect?, to destination: CGRect,
                                duration: TimeInterval, resizeOnly: Bool, placement: WindowAnimationPlacement?,
                                offset: @escaping () -> CGPoint, curve: @escaping (Double) -> CGFloat,
                                completion: @escaping (CGRect) -> Void) {
        let origin = startingFrame ?? element.frame
        guard enabled(), environmentIsSafe(), element.isFullScreen != true,
              !origin.isNull, !destination.isNull, !origin.isEmpty, !destination.isEmpty,
              [origin.minX, origin.minY, origin.width, origin.height,
               destination.minX, destination.minY, destination.width, destination.height].allSatisfy(\.isFinite),
              origin != destination else { completion(.null); return }
        let restoreAccessibility = element.beginAnimatedAdjustment()
        var finalFrame: CGRect?
        var finalized = false
        lastEnvironmentCheck = clock()
        window = element
        WindowFrostDiagnostics.event("direct-animation-start", fields: ["windowID": element.windowId ?? 0,
            "source": [origin.minX, origin.minY, origin.width, origin.height],
            "destination": [destination.minX, destination.minY, destination.width, destination.height],
            "resizeOnly": resizeOnly, "duration": duration])
        animation = WindowFrameAnimation(from: origin, to: destination, startTime: clock(), duration: duration,
                                         offset: offset, curve: curve, write: { frame, progress in
            if let placement {
                _ = element.setConstrainedAnimationFrame(frame, placement: placement, origin: origin, progress: progress)
                return true
            }
            return element.setAnimationFrame(frame, resizeOnly: resizeOnly)
        }, finalize: { frame in
            finalized = true
            if let placement {
                finalFrame = element.setConstrainedAnimationFrame(frame, placement: placement, origin: origin, progress: 1)
            }
        }, cleanup: { [weak self] in
            self?.stopDriving()
            self?.animation = nil
            self?.window = nil
            restoreAccessibility()
            if !finalized { WindowFrostDiagnostics.event("direct-animation-cancel", fields: ["windowID": element.windowId ?? 0]) }
        }, completion: { requested in
            if placement == nil {
                // Restore the normal AX timeout before settling native display adjustments.
                element.setFrame(requested, adjustSizeFirst: false, adjustPosition: !resizeOnly)
                let achieved = element.frame
                let sizeMatches = abs(achieved.width - requested.width) <= 1
                    && abs(achieved.height - requested.height) <= 1
                let positionMatches = resizeOnly || (abs(achieved.minX - requested.minX) <= 1
                    && abs(achieved.minY - requested.minY) <= 1)
                if !achieved.isNull, sizeMatches, positionMatches { finalFrame = achieved }
            }
            let frame = finalFrame ?? .null
            WindowFrostDiagnostics.event("direct-animation-complete", fields: ["windowID": element.windowId ?? 0,
                "placed": !frame.isNull])
            completion(frame)
        })
        startDriving()
    }

    private func clearPendingRelease() {
        pendingRelease = nil
        window = nil
        stopDriving()
    }

    private func stopDriving() {
        timer?.invalidate()
        timer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func startDriving() {
        guard automaticallyAdvances else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.advance(at: self.clock())
        }
        self.timer = timer
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() }
        RunLoop.main.add(timer, forMode: .common)
    }
}
