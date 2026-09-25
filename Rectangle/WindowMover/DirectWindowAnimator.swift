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
        var minimumHint: CGSize?
        var motion: WindowKeyboardMotion
        var placement: WindowAnimationPlacement
        var completion: (CGRect) -> Void
        let cleanup: () -> Void
        var previousFrame: CGRect
        var lastSampledFrame: CGRect?
        var lastWriteTime: TimeInterval
        var visualTime: TimeInterval
        var lastTick: TimeInterval
        var sizeFeedback = WindowAnimationSizeFeedback()
        var resizePause = WindowAnimationResizePause()
        var handoff = WindowAnimationHandoff()
        var recentWrites: [(time: TimeInterval, values: [CGFloat], velocity: [CGFloat])] = []

        init(origin: CGRect, destination: CGRect, placement: WindowAnimationPlacement, at time: TimeInterval,
             cleanup: @escaping () -> Void, completion: @escaping (CGRect) -> Void) {
            motion = WindowKeyboardMotion(from: origin, to: destination, at: time)
            self.placement = placement
            self.cleanup = cleanup
            self.completion = completion
            previousFrame = origin
            lastWriteTime = time
            visualTime = time
            lastTick = time
        }
    }

    private var keyboardSession: KeyboardSession?
    private final class HelperPreparation {
        let destination: CGRect
        let origin: CGRect
        let placement: WindowAnimationPlacement
        let duration: TimeInterval
        let initialSize: CGSize
        let startedAt: TimeInterval
        let cleanup: () -> Void
        let completion: (CGRect) -> Void
        var previousSize: CGSize?
        var stableSince: TimeInterval?
        var retried = false

        init(destination: CGRect, origin: CGRect, placement: WindowAnimationPlacement,
             duration: TimeInterval, startedAt: TimeInterval, hint: CGSize?, cleanup: @escaping () -> Void,
             completion: @escaping (CGRect) -> Void) {
            self.destination = destination
            self.origin = origin
            self.placement = placement
            self.duration = duration
            var initialSize = WindowSizeConstraints.animationSize(destination.size, origin: origin.size, hint: hint)
            // Defer growth that needs a different origin. Moving there first
            // would introduce a visible jump before the position animation.
            if let position = placement.positionBeforeGrowing(from: origin, to: destination) {
                if position.x != origin.minX { initialSize.width = origin.width }
                if position.y != origin.minY { initialSize.height = origin.height }
            }
            self.initialSize = initialSize
            self.startedAt = startedAt
            self.cleanup = cleanup
            self.completion = completion
        }
    }
    private var helperPreparation: HelperPreparation?
    private var helperDestination: CGRect?
    private var settlementIsKeyboard = false
    private var window: AccessibilityElement?
    private var animation: WindowFrameAnimation?
    private var pendingRelease: PendingRelease?
    private var pendingSettlement: PendingSettlement?
    private let capturePauseID = UUID()
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
    private let smoothResize: Bool
    private let automaticallyAdvances: Bool
    private let environmentIsSafe: () -> Bool
    private let readServerFrame: (AccessibilityElement) -> CGRect?
    private func serverFrame(_ element: AccessibilityElement) -> CGRect? {
        if let cached = element.animationReads?.server { return cached }
        let started = ProcessInfo.processInfo.systemUptime
        let frame = readServerFrame(element)
        WindowAnimationDiagnostics.event("animation-operation", fields: ["operation": "server-read",
            "milliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000])
        element.animationReads?.server = frame
        return frame
    }
    private let crossesDisplays: (CGRect, CGRect) -> Bool
    private let minimumHint: (AccessibilityElement) -> CGSize?
    private let isNativeResizeApp: (String?) -> Bool
    private var lastEnvironmentCheck: TimeInterval = 0

    init(enabled: @escaping () -> Bool = { WindowAnimator.enabled },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallyAdvances: Bool = true, smoothResize: Bool = false,
         frameInterval: TimeInterval = 1.0 / 60,
         environmentIsSafe: @escaping () -> Bool = { !WindowAnimationInterruptionPolicy.missionControlActive },
         serverFrame: @escaping (AccessibilityElement) -> CGRect? = { element in
             element.windowId.flatMap { WindowUtil.getWindowFrame(id: $0) }
         },
         crossesDisplays: @escaping (CGRect, CGRect) -> Bool = { WindowAnimator.crossesDisplays(from: $0, to: $1) },
         minimumHint: @escaping (AccessibilityElement) -> CGSize? = { $0.rememberedMinimumSize },
         isNativeResizeApp: @escaping (String?) -> Bool = { id in
             guard let id else { return false }
             return Defaults.directAnimationNativeResizeApps.typedValue?.contains(id) == true
         }) {
        self.enabled = enabled
        self.clock = clock
        self.smoothResize = smoothResize
        self.automaticallyAdvances = automaticallyAdvances
        self.drivingInterval = frameInterval
        self.environmentIsSafe = environmentIsSafe
        self.readServerFrame = serverFrame
        self.crossesDisplays = crossesDisplays
        self.isNativeResizeApp = isNativeResizeApp
        self.minimumHint = minimumHint
    }

    func destination(for element: AccessibilityElement) -> CGRect? {
        window == element ? (helperDestination ?? pendingRelease?.destination ?? pendingSettlement?.destination ?? keyboardSession?.motion.destination ?? animation?.destination) : nil
    }

    func cancel(for element: AccessibilityElement) {
        if window == element { cancel() }
    }

    func cancel() {
        if let preparation = helperPreparation {
            helperPreparation = nil
            helperDestination = nil
            window = nil
            stopDriving()
            preparation.cleanup()
        }
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
        if let preparation = helperPreparation {
            cancel()
            preparation.completion(.null)
            return
        }
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
        if helperDestination != nil || keyboardSession != nil || pendingRelease != nil || pendingSettlement != nil { cancel() }
        else { finish() }
    }

    func advance(at time: TimeInterval) {
        guard !advancing else { return }
        advancing = true
        let observedWindow = window
        observedWindow?.animationReads = WindowAnimationReadCache()
        observedWindow?.animationIntermediateStep = animation != nil || keyboardSession != nil
        defer {
            observedWindow?.animationReads = nil
            observedWindow?.animationIntermediateStep = false
            advancing = false
        }
        if let observedWindow, observedWindow.animationIntermediateStep, helperDestination == nil {
            let now = observedWindow.animationVerificationTime ?? time
            var acknowledged = false
            if observedWindow.animationResizeNotified, observedWindow.animationResizeResponse.pendingSize != nil,
               observedWindow.animationObservedFrame != nil, !observedWindow.animationNeedsRecovery,
               !observedWindow.animationNeedsFreshGeometry, now - observedWindow.animationObservedAt < 1.0 / 20,
               let size = observedWindow.size {
                acknowledged = observedWindow.animationResizeResponse.acknowledge(size, at: now)
                if acknowledged {
                    // AX acceptance permits the next resize, but does not prove
                    // presentation. Retain the pending size in the safety bounds.
                    observedWindow.animationResizeNotified = false
                    WindowAnimationDiagnostics.event("animation-resize-acknowledged", fields: ["windowID": observedWindow.windowId ?? 0])
                }
            }
            let interval: TimeInterval = acknowledged || observedWindow.animationResizeResponse.pendingSize == nil ? 1.0 / 20 : 1.0 / 30
            let resizeResponseDue = observedWindow.animationResizeNotified
                && observedWindow.animationResizeResponse.pendingSize != nil
                && now - observedWindow.animationObservedAt >= 1.0 / 40
            if !observedWindow.animationYieldRequested && (observedWindow.animationObservedFrame == nil || observedWindow.animationNeedsRecovery
                || observedWindow.animationNeedsFreshGeometry || resizeResponseDue
                || now - observedWindow.animationObservedAt >= interval) {
                if let actual = serverFrame(observedWindow), WindowAnimationGeometry.valid(actual) {
                    observedWindow.animationObservedFrame = actual
                    observedWindow.animationObservedAt = now
                    observedWindow.animationExpectedOrigin = nil
                    observedWindow.animationResizeResponse.observe(actual.size, at: now)
                    observedWindow.animationNeedsRecovery = false
                    observedWindow.animationNeedsFreshGeometry = false
                    observedWindow.animationResizeNotified = false
                } else {
                    observedWindow.animationObservedFrame = nil
                }
            } else if let position = observedWindow.animationExpectedOrigin {
                // Successful position writes are usable between bounded samples;
                // an unacknowledged size is never substituted for the observed size.
                observedWindow.animationObservedFrame?.origin = position
            }
        } else if var policy = observedWindow?.animationPolicy, let observedWindow {
            observedWindow.animationObservedFrame = nil
            let verificationTime = observedWindow.animationVerificationTime ?? time
            policy.now = verificationTime
            if policy.needsVerification {
                let actual = observedWindow.frame
                if observedWindow.animationYieldRequested { return }
                policy.observe(ax: actual, server: serverFrame(observedWindow), at: verificationTime)
            }
            observedWindow.animationPolicy = policy
        }
        if time - lastEnvironmentCheck >= 0.1 {
            lastEnvironmentCheck = time
            guard environmentIsSafe() else { cancel(); return }
        }
        guard enabled() else { finish(); return }
        if let preparation = helperPreparation, let window {
            advanceHelperPreparation(preparation, window: window, at: time)
            return
        }
        if var pending = pendingSettlement, let window {
            let actual = window.frame
            let server = serverFrame(window)
            let decision = pending.stability.observe(ax: actual, server: server,
                destination: pending.destination, placement: pending.placement, origin: pending.origin, at: clock())
            if WindowAnimationDiagnostics.enabled {
                WindowAnimationDiagnostics.event("direct-settlement", fields: [
                    "windowID": window.windowId ?? 0, "elapsed": clock() - pending.stability.startedAt,
                    "actual": actual.dictionaryRepresentation,
                    "server": server?.dictionaryRepresentation ?? [:] as CFDictionary,
                    "target": pending.destination.dictionaryRepresentation,
                    "bounds": pending.placement.screenFrame.dictionaryRepresentation,
                    "handoffReused": pending.stability.reusedHandoff,
                    "decision": String(describing: decision)])
            }
            pendingSettlement = pending
            switch decision {
            case .waiting: break
            case .retrySize:
                if window.writeAnimationSize(pending.destination.size) != .success { completeSettlement(.null) }
            case .retrySizeAt(let position):
                // Retry the size at this small offset only. Aligning the
                // achieved size here would bypass the settlement trajectory.
                guard window.writeAnimationPosition(position) == .success,
                      window.writeAnimationSize(pending.destination.size) == .success else {
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
        element.animationPolicy = WindowAnimationWritePolicy()
        element.animationResizeResponse = WindowAnimationResizeResponse()
        element.animationObservedFrame = nil
        element.animationObservedAt = -.infinity
        element.animationExpectedOrigin = nil
        element.animationNeedsFreshGeometry = false
        element.animationResizeNotified = false
        element.animationDestination = destination
        element.animationEdgeProbeSent = false
        element.animationNeedsPositionStep = false
        element.animationNeedsRecovery = false
        element.animationMotionApplied = true
        let curve = profile == .layoutHelper ? WindowAnimationCurve.placementValue : curve
        if profile == .keyboard, !releasedSnap, !resizeOnly, !isNativeResizeApp(element.bundleIdentifier) {
            animateKeyboard(element, to: destination, placement: placement, generation: generation, completion: completion)
            return
        }
        if window == element { cancel() } else { finish() }
        // Finishing the previous window can synchronously submit a newer request.
        guard intent == generation else { return }
        if profile == .layoutHelper, !resizeOnly, !releasedSnap, let placement,
           !isNativeResizeApp(element.bundleIdentifier) {
            prepareHelper(element, to: destination, duration: duration, placement: placement, completion: completion)
            return
        }
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
                                        resizeOnly: resizeOnly, placement: placement, profile: profile, offset: offset,
                                        curve: curve, completion: completion)
                }, fallback: { completion(.null) })
            WindowAnimationDiagnostics.event("direct-released-snap-wait", fields: ["windowID": element.windowId ?? 0])
            startDriving()
            advance(at: clock())
            return
        }
        startAnimation(element, from: startingFrame, to: destination, duration: duration,
                       resizeOnly: resizeOnly, placement: placement, profile: profile, offset: offset, curve: curve, completion: completion)
    }

    private func prepareHelper(_ element: AccessibilityElement, to destination: CGRect,
                               duration: TimeInterval, placement: WindowAnimationPlacement,
                               completion: @escaping (CGRect) -> Void) {
        let origin = element.frame
        guard enabled(), environmentIsSafe(), element.isFullScreen != true,
              WindowAnimationGeometry.valid(origin), WindowAnimationGeometry.valid(destination),
              origin != destination else { completion(.null); return }
        let cleanup = element.beginAnimatedAdjustment()
        window = element
        helperDestination = destination
        lastEnvironmentCheck = clock()
        let preparation = HelperPreparation(destination: destination, origin: origin, placement: placement,
            duration: duration, startedAt: clock(), hint: minimumHint(element), cleanup: cleanup, completion: completion)
        helperPreparation = preparation
        if origin.size != preparation.initialSize {
            let result = element.writeAnimationSize(preparation.initialSize)
            // A timeout can still have applied the resize. Only corroborated
            // readback on subsequent ticks may accept it.
            guard result == .success || result == .cannotComplete else { finish(); return }
        }
        WindowAnimationDiagnostics.event("helper-size-request", fields: ["windowID": element.windowId ?? 0])
        startDriving()
    }

    private func advanceHelperPreparation(_ preparation: HelperPreparation, window: AccessibilityElement,
                                          at time: TimeInterval) {
        guard time - preparation.startedAt < 0.65 else { finish(); return }
        let actual = window.frame
        guard let server = serverFrame(window), WindowAnimationGeometry.valid(actual),
              WindowAnimationGeometry.near(actual, server, tolerance: 1) else {
            preparation.previousSize = nil
            preparation.stableSince = nil
            return
        }
        let exact = actual.size == preparation.initialSize
        if !exact {
            if preparation.previousSize != actual.size {
                preparation.previousSize = actual.size
                preparation.stableSince = time
                return
            }
            guard let stableSince = preparation.stableSince, time - stableSince >= 0.05 else { return }
            if !preparation.retried, actual.size == preparation.origin.size {
                preparation.retried = true
                preparation.stableSince = nil
                preparation.previousSize = nil
                let result = window.writeAnimationSize(preparation.initialSize)
                guard result == .success || result == .cannotComplete else { finish(); return }
                return
            }
        }
        helperPreparation = nil
        startHelperMotion(window, from: actual, preparation: preparation)
    }

    private func startHelperMotion(_ element: AccessibilityElement, from origin: CGRect,
                                   preparation: HelperPreparation) {
        let requested = preparation.destination
        let placement = preparation.placement
        var alignmentSize = origin.size
        if preparation.initialSize.width != requested.width {
            alignmentSize.width = max(origin.width, requested.width)
        }
        if preparation.initialSize.height != requested.height {
            alignmentSize.height = max(origin.height, requested.height)
        }
        let aligned = placement.frame(for: requested, actualSize: alignmentSize, origin: origin, progress: 1)
        let destination = CGRect(origin: aligned.origin, size: origin.size)
        let startedAt = clock()
        var previous = origin.origin
        var finalized = false
        var valid = true
        let readServer = serverFrame
        let animationClock = clock
        WindowAnimationDiagnostics.event("helper-position-start", fields: ["windowID": element.windowId ?? 0,
            "preparationMilliseconds": (startedAt - preparation.startedAt) * 1000,
            "source": origin.dictionaryRepresentation, "destination": destination.dictionaryRepresentation])
        animation = WindowFrameAnimation(from: origin, to: destination, startTime: startedAt,
            duration: preparation.duration, curve: WindowAnimationCurve.placementValue,
            maximumFrameInterval: { [weak self] in max(1.0 / 30, self?.drivingInterval ?? 1.0 / 60) },
            maximumDuration: max(0.45, preparation.duration * 1.5), write: { frame, _ in
                let position = CGPoint(x: frame.minX.rounded(), y: frame.minY.rounded())
                guard position != previous else { return true }
                let start = WindowAnimationDiagnostics.enabled ? animationClock() : nil
                let result = element.writeAnimationPosition(position)
                if let start {
                    WindowAnimationDiagnostics.event("helper-position-write", fields: ["windowID": element.windowId ?? 0,
                        "milliseconds": (animationClock() - start) * 1000,
                        "elapsed": start - startedAt, "result": result.rawValue])
                }
                guard result == .success else { valid = false; return false }
                previous = position
                return true
            }, finalize: { _ in
                finalized = true
                if valid, previous != destination.origin {
                    valid = element.writeAnimationPosition(destination.origin) == .success
                }
                if valid, preparation.initialSize != requested.size {
                    // Apply deferred growth once at the safe final origin.
                    // All intermediate animation writes remain position-only.
                    let result = element.writeAnimationSize(requested.size)
                    valid = result == .success || result == .cannotComplete
                }
            }, cleanup: { [weak self] in
                self?.stopDriving()
                self?.animation = nil
                self?.window = nil
                self?.helperDestination = nil
                if !finalized { preparation.cleanup() }
            }, completion: { [weak self] _ in
                guard let self, valid else {
                    if finalized { preparation.cleanup() }
                    preparation.completion(.null)
                    return
                }
                let actual = element.frame
                let server = readServer(element)
                let verified = WindowAnimationGeometry.near(actual, requested, tolerance: 0.001)
                    && server.map { WindowAnimationGeometry.near(actual, $0, tolerance: 0.001) } == true
                // A provisional constrained size is not a learned minimum.
                // Preserve normal verification at the final on-screen position.
                self.window = element
                self.pendingSettlement = PendingSettlement(destination: requested, origin: origin,
                    placement: placement, stability: WindowAnimationSettlement(startedAt: self.clock(),
                        verifiedFrame: verified ? actual : nil, alignmentTolerance: 0.001),
                    cleanup: preparation.cleanup, completion: preparation.completion)
                self.startDriving()
            })
        if origin.origin == destination.origin {
            // Verification need not wait for an empty position animation.
            animation?.finish()
            return
        }
        startDriving()
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
            session.minimumHint = minimumHint(element)
            session.placement = placement
            session.previousFrame = actual
            session.lastSampledFrame = nil
            session.lastWriteTime = now
            session.sizeFeedback = WindowAnimationSizeFeedback()
            session.resizePause = WindowAnimationResizePause()
            session.recentWrites.removeAll(keepingCapacity: true)
            session.handoff = WindowAnimationHandoff()
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
        keyboardSession?.minimumHint = minimumHint(element)
        window = element
        lastEnvironmentCheck = now
        if rebindDriver { startDriving() }
        WindowAnimationDiagnostics.event("keyboard-animation-start", fields: ["windowID": element.windowId ?? 0,
            "source": [origin.minX, origin.minY, origin.width, origin.height],
            "destination": [destination.minX, destination.minY, destination.width, destination.height]])
    }

    private func advanceKeyboard(at time: TimeInterval) {
        guard let session = keyboardSession, let window else { return }
        window.animationMotionApplied = true
        let priorTime = max(session.visualTime, session.motion.startedAt)
        let delta = max(0, time - session.lastTick)
        let debt = max(0, session.lastTick - priorTime)
        session.visualTime = priorTime + min(1.0 / 30, delta + (delta <= 0.025 ? min(0.004, debt * 0.25) : 0))
        session.lastTick = time
        let sample = session.motion.sample(at: session.visualTime)
        var frame = sample.frame
        frame.size = session.motion.sample(at: max(time, session.visualTime)).frame.size
        let sampled = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                             width: frame.width.rounded(), height: frame.height.rounded())
        // Read the preceding frame before issuing another write, so the two
        // window APIs have time to acknowledge the same geometry.
        let endingAt = session.motion.startedAt + WindowKeyboardMotion.duration
        if window.animationObservedFrame == nil, session.handoff.shouldSample(at: time, endingAt: endingAt) {
            session.handoff.observe(ax: window.frame, server: serverFrame(window), at: time)
        }
        if sampled != session.lastSampledFrame || session.previousFrame.size != sampled.size {
            var requested = sampled
            let plannedSize = WindowSizeConstraints.animationSize(sampled.size, origin: session.motion.origin.size, hint: session.minimumHint)
            let predicted = session.sizeFeedback.size(for: plannedSize)
            if predicted != sampled.size {
                requested = session.placement.frame(for: sampled, actualSize: predicted,
                    origin: session.motion.origin, progress: sample.progress)
            }
            let correction = min(1, CGFloat(max(0, time - session.lastWriteTime)) * 60)
            let paused = session.resizePause.motion?.sample(requested: requested, at: time)
            let effective = paused?.frame ?? requested
            if let achieved = window.setConstrainedAnimationFrame(effective, placement: session.placement,
                origin: session.motion.origin, progress: sample.progress, previousFrame: session.previousFrame,
                maximumCorrection: correction) {
                let values = [achieved.minX, achieved.minY, achieved.width, achieved.height]
                let requestedValues = [effective.minX, effective.minY, effective.width, effective.height]
                let velocity = sample.velocity.enumerated().map { index, value in
                    abs(values[index] - requestedValues[index]) <= 2 ? (paused?.velocity[index] ?? value) : 0
                }
                observeResizePause(&session.resizePause, window: window, requested: sampled.size,
                    achieved: achieved, previous: session.previousFrame, previousTime: session.lastWriteTime,
                    destination: session.motion.destination, placement: session.placement, origin: session.motion.origin,
                    at: time, endingAt: endingAt)
                session.recentWrites.removeAll { time - $0.time > 0.06 }
                session.recentWrites.append((time, values, velocity))
                session.previousFrame = achieved
                session.lastSampledFrame = sampled
                session.lastWriteTime = time
                if window.animationSizeDeferred { session.sizeFeedback = WindowAnimationSizeFeedback() }
                else if achieved.width < sampled.width - 1 || achieved.height < sampled.height - 1 {
                    session.sizeFeedback.observe(requested: sampled.size, actual: window.frame, server: serverFrame(window), at: time)
                } else {
                    session.sizeFeedback = WindowAnimationSizeFeedback()
                }
            }
        }
        if !window.animationMotionApplied { session.visualTime = priorTime }
        if time - session.motion.startedAt >= 0.6 || (sample.progress >= 1 && time >= (session.resizePause.motion?.endsAt ?? 0)) || (sampled == session.motion.destination
            && WindowAnimationGeometry.near(window.frame, sampled, tolerance: 0.001)
            && serverFrame(window).map({ WindowAnimationGeometry.near($0, sampled, tolerance: 0.001) }) == true) {
            finishKeyboard()
        }
    }

    private func finishKeyboard() {
        guard let session = keyboardSession, let window else { return }
        keyboardSession = nil
        let destination = session.motion.destination
        if let observed = window.animationObservedFrame {
            let result = observed.size == destination.size ? AXError.success : window.writeAnimationSize(destination.size)
            guard result == .success || result == .cannotComplete else {
                self.window = nil
                stopDriving()
                session.cleanup()
                session.completion(.null)
                return
            }
            pendingSettlement = PendingSettlement(destination: destination, origin: session.motion.origin,
                placement: session.placement, stability: WindowAnimationSettlement(startedAt: clock(),
                    alignmentTolerance: 0.001, probeConstrainedPosition: true,
                    initialSizeRetry: window.animationEdgeProbeSent),
                cleanup: session.cleanup, completion: session.completion)
            settlementIsKeyboard = true
            return
        }
        if let motion = session.resizePause.motion,
           writePausedPosition(window, frame: motion.destination, previous: session.previousFrame, exact: true) == nil {
            self.window = nil
            stopDriving()
            session.cleanup()
            session.completion(.null)
            return
        }
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
        let confirmed = serverFrame(window)
        let now = clock()
        session.handoff.observe(ax: placed, server: confirmed, at: now)
        let verified = WindowAnimationGeometry.near(placed, destination, tolerance: 0.001)
            && confirmed.map { WindowAnimationGeometry.near($0, destination, tolerance: 0.001) } == true
        pendingSettlement = PendingSettlement(destination: destination, origin: session.motion.origin,
            placement: session.placement, stability: WindowAnimationSettlement(startedAt: now,
                verifiedFrame: verified ? placed : nil, alignmentTolerance: 0.001,
                handoff: session.handoff.evidence(for: destination, at: now),
                probeConstrainedPosition: session.resizePause.motion != nil),
            cleanup: session.cleanup, completion: session.completion)
        settlementIsKeyboard = true
    }

    private func startAnimation(_ element: AccessibilityElement, from startingFrame: CGRect?, to destination: CGRect,
                                duration: TimeInterval, resizeOnly: Bool, placement: WindowAnimationPlacement?,
                                profile: WindowAnimationProfile,
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
        var resizePause = WindowAnimationResizePause()
        var handoff = WindowAnimationHandoff()
        let startedAt = clock()
        var lastWriteTime = clock()
        var reachedDestination = false
        var verifiedFinalFrame: CGRect?
        let readServer = serverFrame
        let animationClock = clock
        let hint = minimumHint(element)
        var finalized = false
        let needsSettlement = placement != nil && !nativeResize
        var finalResizeAccepted = false
        lastEnvironmentCheck = clock()
        window = element
        WindowAnimationDiagnostics.event("direct-animation-start", fields: ["windowID": element.windowId ?? 0,
            "source": [origin.minX, origin.minY, origin.width, origin.height],
            "destination": [destination.minX, destination.minY, destination.width, destination.height],
            "resizeOnly": resizeOnly, "duration": duration, "nativeResize": nativeResize])
        let maximumFrameInterval: () -> TimeInterval = { [weak self] in
            profile == .layoutHelper
                ? max(1.0 / 60, self?.drivingInterval ?? 1.0 / 60) : 1.0 / 30
        }
        animation = WindowFrameAnimation(from: origin, to: destination, startTime: startedAt, duration: duration,
                                         offset: offset, curve: smoothResize && origin.size != destination.size ? WindowAnimationCurve.resizeValue : curve, maximumFrameInterval: maximumFrameInterval,
                                         maximumDuration: profile == .layoutHelper ? max(0.9, duration * 3) : max(0.6, duration * 2.5),
                                         didApplyFrame: { element.animationMotionApplied },
                                         independentSizeProgress: profile != .layoutHelper,
                                         catchesUp: profile != .layoutHelper,
                                         write: { [weak self] frame, progress in
            element.animationMotionApplied = true
            element.animationIntermediateStep = progress < 1
            defer { element.animationIntermediateStep = false }
            if element.animationNeedsRecovery {
                let actual = element.animationObservedFrame ?? element.frame
                guard WindowAnimationGeometry.valid(actual), !element.animationYieldRequested else { return true }
                previousFrame = actual
                element.animationNeedsRecovery = false
                sizeFeedback = WindowAnimationSizeFeedback()
            }
            let traceStart = WindowAnimationDiagnostics.enabled ? animationClock() : nil
            defer {
                if let traceStart {
                    WindowAnimationDiagnostics.event("direct-frame-write", fields: ["windowID": element.windowId ?? 0,
                        "progress": progress, "elapsed": traceStart - startedAt,
                        "milliseconds": (animationClock() - traceStart) * 1000,
                        "requested": frame.dictionaryRepresentation,
                        "lastAccepted": previousFrame.dictionaryRepresentation])
                }
            }
            if nativeResize { return true }
            if let placement {
                // Intermediate AX frames use whole points. Once motion rounds to
                // the same frame, leave it alone until the next distinct sample.
                // Final placement still uses the exact destination below.
                let sampledFrame = CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(),
                                          width: frame.width.rounded(), height: frame.height.rounded())
                let now = animationClock()
                let endingAt = now + (self?.animation?.remainingDuration ?? 0)
                if element.animationObservedFrame == nil, handoff.shouldSample(at: now, endingAt: endingAt) {
                    let actual = element.frame
                    guard !element.animationYieldRequested else { return true }
                    handoff.observe(ax: actual, server: readServer(element), at: now)
                }
                if sampledFrame != lastSampledFrame || previousFrame.size != sampledFrame.size {
                    var requested = sampledFrame
                    let plannedSize = WindowSizeConstraints.animationSize(sampledFrame.size, origin: origin.size, hint: hint)
                    let predictedSize = sizeFeedback.size(for: plannedSize)
                    if predictedSize != sampledFrame.size {
                        requested = placement.frame(for: sampledFrame, actualSize: predictedSize, origin: origin, progress: progress)
                    }
                    let correction = profile.constraintCorrection(after: now - lastWriteTime)
                    let effective = resizePause.motion?.sample(requested: requested, at: now).frame ?? requested
                    if let achieved = element.setConstrainedAnimationFrame(effective, placement: placement, origin: origin,
                        progress: progress, previousFrame: previousFrame, maximumCorrection: correction) {
                        if profile == .standard, !resizeOnly {
                            self?.observeResizePause(&resizePause, window: element, requested: sampledFrame.size,
                                achieved: achieved, previous: previousFrame, previousTime: lastWriteTime,
                                destination: destination, placement: placement, origin: origin,
                                at: now, endingAt: endingAt)
                        }
                        previousFrame = achieved
                        lastSampledFrame = sampledFrame
                        lastWriteTime = now
                        if element.animationYieldRequested { return true }
                        if element.animationSizeDeferred { sizeFeedback = WindowAnimationSizeFeedback() }
                        else if achieved.width < sampledFrame.width - 1 || achieved.height < sampledFrame.height - 1 {
                            let actual = element.frame
                            if element.animationYieldRequested { return true }
                            sizeFeedback.observe(requested: sampledFrame.size, actual: actual,
                                                 server: readServer(element), at: now)
                        } else {
                            sizeFeedback.observe(requested: sampledFrame.size, actual: achieved, server: achieved, at: now)
                        }
                    }
                }
                if element.animationYieldRequested || element.animationNeedsRecovery { return true }
                if element.animationObservedFrame == nil, sampledFrame == destination {
                    let actual = element.frame
                    reachedDestination = WindowAnimationGeometry.near(actual, destination, tolerance: 0.001)
                        && readServer(element).map { WindowAnimationGeometry.near($0, destination, tolerance: 0.001) } == true
                }
                return true
            }
            return element.setAnimationFrame(frame, resizeOnly: resizeOnly)
        }, finishNotBefore: { resizePause.motion?.endsAt ?? -.infinity }, finishedEarly: { reachedDestination }, finalize: { [weak self] frame in
            finalized = true
            if let motion = resizePause.motion,
               self?.writePausedPosition(element, frame: motion.destination, previous: previousFrame, exact: true) == nil { return }
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
                if let actual = element.animationObservedFrame {
                    if WindowAnimationGeometry.near(actual, frame, tolerance: 0.5) {
                        finalResizeAccepted = true
                    } else if actual.size == frame.size {
                        finalResizeAccepted = true
                    } else {
                        let result = element.writeAnimationSize(frame.size)
                        // A timeout may already have applied the resize. The
                        // next settlement tick verifies it before any retry.
                        finalResizeAccepted = result == .success || result == .cannotComplete
                    }
                    return
                }
                // Do not align a possibly stale size and immediately report success.
                // The settlement phase verifies the achieved frame on later ticks.
                let actual = element.frame
                finalResizeAccepted = (WindowAnimationGeometry.valid(actual) && actual.size == frame.size)
                    || element.writeAnimationSize(frame.size) == .success
                if finalResizeAccepted {
                    var placed = element.frame
                    var confirmed = readServer(element)
                    if profile == .layoutHelper, let placement, placed.size == frame.size,
                       confirmed.map({ WindowAnimationGeometry.near(placed, $0, tolerance: 1) }) == true {
                        // Finish a corroborated final resize in the same tick.
                        // A still-oversized response must use normal settlement.
                        let aligned = placement.frame(for: frame, actualSize: placed.size, origin: origin, progress: 1)
                        if placed.origin != aligned.origin {
                            guard element.writeAnimationPosition(aligned.origin) == .success else {
                                finalResizeAccepted = false
                                return
                            }
                            placed = element.frame
                            confirmed = readServer(element)
                        }
                    }
                    handoff.observe(ax: placed, server: confirmed, at: animationClock())
                    if WindowAnimationGeometry.near(placed, frame, tolerance: 0.001),
                       confirmed.map({ WindowAnimationGeometry.near($0, frame, tolerance: 0.001) }) == true {
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
                let now = self.clock()
                self.pendingSettlement = PendingSettlement(destination: requested, origin: origin,
                    placement: placement, stability: WindowAnimationSettlement(startedAt: now,
                        verifiedFrame: verifiedFinalFrame,
                        alignmentTolerance: profile == .layoutHelper || resizePause.motion != nil || element.animationObservedFrame != nil ? 0.001 : 1,
                        handoff: handoff.evidence(for: requested, at: now),
                        probeConstrainedPosition: resizePause.motion != nil || element.animationObservedFrame != nil,
                        initialSizeRetry: element.animationEdgeProbeSent),
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

    private func observeResizePause(_ pause: inout WindowAnimationResizePause, window: AccessibilityElement,
                                    requested: CGSize, achieved: CGRect, previous: CGRect, previousTime: TimeInterval,
                                    destination: CGRect, placement: WindowAnimationPlacement, origin: CGRect,
                                    at now: TimeInterval, endingAt: TimeInterval) {
        guard window.animationObservedFrame == nil, !window.animationSizeDeferred else { return }
        guard achieved.width > requested.width + 1 || achieved.height > requested.height + 1 else {
            pause = WindowAnimationResizePause()
            return
        }
        if let motion = pause.motion,
           motion.width.map({ abs(achieved.width - $0) <= 1 && requested.width < $0 - 1 }) ?? true,
           motion.height.map({ abs(achieved.height - $0) <= 1 && requested.height < $0 - 1 }) ?? true {
            // The size read already confirms held axes. Do not add another
            // AX/WindowServer round trip while the other axis keeps resizing.
            let widthStillFree = motion.width == nil && achieved.width > requested.width + 1
            let heightStillFree = motion.height == nil && achieved.height > requested.height + 1
            if !widthStillFree && !heightStillFree { return }
        }
        let elapsed = max(1.0 / 120, now - previousTime)
        let velocity = CGPoint(x: (achieved.minX - previous.minX) / elapsed,
                               y: (achieved.minY - previous.minY) / elapsed)
        let actual = window.frame
        guard !window.animationYieldRequested else { return }
        let server = serverFrame(window)
        pause.observe(requested: requested, actual: actual, server: server,
            destination: destination, placement: placement, origin: origin, velocity: velocity,
            at: clock(), endingAt: endingAt)
        if let motion = pause.motion {
            WindowAnimationDiagnostics.event("direct-resize-pause", fields: ["windowID": window.windowId ?? 0,
                "actual": actual.dictionaryRepresentation, "target": destination.dictionaryRepresentation,
                "positionTarget": motion.destination.dictionaryRepresentation])
        }
    }

    private func writePausedPosition(_ window: AccessibilityElement, frame: CGRect, previous: CGRect,
                                     exact: Bool = false) -> CGRect? {
        var frame = frame
        if !exact { frame.origin = CGPoint(x: frame.minX.rounded(), y: frame.minY.rounded()) }
        guard frame.origin != previous.origin else { return frame }
        let startedAt = WindowAnimationDiagnostics.enabled ? clock() : nil
        let result = window.writeAnimationPosition(frame.origin)
        if let startedAt {
            WindowAnimationDiagnostics.event("direct-position-write", fields: ["windowID": window.windowId ?? 0,
                "milliseconds": (clock() - startedAt) * 1000, "result": result.rawValue,
                "requested": frame.dictionaryRepresentation])
        }
        return result == .success ? frame : nil
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

    deinit { if automaticallyAdvances { LayoutHelperCaptureGate.shared.end(capturePauseID) } }

    private func stopDriving() {
        guard automaticallyAdvances else { return }
        LayoutHelperCaptureGate.shared.end(capturePauseID)
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
        LayoutHelperCaptureGate.shared.begin(capturePauseID)
        let destination = helperDestination ?? pendingRelease?.destination ?? pendingSettlement?.destination ?? keyboardSession?.motion.destination ?? animation?.destination
        let screen = NSScreen.screens.max { first, second in
            func area(_ screen: NSScreen) -> CGFloat {
                guard let destination else { return 0 }
                let intersection = screen.frame.screenFlipped.intersection(destination)
                return intersection.isNull ? 0 : intersection.width * intersection.height
            }
            return area(first) < area(second)
        }
        var frameRate = 60
        if let screen, screen.maximumFramesPerSecond > 0 {
            frameRate = min(120, screen.maximumFramesPerSecond)
        }
        drivingInterval = 1.0 / Double(frameRate)
        if let screen {
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

final class WindowAnimationRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var changed = false
    private var resized = false
    func geometryChanged(resized: Bool = false) { lock.lock(); changed = true; self.resized = self.resized || resized; lock.unlock() }
    func consumeGeometryChange() -> Bool { lock.lock(); defer { lock.unlock() }; let result = changed; changed = false; return result }
    func consumeResizeChange() -> Bool { lock.lock(); defer { lock.unlock() }; let result = resized; resized = false; return result }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCurrent: Bool { lock.lock(); defer { lock.unlock() }; return !cancelled }
}

struct WindowAnimationPacing {
    let maximumRate: Int
    private(set) var rate: Int
    private var slow = 0
    private var fast = 0
    private var costs: [TimeInterval] = []
    init(maximumRate: Int, initialRate: Int? = nil) {
        self.maximumRate = max(1, min(120, maximumRate > 0 ? maximumRate : 60))
        let preferred = min(self.maximumRate, initialRate ?? self.maximumRate)
        rate = preferred >= 120 ? 120 : (preferred >= 60 ? 60 : min(30, self.maximumRate))
    }
    var interval: TimeInterval { 1 / Double(rate) }
    mutating func observe(cost: TimeInterval) {
        costs.append(cost)
        if costs.count > 8 { costs.removeFirst() }
        let tail = costs.sorted()[max(0, Int(Double(costs.count - 1) * 0.9))]
        if cost > interval {
            slow += 1; fast = 0
            if slow >= 3, rate > 30 { rate = rate > 60 ? 60 : 30; slow = 0; costs.removeAll() }
        } else {
            slow = 0
            let next = rate == 30 ? 60 : 120
            if next <= maximumRate, tail < 0.65 / Double(next) { fast += 1 } else { fast = 0 }
            if fast >= 12 { rate = next; fast = 0; costs.removeAll() }
        }
    }
}

/// Owns AX handles independently of main-thread caches. Cancellation is checked
/// between properties, without holding a lock across an unresponsive AX call.
private final class WindowAnimationElement: AccessibilityElement {
    let process: pid_t
    let launch: TimeInterval
    let bundle: String?
    let enhancedUI: EnhancedUI
    let assistiveTechnology: Bool
    var request: WindowAnimationRequest
    var hint: CGSize?
    var readCount = 0
    var writeCount = 0
    var resizeCost: TimeInterval = 0
    var resizeWork: TimeInterval = 0
    private func measured<T>(_ operation: String, _ body: () -> T) -> T {
        let start = ProcessInfo.processInfo.systemUptime
        let value = body()
        let cost = ProcessInfo.processInfo.systemUptime - start
        if operation == "size-write" || operation == "size-read" { resizeWork += cost }
        if animationIntermediateStep && cost > 0.02 {
            animationYieldRequested = true
        }
        if operation == "size-write" {
            resizeCost = resizeCost == 0 ? cost : resizeCost * 0.75 + cost * 0.25
            animationSizeInterval = resizeCost > 0.03 ? 1.0 / 20 : (resizeCost > 0.016 ? 1.0 / 30 : (resizeCost > 0.008 ? 1.0 / 60 : 0))
        }
        WindowAnimationDiagnostics.event("animation-operation", fields: ["windowID": windowId ?? 0,
            "operation": operation, "milliseconds": cost * 1000])
        return value
    }
    override func readAnimationGeometry() -> Bool {
        readCount += 1
        return measured("geometry-read") { super.readAnimationGeometry() }
    }

    init(_ element: AXUIElement, pid: pid_t, id: CGWindowID, launch: TimeInterval,
         bundle: String?, enhancedUI: EnhancedUI, assistiveTechnology: Bool, request: WindowAnimationRequest) {
        process = pid; self.launch = launch; self.bundle = bundle; self.enhancedUI = enhancedUI
        self.assistiveTechnology = assistiveTechnology; self.request = request
        super.init(element, messagingTimeout: 0.05, windowID: id)
    }
    override var bundleIdentifier: String? { bundle }
    override var pid: pid_t? { process }
    override var frame: CGRect {
        return measured("frame-read") { super.frame }
    }
    override var size: CGSize? {
        get {
            if let size = animationReads?.size { return size }
            readCount += 1
            return measured("size-read") { super.size }
        }
        set { if let newValue { _ = writeAnimationSize(newValue) } }
    }
    private var mayWrite: Bool {
        request.isCurrent && WindowProcessIdentity.launchTime(for: process) == launch
    }
    override func writeAnimationPosition(_ position: CGPoint) -> AXError {
        guard mayWrite else { return .cannotComplete }
        writeCount += 1
        return measured("position-write") { super.writeAnimationPosition(position) }
    }
    override func writeAnimationSize(_ size: CGSize) -> AXError {
        guard mayWrite else { return .cannotComplete }
        writeCount += 1
        return measured("size-write") { super.writeAnimationSize(size) }
    }
    override func beginAnimatedAdjustment() -> () -> Void {
        let application = AccessibilityElement(AXUIElementCreateApplication(process), application: true,
                                                messagingTimeout: 0.05)
        return measured("enhanced-ui-begin") {
            enhancedUI.beginWindowAdjustment(bundleIdentifier: bundle,
                builtInAssistiveTechnologyEnabled: assistiveTechnology,
                readEnhancedUI: { application.enhancedUserInterface },
                writeEnhancedUI: { application.enhancedUserInterface = $0 })
        }
    }
    override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
        if adjustSizeFirst, writeAnimationSize(frame.size) != .success { return }
        if adjustPosition, writeAnimationPosition(frame.origin) != .success { return }
        _ = writeAnimationSize(frame.size)
    }
}

/// Main-thread lifecycle and display callbacks; only the serial worker touches
/// the direct animator. Busy workers sample the newest time, never queued frames.
final class WindowAnimationExecutor {
    private struct Active {
        let element: AccessibilityElement
        let destination: CGRect
        let request: WindowAnimationRequest
        let offset: () -> CGPoint
        let pid: pid_t
    }
    private let queue = DispatchQueue(label: "Rectangle.WindowAnimation", qos: .userInteractive)
    private let captureID = UUID()
    private var active: Active?
    private var retiring: [(AccessibilityElement, CGRect, WindowAnimationRequest)] = []
    private var displayCleanup: (() -> Void)?
    private var generation: UInt64 = 0
    private var externalWork = 0
    private var tickPending = false
    private var nextTick: TimeInterval = 0
    private var pacing = WindowAnimationPacing(maximumRate: 60)
    private var mouseMonitor: Any?
    private var observation: WindowAnimationObservation?
    private var responses = WindowAnimationResponseHistory()
    private var preparing: (WindowAnimationResponseKey, TimeInterval)?

    // Accessed exclusively by queue.
    private var prepared: (WindowAnimationResponseKey, AXUIElement, TimeInterval)?
    private var workerTime: TimeInterval = 0
    private var workerWindow: WindowAnimationElement?
    private var workerScreens: [CGRect] = []
    private var workerNativeResize = false
    private var workerOffset = CGPoint.zero
    private lazy var core = DirectWindowAnimator(enabled: { true }, clock: { [weak self] in self?.workerTime ?? ProcessInfo.processInfo.systemUptime }, automaticallyAdvances: false, smoothResize: true,
        environmentIsSafe: { !WindowAnimationInterruptionPolicy.missionControlActive },
        crossesDisplays: { [weak self] a, b in
            let screens = self?.workerScreens ?? []
            return WindowDisplayTransition.display(containing: a, displays: screens)
                != WindowDisplayTransition.display(containing: b, displays: screens)
        }, minimumHint: { ($0 as? WindowAnimationElement)?.hint },
        isNativeResizeApp: { [weak self] _ in self?.workerNativeResize == true })

    func prepare(_ element: AccessibilityElement) {
        guard active == nil, externalWork == 0, WindowAnimator.enabled,
              let pid = element.pid, let id = element.windowId,
              let launch = WindowProcessIdentity.launchTime(for: pid) else { return }
        let key = WindowAnimationResponseKey(pid: pid, window: id, launch: launch)
        let now = ProcessInfo.processInfo.systemUptime
        if let preparing, now - preparing.1 < 1 { return }
        preparing = (key, now)
        queue.async { [self] in
            let reader = AccessibilityReadBatch(budget: 0.04)
            let windows = reader.value(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let raw = windows.first(where: { reader.windowID($0) == id }), reader.available {
                prepared = (key, raw, ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func destination(for element: AccessibilityElement) -> CGRect? {
        if let active, active.element == element { return active.destination }
        return retiring.last(where: { $0.0 == element })?.1
    }
    func afterPendingWrites(_ body: @escaping () -> Void) {
        if active == nil && retiring.isEmpty && !tickPending && externalWork == 0 { body(); return }
        let expected = generation
        queue.async { [self] in
            DispatchQueue.main.async { [self] in
                guard generation == expected else { return }
                body()
            }
        }
    }
    func performPlacementWork(_ body: @escaping () -> Void) {
        externalWork += 1
        queue.async { [self] in
            body()
            DispatchQueue.main.async { [self] in externalWork -= 1 }
        }
    }
    func cancel(for element: AccessibilityElement) {
        guard active?.element == element else { return }
        cancel()
    }
    func cancel() {
        generation &+= 1
        guard let previous = active else { return }
        previous.request.cancel()
        retiring.append((previous.element, previous.destination, previous.request))
        active = nil
        stopDisplay()
        let drained = retiring.map { $0.2 }
        queue.async { [self] in
            core.cancel(); workerWindow = nil
            DispatchQueue.main.async { [self] in retiring.removeAll { entry in drained.contains { $0 === entry.2 } } }
        }
    }
    func cancelIfTargetDiffers(from pid: pid_t?) {
        if let pid, let active, active.pid != pid { cancel() }
    }
    func finish() {
        guard let current = active else { return }
        stopDisplay()
        queue.async { [self] in
            guard current.request.isCurrent else { return }
            core.finish()
            DispatchQueue.main.async { [self] in clear(current.request) }
        }
    }
    func mouseDown() { cancel() }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval, resizeOnly: Bool, releasedSnap: Bool,
                 placement: WindowAnimationPlacement?, profile: WindowAnimationProfile,
                 offset: @escaping () -> CGPoint, curve: @escaping (Double) -> CGFloat,
                 completion: @escaping (CGRect) -> Void) {
        guard WindowAnimator.enabled, let pid = element.pid, let id = element.windowId,
              let launch = WindowProcessIdentity.launchTime(for: pid) else { completion(.null); return }
        generation &+= 1
        let sameWindow = active?.element == element
        if let previous = active {
            previous.request.cancel()
            retiring.append((previous.element, previous.destination, previous.request))
        }
        let drained = retiring.map { $0.2 }
        let request = WindowAnimationRequest()
        let key = WindowAnimationResponseKey(pid: pid, window: id, launch: launch)
        let response = responses.entry(for: key, at: ProcessInfo.processInfo.systemUptime)
        active = Active(element: element, destination: destination, request: request, offset: offset, pid: pid)
        let screens = NSScreen.screens.map { $0.frame.screenFlipped }
        let hint = element.rememberedMinimumSize
        let bundle = element.bundleIdentifier
        let native = bundle.map { Defaults.directAnimationNativeResizeApps.typedValue?.contains($0) == true } ?? false
        let enhanced = Defaults.enhancedUI.value
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        let initialOffset = offset()
        let preferredWindow = element.animationObservationElement
        startDisplay(destination: destination, initialPacing: response?.pacing)
        queue.async { [self] in
            guard request.isCurrent else { return }
            workerScreens = screens; workerNativeResize = native; workerOffset = initialOffset
            if !sameWindow || workerWindow?.windowId != id || workerWindow?.process != pid || workerWindow?.launch != launch {
                core.cancel(); workerWindow = nil
                var raw: AXUIElement?
                if let prepared, prepared.0 == key,
                   ProcessInfo.processInfo.systemUptime - prepared.2 < 2,
                   WindowProcessIdentity.launchTime(for: pid) == launch {
                    raw = prepared.1
                }
                self.prepared = nil
                if raw == nil {
                    raw = WindowAccessibilityLookup.resolve(pid: pid, id: id, launch: launch,
                        preferred: preferredWindow, isCurrent: { request.isCurrent })
                }
                if let raw {
                    workerWindow = WindowAnimationElement(raw, pid: pid, id: id, launch: launch,
                        bundle: bundle, enhancedUI: enhanced, assistiveTechnology: assistive, request: request)
                    workerWindow?.resizeCost = response?.resizeCost ?? 0
                }
            }
            guard request.isCurrent else { return }
            DispatchQueue.main.async { [self] in
                retiring.removeAll { entry in drained.contains { $0 === entry.2 } }
            }
            guard let window = workerWindow else {
                DispatchQueue.main.async { [self] in
                    guard active?.request === request else { return }
                    clear(request); completion(.null)
                }
                return
            }
            window.request = request; window.hint = hint
            let watch = WindowAnimationObservation(pid: pid, element: window.animationObservationElement, request: request)
            DispatchQueue.main.async { [self] in
                if active?.request === request { observation = watch }
            }
            workerTime = ProcessInfo.processInfo.systemUptime
            window.animationSizeInterval = window.resizeCost > 0.03 ? 1.0 / 20 : (window.resizeCost > 0.016 ? 1.0 / 30 : (window.resizeCost > 0.008 ? 1.0 / 60 : 0))
            core.animate(window, from: startingFrame, to: destination, duration: duration,
                resizeOnly: resizeOnly, releasedSnap: releasedSnap, placement: placement, profile: profile,
                offset: { [weak self] in self?.workerOffset ?? .zero }, curve: curve) { [weak self] frame in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.active?.request === request, request.isCurrent else { return }
                        self.clear(request); completion(frame)
                    }
                }
        }
    }
    private func clear(_ request: WindowAnimationRequest) {
        retiring.removeAll { $0.2 === request }
        guard active?.request === request else { return }
        active = nil; stopDisplay()
    }
    private func tick() {
        guard let current = active else { return }
        if !WindowAnimator.enabled { finish(); return }
        let now = ProcessInfo.processInfo.systemUptime
        guard !tickPending, now >= nextTick else { return }
        tickPending = true
        let offset = current.offset()
        let rate = pacing.rate
        queue.async { [self] in
            let start = ProcessInfo.processInfo.systemUptime
            if current.request.isCurrent {
                workerOffset = offset
                workerWindow?.animationYieldRequested = false
                workerWindow?.resizeWork = 0
                let reads = workerWindow?.readCount ?? 0, writes = workerWindow?.writeCount ?? 0
                if current.request.consumeGeometryChange() { workerWindow?.animationPolicy?.geometryChanged = true }
                if current.request.consumeResizeChange() {
                    workerWindow?.animationResizeNotified = true
                    WindowAnimationDiagnostics.event("animation-resize-notification", fields: ["windowID": workerWindow?.windowId ?? 0])
                }
                workerTime = start
                workerWindow?.animationVerificationTime = start
                core.advance(at: workerTime)
                WindowAnimationDiagnostics.event("animation-executor-tick", fields: [
                    "windowID": workerWindow?.windowId ?? 0, "rate": rate,
                    "queueMilliseconds": (start - now) * 1000,
                    "milliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000,
                    "reads": (workerWindow?.readCount ?? 0) - reads,
                    "writes": (workerWindow?.writeCount ?? 0) - writes])
            }
            let end = ProcessInfo.processInfo.systemUptime
            let finished = workerWindow.map { core.destination(for: $0) == nil } ?? true
            let sizeCost = workerWindow?.resizeCost ?? 0
            let movementCost = max(0, end - start - (workerWindow?.resizeWork ?? 0))
            let key = workerWindow.map { WindowAnimationResponseKey(pid: $0.process, window: $0.windowId ?? 0, launch: $0.launch) }
            DispatchQueue.main.async { [self] in
                tickPending = false
                guard active?.request === current.request else { return }
                pacing.observe(cost: movementCost); nextTick = start + pacing.interval * 0.9
                if let key { responses.record(key, pacing: pacing, resizeCost: sizeCost, at: end) }
                if finished { clear(current.request) }
            }
        }
    }
    private func stopDisplay() {
        observation = nil
        displayCleanup?(); displayCleanup = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }; mouseMonitor = nil
        LayoutHelperCaptureGate.shared.end(captureID)
    }
    private func startDisplay(destination: CGRect, initialPacing: WindowAnimationPacing?) {
        stopDisplay(); LayoutHelperCaptureGate.shared.begin(captureID)
        nextTick = 0
        let screen = NSScreen.screens.max {
            let a = $0.frame.screenFlipped.intersection(destination), b = $1.frame.screenFlipped.intersection(destination)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        let maximumRate = screen?.maximumFramesPerSecond ?? 60
        if let initialPacing, initialPacing.maximumRate == maximumRate { pacing = initialPacing }
        else { pacing = WindowAnimationPacing(maximumRate: maximumRate, initialRate: initialPacing?.rate) }
        if let screen {
            let target = WindowAnimationDisplayLinkTarget { [weak self] in self?.tick() }
            let link = screen.displayLink(target: target, selector: #selector(WindowAnimationDisplayLinkTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(pacing.maximumRate),
                maximum: Float(pacing.maximumRate), preferred: Float(pacing.maximumRate))
            link.add(to: .main, forMode: .common)
            displayCleanup = { link.invalidate(); _ = target }
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common); displayCleanup = { timer.invalidate() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.cancel() }
    }
}


/// Notifications only schedule readback; they do not prove a frame was displayed.
private final class WindowAnimationObservation {
    private var observer: AXObserver?
    private let request: WindowAnimationRequest
    init(pid: pid_t, element: AXUIElement, request: WindowAnimationRequest) {
        self.request = request
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else { return }
            Unmanaged<WindowAnimationRequest>.fromOpaque(context).takeUnretainedValue()
                .geometryChanged(resized: notification as String == kAXResizedNotification)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let context = Unmanaged.passUnretained(request).toOpaque()
        for notification in [kAXMovedNotification, kAXResizedNotification] {
            _ = AXObserverAddNotification(observer, element, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}
