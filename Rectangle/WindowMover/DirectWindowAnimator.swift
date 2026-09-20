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
             duration: TimeInterval, startedAt: TimeInterval, cleanup: @escaping () -> Void,
             completion: @escaping (CGRect) -> Void) {
            self.destination = destination
            self.origin = origin
            self.placement = placement
            self.duration = duration
            var initialSize = destination.size
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
         frameInterval: TimeInterval = 1.0 / 60,
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
        self.drivingInterval = frameInterval
        self.environmentIsSafe = environmentIsSafe
        self.serverFrame = serverFrame
        self.crossesDisplays = crossesDisplays
        self.isNativeResizeApp = isNativeResizeApp
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
        defer { advancing = false }
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
            duration: duration, startedAt: clock(), cleanup: cleanup, completion: completion)
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
            maximumDuration: preparation.duration * 1.5, write: { frame, _ in
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
        // Read the preceding frame before issuing another write, so the two
        // window APIs have time to acknowledge the same geometry.
        let endingAt = session.motion.startedAt + WindowKeyboardMotion.duration
        if session.handoff.shouldSample(at: time, endingAt: endingAt) {
            session.handoff.observe(ax: window.frame, server: serverFrame(window), at: time)
        }
        if sampled != session.lastSampledFrame || session.previousFrame.size != sampled.size {
            var requested = sampled
            let predicted = session.sizeFeedback.size(for: sampled.size)
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
                ? max(1.0 / 60, self?.drivingInterval ?? 1.0 / 60) : .greatestFiniteMagnitude
        }
        animation = WindowFrameAnimation(from: origin, to: destination, startTime: startedAt, duration: duration,
                                         offset: offset, curve: curve, maximumFrameInterval: maximumFrameInterval,
                                         maximumDuration: profile == .layoutHelper ? duration * 3 : nil,
                                         write: { [weak self] frame, progress in
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
                if handoff.shouldSample(at: now, endingAt: endingAt) {
                    handoff.observe(ax: element.frame, server: readServer(element), at: now)
                }
                if sampledFrame != lastSampledFrame || previousFrame.size != sampledFrame.size {
                    var requested = sampledFrame
                    let predictedSize = sizeFeedback.size(for: sampledFrame.size)
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
        }, finishedEarly: { reachedDestination }, finalize: { [weak self] frame in
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
                        alignmentTolerance: profile == .layoutHelper || resizePause.motion != nil ? 0.001 : 1,
                        handoff: handoff.evidence(for: requested, at: now),
                        probeConstrainedPosition: resizePause.motion != nil),
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
