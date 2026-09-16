/// DirectWindowAnimator.swift

import Cocoa
import QuartzCore

/// Animates the actual window through Accessibility frame writes.
final class DirectWindowAnimator {
    private struct PendingRelease {
        let destination: CGRect
        var stability: WindowReleasedSnapStability
        let start: (CGRect) -> Void
        let fallback: () -> Void
    }

    private struct PendingSettlement {
        let destination: CGRect
        let origin: CGRect
        let placement: WindowAnimationPlacement
        var stability: WindowAnimationSettlement
        let cleanup: () -> Void
        var completion: (CGRect) -> Void
    }

    private final class KeyboardSession {
        var motion: WindowKeyboardMotion
        var placement: WindowAnimationPlacement
        var completion: (CGRect) -> Void
        let cleanup: () -> Void
        var previousFrame: CGRect
        var lastSampledFrame: CGRect?
        var lastWriteTime: TimeInterval
        var sizeFeedback = WindowAnimationSizeFeedback()
        var recentWrites: [(time: TimeInterval, values: [CGFloat], velocity: [CGFloat])] = []

        init(origin: CGRect, destination: CGRect, placement: WindowAnimationPlacement, at time: TimeInterval,
             cleanup: @escaping () -> Void, completion: @escaping (CGRect) -> Void) {
            motion = WindowKeyboardMotion(from: origin, to: destination, at: time)
            self.placement = placement
            self.cleanup = cleanup
            self.completion = completion
            previousFrame = origin
            lastWriteTime = time
        }
    }

    private var keyboardSession: KeyboardSession?
    private var settlementIsKeyboard = false
    private var window: AccessibilityElement?
    private var animation: WindowFrameAnimation?
    private var pendingRelease: PendingRelease?
    private var pendingSettlement: PendingSettlement?
    private var timer: Timer?
    private var displayLinkCleanup: (() -> Void)?
    private var screenObserver: NSObjectProtocol?
    private var lastDrivenAt: TimeInterval?
    private var drivingInterval: TimeInterval = 1.0 / 60
    private var advancing = false
    private var mouseMonitor: Any?
    private var intent = UUID()
    private let enabled: () -> Bool
    private let clock: () -> TimeInterval
    private let automaticallyAdvances: Bool
    private let environmentIsSafe: () -> Bool
    private let serverFrame: (AccessibilityElement) -> CGRect?
    private let crossesDisplays: (CGRect, CGRect) -> Bool
    private let isNativeResizeApp: (String?) -> Bool
    private var lastEnvironmentCheck: TimeInterval = 0

    init(enabled: @escaping () -> Bool = { WindowAnimator.enabled },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallyAdvances: Bool = true,
         environmentIsSafe: @escaping () -> Bool = { !WindowAnimationInterruptionPolicy.missionControlActive },
         serverFrame: @escaping (AccessibilityElement) -> CGRect? = { element in
             element.windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
         },
         crossesDisplays: @escaping (CGRect, CGRect) -> Bool = { WindowAnimator.crossesDisplays(from: $0, to: $1) },
         isNativeResizeApp: @escaping (String?) -> Bool = { id in
             guard let id else { return false }
             return Defaults.directAnimationNativeResizeApps.typedValue?.contains(id) == true
         }) {
        self.enabled = enabled
        self.clock = clock
        self.automaticallyAdvances = automaticallyAdvances
        self.environmentIsSafe = environmentIsSafe
        self.serverFrame = serverFrame
        self.crossesDisplays = crossesDisplays
        self.isNativeResizeApp = isNativeResizeApp
    }

    func destination(for element: AccessibilityElement) -> CGRect? {
        window == element ? (pendingRelease?.destination ?? pendingSettlement?.destination ?? keyboardSession?.motion.destination ?? animation?.destination) : nil
    }

    func cancel(for element: AccessibilityElement) {
        if window == element { cancel() }
    }

    func cancel() {
        if let session = keyboardSession {
            keyboardSession = nil
            window = nil
            stopDriving()
            session.cleanup()
        }
        if pendingRelease != nil { clearPendingRelease() }
        if pendingSettlement != nil { clearSettlement() }
        animation?.cancel()
    }
    func cancelIfTargetDiffers(from pid: pid_t?) {
        if let pid, let targetPID = window?.pid, pid != targetPID { cancel() }
    }
    func finish() {
        if keyboardSession != nil {
            finishKeyboard()
            if pendingSettlement != nil { completeSettlement(.null) }
            return
        }
        if let pending = pendingRelease {
            clearPendingRelease()
            pending.fallback()
        } else if pendingSettlement != nil {
            completeSettlement(.null)
        } else {
            animation?.finish()
            // An explicit finish must not leave a newly created settlement
            // attached to the next window's animation.
            if pendingSettlement != nil { completeSettlement(.null) }
        }
    }

    func mouseDown() {
        // A new grab supersedes a released snap that has not started writing.
        if keyboardSession != nil || pendingRelease != nil || pendingSettlement != nil { cancel() }
        else { finish() }
    }

    func advance(at time: TimeInterval) {
        guard !advancing else { return }
        advancing = true
        defer { advancing = false }
        if time - lastEnvironmentCheck >= 0.1 {
            lastEnvironmentCheck = time
            guard environmentIsSafe() else { cancel(); return }
        }
        guard enabled() else { finish(); return }
        if var pending = pendingSettlement, let window {
            let decision = pending.stability.observe(ax: window.frame, server: serverFrame(window),
                destination: pending.destination, placement: pending.placement, origin: pending.origin, at: clock())
            pendingSettlement = pending
            switch decision {
            case .waiting: break
            case .retrySize:
                if window.writeAnimationSize(pending.destination.size) != .success { completeSettlement(.null) }
            case .retrySizeAt(let position):
                // Keep the retry position, size and final alignment in one turn.
                // Waiting between them exposes the temporary position at the edge.
                guard window.writeAnimationPosition(position) == .success,
                      window.setConstrainedAnimationFrame(pending.destination, placement: pending.placement,
                          origin: pending.origin, progress: 1) != nil else {
                    completeSettlement(.null)
                    return
                }
            case .align(let frame):
                if window.writeAnimationPosition(frame.origin) != .success { completeSettlement(.null) }
            case .complete(let frame): completeSettlement(frame)
            case .failed: completeSettlement(.null)
            }
            return
        }
        if var pending = pendingRelease, let window {
            let ax = window.frame
            let server = serverFrame(window)
            let decision = pending.stability.observe(ax: ax, server: server, at: time)
            if decision == .waiting {
                pendingRelease = pending
                return
            }
            clearPendingRelease()
            WindowAnimationDiagnostics.event("direct-released-snap-settled", fields: ["windowID": window.windowId ?? 0,
                "ready": decision == .ready, "milliseconds": (time - pending.stability.startedAt) * 1000])
            if decision == .ready { pending.start(ax) }
            else { pending.fallback() }
            return
        }
        if keyboardSession != nil { advanceKeyboard(at: time) }
        else { animation?.tick(at: time) }
    }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration, resizeOnly: Bool,
                 releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement?, profile: WindowAnimationProfile = .standard,
                 offset: @escaping () -> CGPoint,
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value, completion: @escaping (CGRect) -> Void) {
        let generation = UUID()
        intent = generation
        if profile == .keyboard, !releasedSnap, !resizeOnly, !isNativeResizeApp(element.bundleIdentifier) {
            animateKeyboard(element, to: destination, placement: placement, generation: generation, completion: completion)
            return
        }
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
                        WindowAnimationDiagnostics.event("direct-cross-display-snap-immediate", fields: [
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
            WindowAnimationDiagnostics.event("direct-released-snap-wait", fields: ["windowID": element.windowId ?? 0])
            startDriving()
            advance(at: clock())
            return
        }
        startAnimation(element, from: startingFrame, to: destination, duration: duration,
                       resizeOnly: resizeOnly, placement: placement, offset: offset, curve: curve, completion: completion)
    }

    private func animateKeyboard(_ element: AccessibilityElement, to destination: CGRect,
                                 placement: WindowAnimationPlacement?, generation: UUID,
                                 completion: @escaping (CGRect) -> Void) {
        guard enabled(), environmentIsSafe(), element.isFullScreen != true,
              WindowAnimationGeometry.valid(destination) else { completion(.null); return }
        let placement = placement ?? WindowAnimationPlacement(screenFrame: .zero, sharedEdges: nil,
                                                               constrainToScreen: false, gap: 0)
        let now = clock()
        if window == element, let session = keyboardSession {
            session.completion = completion
            if session.motion.destination == destination, session.placement == placement { return }
            let ax = element.frame
            let visible = serverFrame(element).flatMap { WindowAnimationGeometry.valid($0) ? $0 : nil }
            // Continue after the latest acknowledged write; replaying a delayed
            // compositor frame would move the window back along the old path.
            let actual = WindowAnimationGeometry.valid(ax) ? ax : (visible ?? ax)
            guard WindowAnimationGeometry.valid(actual) else { cancel(); completion(.null); return }
            let observed = [actual.minX, actual.minY, actual.width, actual.height]
            let corroborating = visible ?? actual
            let accessible = [corroborating.minX, corroborating.minY, corroborating.width, corroborating.height]
            // WindowServer may still show an earlier successful AX write. Match
            // recent geometry before treating that delay as an external change.
            let recent = session.recentWrites.filter { now - $0.time <= 0.06 }
            var velocity = [CGFloat](repeating: 0, count: 4)
            for index in velocity.indices {
                if recent.contains(where: { abs($0.values[index] - accessible[index]) <= 2 }),
                   let write = recent.last(where: { abs($0.values[index] - observed[index]) <= 2 }) {
                    velocity[index] = write.velocity[index]
                }
            }
            var driftLimits: [CGFloat] = [2, 2, 2, 2]
            if placement.constrainToScreen {
                let bounds = placement.screenFrame.insetBy(dx: placement.gap, dy: placement.gap)
                driftLimits[0] = min(2, max(0, velocity[0] > 0 ? bounds.maxX - actual.maxX : actual.minX - bounds.minX))
                driftLimits[1] = min(2, max(0, velocity[1] > 0 ? bounds.maxY - actual.maxY : actual.minY - bounds.minY))
                if velocity[2] > 0 { driftLimits[2] = min(2, max(0, bounds.maxX - actual.maxX)) }
                if velocity[3] > 0 { driftLimits[3] = min(2, max(0, bounds.maxY - actual.maxY)) }
            }
            let screenChanged = session.placement.screenFrame != placement.screenFrame
            session.motion = WindowKeyboardMotion(from: actual, to: destination, velocity: velocity, at: now, driftLimits: driftLimits)
            session.placement = placement
            session.previousFrame = actual
            session.lastSampledFrame = nil
            session.lastWriteTime = now
            session.sizeFeedback = WindowAnimationSizeFeedback()
            session.recentWrites.removeAll(keepingCapacity: true)
            if screenChanged { startDriving() }
            WindowAnimationDiagnostics.event("keyboard-animation-retarget", fields: ["windowID": element.windowId ?? 0,
                "source": [actual.minX, actual.minY, actual.width, actual.height],
                "destination": [destination.minX, destination.minY, destination.width, destination.height], "velocity": velocity])
            return
        }

        var restoreAccessibility: (() -> Void)?
        var rebindDriver = true
        if window == element, settlementIsKeyboard, var pending = pendingSettlement {
            if pending.destination == destination, pending.placement == placement {
                pending.completion = completion
                pendingSettlement = pending
                return
            }
            restoreAccessibility = pending.cleanup
            rebindDriver = pending.placement.screenFrame != placement.screenFrame
            pendingSettlement = nil
            settlementIsKeyboard = false
        } else {
            if window == element { cancel() } else { finish() }
        }
        guard intent == generation else { restoreAccessibility?(); return }
        let ax = element.frame
        let origin = serverFrame(element).flatMap { WindowAnimationGeometry.valid($0) ? $0 : nil } ?? ax
        guard WindowAnimationGeometry.valid(origin) else {
            restoreAccessibility?()
            window = nil
            stopDriving()
            completion(.null)
            return
        }
        let cleanup = restoreAccessibility ?? element.beginAnimatedAdjustment()
        keyboardSession = KeyboardSession(origin: origin, destination: destination, placement: placement,
                                          at: now, cleanup: cleanup, completion: completion)
        window = element
        lastEnvironmentCheck = now
        if rebindDriver { startDriving() }
        WindowAnimationDiagnostics.event("keyboard-animation-start", fields: ["windowID": element.windowId ?? 0,
            "source": [origin.minX, origin.minY, origin.width, origin.height],
            "destination": [destination.minX, destination.minY, destination.width, destination.height]])
    }

    private func advanceKeyboard(at time: TimeInterval) {
        guard let session = keyboardSession, let window else { return }
        let sample = session.motion.sample(at: time)
        if sample.progress >= 1 { finishKeyboard(); return }
        let frame = sample.frame
        let sampled = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                             width: frame.width.rounded(), height: frame.height.rounded())
        if sampled != session.lastSampledFrame || session.previousFrame.size != sampled.size {
            var requested = sampled
            let predicted = session.sizeFeedback.size(for: sampled.size)
            if predicted != sampled.size {
                requested = session.placement.frame(for: sampled, actualSize: predicted,
                    origin: session.motion.origin, progress: sample.progress)
            }
            let correction = min(1, CGFloat(max(0, time - session.lastWriteTime)) * 60)
            if let achieved = window.setConstrainedAnimationFrame(requested, placement: session.placement,
                origin: session.motion.origin, progress: sample.progress, previousFrame: session.previousFrame,
                maximumCorrection: correction) {
                let values = [achieved.minX, achieved.minY, achieved.width, achieved.height]
                let requestedValues = [sampled.minX, sampled.minY, sampled.width, sampled.height]
                let velocity = sample.velocity.enumerated().map { index, value in
                    abs(values[index] - requestedValues[index]) <= 2 ? value : 0
                }
                session.recentWrites.removeAll { time - $0.time > 0.06 }
                session.recentWrites.append((time, values, velocity))
                session.previousFrame = achieved
                session.lastSampledFrame = sampled
                session.lastWriteTime = time
                if achieved.width < sampled.width - 1 || achieved.height < sampled.height - 1 {
                    session.sizeFeedback.observe(requested: sampled.size, actual: window.frame, server: serverFrame(window), at: time)
                } else {
                    session.sizeFeedback = WindowAnimationSizeFeedback()
                }
            }
        }
        if sampled == session.motion.destination,
           WindowAnimationGeometry.near(window.frame, sampled, tolerance: 0.001),
           serverFrame(window).map({ WindowAnimationGeometry.near($0, sampled, tolerance: 0.001) }) == true {
            finishKeyboard()
        }
    }

    private func finishKeyboard() {
        guard let session = keyboardSession, let window else { return }
        keyboardSession = nil
        let destination = session.motion.destination
        let actual = window.frame
        guard (WindowAnimationGeometry.valid(actual) && actual.size == destination.size)
                || window.writeAnimationSize(destination.size) == .success else {
            self.window = nil
            stopDriving()
            session.cleanup()
            session.completion(.null)
            return
        }
        let resized = window.frame
        if WindowAnimationGeometry.valid(resized), resized.size == destination.size, resized.origin != destination.origin {
            guard window.writeAnimationPosition(destination.origin) == .success else {
                self.window = nil
                stopDriving()
                session.cleanup()
                session.completion(.null)
                return
            }
        }
        let placed = window.frame
        let verified = WindowAnimationGeometry.near(placed, destination, tolerance: 0.001)
            && serverFrame(window).map { WindowAnimationGeometry.near($0, destination, tolerance: 0.001) } == true
        pendingSettlement = PendingSettlement(destination: destination, origin: session.motion.origin,
            placement: session.placement, stability: WindowAnimationSettlement(startedAt: clock(), verifiedFrame: verified ? placed : nil, alignmentTolerance: 0.001),
            cleanup: session.cleanup, completion: session.completion)
        settlementIsKeyboard = true
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
        // Certain apps (such as IINA) apply their aspect ratio asynchronously. Resize once, then align
        // the settled size at completion without triggering another size change.
        let nativeResize = origin.size != destination.size && isNativeResizeApp(element.bundleIdentifier)
        var nativeResizeAccepted = false
        let restoreAccessibility = element.beginAnimatedAdjustment()
        var finalFrame: CGRect?
        var previousFrame = origin
        var lastSampledFrame: CGRect?
        var sizeFeedback = WindowAnimationSizeFeedback()
        var lastWriteTime = clock()
        var reachedDestination = false
        var verifiedFinalFrame: CGRect?
        let readServer = serverFrame
        let animationClock = clock
        var finalized = false
        let needsSettlement = placement != nil && !nativeResize
        var finalResizeAccepted = false
        lastEnvironmentCheck = clock()
        window = element
        WindowAnimationDiagnostics.event("direct-animation-start", fields: ["windowID": element.windowId ?? 0,
            "source": [origin.minX, origin.minY, origin.width, origin.height],
            "destination": [destination.minX, destination.minY, destination.width, destination.height],
            "resizeOnly": resizeOnly, "duration": duration, "nativeResize": nativeResize])
        animation = WindowFrameAnimation(from: origin, to: destination, startTime: clock(), duration: duration,
                                         offset: offset, curve: curve, write: { frame, progress in
            if nativeResize { return true }
            if let placement {
                // Intermediate AX frames use whole points. Once motion rounds to
                // the same frame, leave it alone until the next distinct sample.
                // Final placement still uses the exact destination below.
                let sampledFrame = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                                          width: frame.width.rounded(), height: frame.height.rounded())
                let now = animationClock()
                if sampledFrame != lastSampledFrame || previousFrame.size != sampledFrame.size {
                    var requested = sampledFrame
                    let predictedSize = sizeFeedback.size(for: sampledFrame.size)
                    if predictedSize != sampledFrame.size {
                        requested = placement.frame(for: sampledFrame, actualSize: predictedSize, origin: origin, progress: progress)
                    }
                    let correction = min(1, CGFloat(max(0, now - lastWriteTime)) * 60)
                    if let achieved = element.setConstrainedAnimationFrame(requested, placement: placement, origin: origin,
                        progress: progress, previousFrame: previousFrame, maximumCorrection: correction) {
                        previousFrame = achieved
                        lastSampledFrame = sampledFrame
                        lastWriteTime = now
                        if achieved.width < sampledFrame.width - 1 || achieved.height < sampledFrame.height - 1 {
                            sizeFeedback.observe(requested: sampledFrame.size, actual: element.frame,
                                                 server: readServer(element), at: now)
                        } else {
                            sizeFeedback.observe(requested: sampledFrame.size, actual: achieved, server: achieved, at: now)
                        }
                    }
                }
                if sampledFrame == destination {
                    let actual = element.frame
                    reachedDestination = WindowAnimationGeometry.near(actual, destination, tolerance: 0.001)
                        && readServer(element).map { WindowAnimationGeometry.near($0, destination, tolerance: 0.001) } == true
                }
                return true
            }
            return element.setAnimationFrame(frame, resizeOnly: resizeOnly)
        }, finishedEarly: { reachedDestination }, finalize: { frame in
            finalized = true
            if nativeResize {
                guard nativeResizeAccepted else { return }
                let actual = element.frame
                guard WindowAnimationGeometry.valid(actual) else { return }
                // Restore requests carry a previously achieved size. If the native resize app
                // rejected that growth, let the ordinary mover retry it.
                if placement?.sharedEdges == nil,
                   abs(actual.width - frame.width) > 1 || abs(actual.height - frame.height) > 1 { return }
                let aligned = placement?.frame(for: frame, actualSize: actual.size, origin: origin, progress: 1)
                    ?? CGRect(origin: resizeOnly ? actual.origin : frame.origin, size: actual.size)
                if aligned.origin != actual.origin {
                    guard element.writeAnimationPosition(aligned.origin) == .success else { return }
                }
                let achieved = element.frame
                if WindowAnimationGeometry.valid(achieved),
                   abs(achieved.minX - aligned.minX) <= 1, abs(achieved.minY - aligned.minY) <= 1,
                   abs(achieved.width - aligned.width) <= 1, abs(achieved.height - aligned.height) <= 1 {
                    finalFrame = achieved
                }
            } else if placement != nil {
                // Do not align a possibly stale size and immediately report success.
                // The settlement phase verifies the achieved frame on later ticks.
                let actual = element.frame
                finalResizeAccepted = (WindowAnimationGeometry.valid(actual) && actual.size == frame.size)
                    || element.writeAnimationSize(frame.size) == .success
                if finalResizeAccepted {
                    let placed = element.frame
                    if WindowAnimationGeometry.near(placed, frame, tolerance: 0.001),
                       readServer(element).map({ WindowAnimationGeometry.near($0, frame, tolerance: 0.001) }) == true {
                        verifiedFinalFrame = placed
                    }
                }
            }
        }, cleanup: { [weak self] in
            self?.stopDriving()
            self?.animation = nil
            self?.window = nil
            if !finalized || !needsSettlement { restoreAccessibility() }
            if !finalized { WindowAnimationDiagnostics.event("direct-animation-cancel", fields: ["windowID": element.windowId ?? 0]) }
        }, completion: { [weak self] requested in
            if needsSettlement, let placement {
                guard let self, finalResizeAccepted else {
                    restoreAccessibility()
                    completion(.null)
                    return
                }
                self.window = element
                self.pendingSettlement = PendingSettlement(destination: requested, origin: origin,
                    placement: placement, stability: WindowAnimationSettlement(startedAt: self.clock(), verifiedFrame: verifiedFinalFrame),
                    cleanup: restoreAccessibility, completion: completion)
                self.startDriving()
                return
            }
            if placement == nil && !nativeResize {
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
            WindowAnimationDiagnostics.event("direct-animation-complete", fields: ["windowID": element.windowId ?? 0,
                "placed": !frame.isNull])
            completion(frame)
        })
        if nativeResize {
            if let placement {
                nativeResizeAccepted = element.setConstrainedAnimationFrame(destination, placement: placement,
                    origin: origin, progress: 1, previousFrame: origin) != nil
            } else {
                nativeResizeAccepted = element.setAnimationFrame(destination, resizeOnly: resizeOnly)
            }
            WindowAnimationDiagnostics.event("direct-native-resize-settlement", fields: [
                "windowID": element.windowId ?? 0, "accepted": nativeResizeAccepted])
        }
        startDriving()
    }

    private func clearPendingRelease() {
        pendingRelease = nil
        window = nil
        stopDriving()
    }

    private func clearSettlement() {
        let pending = pendingSettlement
        pendingSettlement = nil
        settlementIsKeyboard = false
        window = nil
        stopDriving()
        pending?.cleanup()
    }

    private func completeSettlement(_ frame: CGRect) {
        guard let pending = pendingSettlement else { return }
        WindowAnimationDiagnostics.event("direct-animation-complete", fields: [
            "windowID": window?.windowId ?? 0, "placed": !frame.isNull,
            "settlementMilliseconds": (clock() - pending.stability.startedAt) * 1000])
        clearSettlement()
        pending.completion(frame)
    }

    private func stopDriving() {
        displayLinkCleanup?()
        displayLinkCleanup = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        lastDrivenAt = nil
        timer?.invalidate()
        timer = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func drive() {
        let now = clock()
        if let lastDrivenAt, now - lastDrivenAt < drivingInterval * 0.9 { return }
        lastDrivenAt = now
        advance(at: now)
    }

    private func startDriving() {
        guard automaticallyAdvances else { return }
        stopDriving()
        let destination = pendingRelease?.destination ?? pendingSettlement?.destination ?? keyboardSession?.motion.destination ?? animation?.destination
        let screen = NSScreen.screens.max { first, second in
            func area(_ screen: NSScreen) -> CGFloat {
                guard let destination else { return 0 }
                let intersection = screen.frame.screenFlipped.intersection(destination)
                return intersection.isNull ? 0 : intersection.width * intersection.height
            }
            return area(first) < area(second)
        }
        var frameRate = 60
        if #available(macOS 12.0, *), let screen, screen.maximumFramesPerSecond > 0 {
            frameRate = min(120, screen.maximumFramesPerSecond)
        }
        drivingInterval = 1.0 / Double(frameRate)
        if #available(macOS 14.0, *), let screen {
            let target = WindowAnimationDisplayLinkTarget { [weak self] in self?.drive() }
            let link = screen.displayLink(target: target, selector: #selector(WindowAnimationDisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(frameRate), maximum: Float(frameRate), preferred: Float(frameRate))
            link.add(to: .main, forMode: .common)
            displayLinkCleanup = { link.invalidate(); _ = target }
        } else {
            let timer = Timer(timeInterval: drivingInterval, repeats: true) { [weak self] _ in self?.drive() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.finish() }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() }
    }
}

@available(macOS 14.0, *)
private final class WindowAnimationDisplayLinkTarget: NSObject {
    private let onFrame: () -> Void
    init(onFrame: @escaping () -> Void) { self.onFrame = onFrame }
    @objc func tick(_ link: CADisplayLink) { onFrame() }
}
