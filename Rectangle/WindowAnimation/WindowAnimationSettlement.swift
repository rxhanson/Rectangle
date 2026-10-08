import Cocoa
import QuartzCore

/// Verifies size retries and animates any remaining position correction.
/// Observations belong to this placement only; they never become size hints.
struct WindowAnimationSettlement {
    enum Decision {
        case waiting, retrySize, retrySizeAt(CGPoint), align(CGRect), complete(CGRect), failed
    }

    private struct Alignment {
        let origin: CGRect
        let target: CGRect
        let duration: TimeInterval
        let velocity: CGPoint
        var elapsed: TimeInterval = 0
        var lastTick: TimeInterval
        var expected: CGRect
    }

    let startedAt: TimeInterval
    private var verificationStartedAt: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?
    private var sizeRetries = 0
    private var alignment: Alignment?
    private var completionCandidate: CGRect?
    private var lastAlignmentRequest: (frame: CGRect, observed: CGRect)?
    private var handoff: WindowAnimationHandoff.Evidence?
    private(set) var reusedHandoff = false
    private let alignmentTolerance: CGFloat
    private let probeConstrainedPosition: Bool

    init(startedAt: TimeInterval, verifiedFrame: CGRect? = nil, alignmentTolerance: CGFloat = 1,
         handoff: WindowAnimationHandoff.Evidence? = nil, probeConstrainedPosition: Bool = false,
         initialSizeRetry: Bool = false) {
        self.startedAt = startedAt
        verificationStartedAt = startedAt
        self.alignmentTolerance = alignmentTolerance
        self.probeConstrainedPosition = probeConstrainedPosition
        sizeRetries = initialSizeRetry ? 1 : 0
        completionCandidate = verifiedFrame
        self.handoff = handoff
        if let verifiedFrame {
            previous = verifiedFrame
            stableSince = startedAt
        }
    }

    mutating func observe(ax: CGRect, server: CGRect?, destination: CGRect,
                          placement: WindowAnimationPlacement, origin: CGRect,
                          at now: TimeInterval) -> Decision {
        // Two bounded resize retries, position motion and final verification
        // share one deadline. A missing acknowledgment also has its own limit.
        guard now - startedAt < 1.2 else { return .failed }
        guard let server, WindowAnimationGeometry.valid(ax), WindowAnimationGeometry.valid(server),
              WindowAnimationGeometry.near(ax, server, tolerance: 1) else {
            previous = nil
            stableSince = nil
            completionCandidate = nil
            handoff = nil
            alignment?.lastTick = now
            return now - verificationStartedAt < 0.2 ? .waiting : .failed
        }
        let sizeDiffers = abs(ax.width - destination.width) > 1 || abs(ax.height - destination.height) > 1
        if !sizeDiffers, WindowAnimationGeometry.near(ax, destination, tolerance: alignmentTolerance) {
            return .complete(ax)
        }
        if let request = lastAlignmentRequest, !sizeDiffers || sizeRetries >= 2 {
            let aligned = placement.frame(for: destination, actualSize: ax.size, origin: origin, progress: 1)
            // Some apps quantize fractional gap coordinates. Accept that result
            // only after an exact final position write leaves corroborated geometry unchanged.
            if WindowAnimationGeometry.near(ax, server, tolerance: 0.001),
               WindowAnimationGeometry.near(ax, request.observed, tolerance: 0.001),
               WindowAnimationGeometry.near(request.frame, aligned, tolerance: 0.001),
               Self.matchesPixelRoundedFrame(ax, target: aligned) {
                return .complete(ax)
            }
        }
        var continuingVelocity = CGPoint.zero
        var continuationElapsed: TimeInterval = 0
        if let evidence = handoff {
            handoff = nil
            let aligned = placement.frame(for: destination, actualSize: ax.size, origin: origin, progress: 1)
            let delta = CGPoint(x: aligned.minX - ax.minX, y: aligned.minY - ax.minY)
            let sameDirection = delta.x * evidence.velocity.x >= 0 && delta.y * evidence.velocity.y >= 0
            if evidence.destination == destination, now >= evidence.sampledAt,
               now - evidence.sampledAt <= 1.0 / 30,
               WindowAnimationGeometry.near(ax, evidence.frame, tolerance: 1),
               sameDirection {
                reusedHandoff = true
                previous = ax
                // Earlier intermediate sizes cannot prove that the final
                // resize has finished responding. Keep its full grace period.
                stableSince = sizeDiffers ? max(startedAt, evidence.stableSince) : evidence.stableSince
                if !sizeDiffers {
                    continuingVelocity = CGPoint(x: delta.x * evidence.velocity.x > 0 ? evidence.velocity.x : 0,
                                                 y: delta.y * evidence.velocity.y > 0 ? evidence.velocity.y : 0)
                    continuationElapsed = now - evidence.sampledAt
                }
            }
        }
        if let candidate = completionCandidate {
            completionCandidate = nil
            // Reuse the final readback only when a fresh AX/WindowServer pair
            // still confirms the requested size and aligned position.
            let aligned = placement.frame(for: destination, actualSize: ax.size, origin: origin, progress: 1)
            if !sizeDiffers, WindowAnimationGeometry.near(ax, candidate, tolerance: alignmentTolerance),
               WindowAnimationGeometry.near(ax, aligned, tolerance: alignmentTolerance) {
                return .complete(ax)
            }
        }
        if var motion = alignment {
            guard WindowAnimationGeometry.near(ax, motion.expected, tolerance: 1) else {
                // A resize or external move invalidates the trajectory. Recompute
                // from the geometry reported by both AX and WindowServer.
                alignment = nil
                resetObservation(at: now)
                return .waiting
            }
            motion.elapsed += min(1.0 / 30, max(0, now - motion.lastTick))
            motion.lastTick = now
            let t = min(1, motion.elapsed / motion.duration)
            let next = alignmentFrame(motion, at: motion.elapsed, size: ax.size)
            motion.expected = next
            alignment = t >= 1 ? nil : motion
            resetObservation(at: now)
            if t >= 1, !sizeDiffers { completionCandidate = next }
            return requestAlignment(next, observed: ax)
        }
        guard now - verificationStartedAt < 0.2 else { return .failed }
        if sizeDiffers, sizeRetries == 0, probeConstrainedPosition, placement.constrainToScreen,
           abs(ax.minX - destination.minX) <= 1, abs(ax.minY - destination.minY) <= 1 {
            let bounds = placement.screenFrame.insetBy(dx: placement.gap, dy: placement.gap)
            var position = ax.origin
            if ax.width > destination.width + 1, ax.maxX > bounds.maxX + 1 {
                position.x -= 1
            } else if ax.height > destination.height + 1, ax.maxY > bounds.maxY + 1 {
                position.y -= 1
            }
            if position != ax.origin {
                // Release an edge clamp at the requested origin before waiting
                // for a stable size. This probe does not establish a minimum.
                sizeRetries += 1
                resetObservation(at: now)
                return .retrySizeAt(position)
            }
        }
        if sizeDiffers {
            guard let previous, WindowAnimationGeometry.near(previous, ax, tolerance: 1) else {
                self.previous = ax
                stableSince = now
                return .waiting
            }
        } else if stableSince == nil {
            previous = ax
            stableSince = now
        }
        // Allow a short in-flight resize response to arrive before issuing
        // another size write or aligning to a temporarily stale width.
        let stabilityInterval: TimeInterval = sizeDiffers ? (sizeRetries == 0 ? 0.08 : 0.05) : 0
        guard let stableSince, now - stableSince + 0.000001 >= stabilityInterval else { return .waiting }
        var aligned = placement.frame(for: destination, actualSize: ax.size, origin: origin, progress: 1)
        if sizeDiffers, sizeRetries < 2 {
            if let position = placement.positionBeforeGrowing(from: aligned, to: destination) {
                aligned.origin = position
            }
            if sizeRetries == 0 {
                sizeRetries += 1
                resetObservation(at: now)
                // A small move may release a temporary edge clamp. Count it as
                // a size retry and leave final alignment to the motion phase.
                func step(_ current: CGFloat, toward target: CGFloat) -> CGFloat {
                    current + min(1, max(-1, target - current))
                }
                var position = CGPoint(x: step(ax.minX, toward: aligned.minX),
                                       y: step(ax.minY, toward: aligned.minY))
                if position == ax.origin, probeConstrainedPosition, placement.constrainToScreen {
                    // Correct alignment can hide a temporary screen-edge size limit.
                    // Try a small inward move before accepting the constrained size.
                    let bounds = placement.screenFrame.insetBy(dx: placement.gap, dy: placement.gap)
                    if ax.width > destination.width + 1, ax.width < bounds.width - 1 {
                        position.x += ax.maxX >= bounds.maxX - 1 ? -1 : 1
                    } else if ax.height > destination.height + 1, ax.height < bounds.height - 1 {
                        position.y += ax.maxY >= bounds.maxY - 1 ? -1 : 1
                    }
                }
                return position == ax.origin ? .retrySize : .retrySizeAt(position)
            }
            if WindowAnimationGeometry.near(ax, aligned, tolerance: alignmentTolerance) {
                sizeRetries += 1
                resetObservation(at: now)
                return .retrySize
            }
        } else if WindowAnimationGeometry.near(ax, aligned, tolerance: alignmentTolerance) {
            return .complete(ax)
        }
        let distance = max(abs(aligned.minX - ax.minX), abs(aligned.minY - ax.minY))
        if distance <= 1.000001, !sizeDiffers || (probeConstrainedPosition && sizeRetries > 0) {
            // A one-point remainder needs one exact write. Fractional steps
            // may round back to the same pixel and create an idle tail.
            resetObservation(at: now)
            if !sizeDiffers { completionCandidate = aligned }
            return requestAlignment(aligned, observed: ax)
        }
        // Preserve the gentle constrained-size recovery. Only an ordinary
        // position residual with no size retries uses the shorter correction.
        let minimumDuration: TimeInterval = sizeDiffers && distance > 8 ? 0.18 : 1.0 / 30
        // Releasing an edge constraint can require another position correction.
        // Animate that correction from the newly observed frame.
        let duration = sizeDiffers ? min(0.3, max(minimumDuration, Double(distance) / 140))
            : min(0.12, max(minimumDuration, Double(distance) / 700))
        alignment = Alignment(origin: ax, target: aligned,
            duration: duration,
            velocity: continuingVelocity, lastTick: now, expected: ax)
        resetObservation(at: now)
        if continuationElapsed > 0, var motion = alignment {
            motion.elapsed = min(1.0 / 30, continuationElapsed)
            let next = alignmentFrame(motion, at: motion.elapsed, size: ax.size)
            motion.expected = next
            alignment = motion.elapsed >= motion.duration ? nil : motion
            if alignment == nil { completionCandidate = next }
            return requestAlignment(next, observed: ax)
        }
        if !sizeDiffers, var motion = alignment {
            motion.elapsed = min(1.0 / 60, motion.duration)
            let next = alignmentFrame(motion, at: motion.elapsed, size: ax.size)
            motion.expected = next
            alignment = motion
            return requestAlignment(next, observed: ax)
        }
        return .waiting
    }

    private mutating func requestAlignment(_ frame: CGRect, observed: CGRect) -> Decision {
        lastAlignmentRequest = (frame, observed)
        return .align(frame)
    }

    private static func matchesPixelRoundedFrame(_ actual: CGRect, target: CGRect) -> Bool {
        let values = [actual.minX, actual.minY, actual.width, actual.height]
        let targets = [target.minX, target.minY, target.width, target.height]
        return [CGFloat(1), 0.5].contains { pixel in
            zip(values, targets).allSatisfy { value, target in
                abs(value - target) <= 0.001
                    || (abs(value - target) <= pixel / 2 + 0.001
                        && abs(value / pixel - (value / pixel).rounded()) <= 0.001)
            }
        }
    }

    private func alignmentFrame(_ motion: Alignment, at elapsed: TimeInterval, size: CGSize) -> CGRect {
        func position(_ origin: CGFloat, _ target: CGFloat, _ velocity: CGFloat) -> CGFloat {
            WindowKeyboardMotion.Axis(origin: origin, destination: target, velocity: velocity,
                duration: motion.duration, maximumDrift: 0).sample(at: elapsed).position
        }
        return CGRect(x: position(motion.origin.minX, motion.target.minX, motion.velocity.x),
                      y: position(motion.origin.minY, motion.target.minY, motion.velocity.y),
                      width: size.width, height: size.height)
    }

    private mutating func resetObservation(at now: TimeInterval) {
        previous = nil
        stableSince = nil
        verificationStartedAt = now
    }
}

struct WindowReleasedSnapStability {
    enum Decision { case waiting, ready, timedOut }
    let startedAt: TimeInterval
    private var previous: CGRect?
    private var stableSince: TimeInterval?

    init(startedAt: TimeInterval) { self.startedAt = startedAt }

    mutating func observe(ax: CGRect, server: CGRect?, at now: TimeInterval) -> Decision {
        if let server, WindowAnimationGeometry.valid(ax), WindowAnimationGeometry.valid(server),
           WindowAnimationGeometry.near(ax, server, tolerance: 1) {
            if let previous, WindowAnimationGeometry.near(previous, server, tolerance: 1) {
                if let stableSince, now - stableSince >= 1.0 / 30 { return .ready }
            } else { stableSince = now }
            previous = server
        } else {
            previous = nil
            stableSince = nil
        }
        return now - startedAt >= 0.15 ? .timedOut : .waiting
    }
}

/// Briefly reuses the previous animation's final geometry when retargeting.
/// This observation does not establish a window size limit.
struct WindowAnimationHandoff {
    struct Evidence {
        let destination: CGRect
        let frame: CGRect
        let sampledAt: TimeInterval
        let stableSince: TimeInterval
        let velocity: CGPoint
    }

    private var samples: [(frame: CGRect, time: TimeInterval, positionConfirmed: Bool)] = []
    private var lastAttempt: TimeInterval?
    private var attempts = 0

    mutating func shouldSample(at now: TimeInterval, endingAt end: TimeInterval) -> Bool {
        guard now >= end - 0.08, now < end, attempts < 3,
              lastAttempt.map({ now - $0 >= 1.0 / 30 - 0.000001 }) ?? true else { return false }
        attempts += 1
        lastAttempt = now
        return true
    }

    mutating func observe(ax: CGRect, server: CGRect?, at now: TimeInterval) {
        guard now.isFinite, let server, WindowAnimationGeometry.valid(ax),
              WindowAnimationGeometry.valid(server), abs(ax.width - server.width) <= 1,
              abs(ax.height - server.height) <= 1 else {
            samples.removeAll(keepingCapacity: true)
            return
        }
        if let first = samples.first, let last = samples.last,
           now <= last.time || now - last.time > 0.05
            || abs(ax.width - first.frame.width) > 1 || abs(ax.height - first.frame.height) > 1 {
            samples.removeAll(keepingCapacity: true)
        }
        // Size acknowledgments remain useful while position writes are still
        // in flight. Velocity requires corroborated positions throughout.
        samples.append((ax, now, WindowAnimationGeometry.near(ax, server, tolerance: 1)))
        if samples.count > 4 { samples.removeFirst() }
    }

    func evidence(for destination: CGRect, at now: TimeInterval) -> Evidence? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last,
              last.positionConfirmed,
              now >= last.time, now - last.time <= 1.0 / 30,
              last.time - first.time >= 1.0 / 30 else { return nil }
        func velocity(_ coordinate: (CGRect) -> CGFloat) -> CGFloat {
            guard samples.allSatisfy({ $0.positionConfirmed }) else { return 0 }
            let delta = coordinate(last.frame) - coordinate(first.frame)
            let pairs = Array(zip(samples, samples.dropFirst()))
            guard let lastMovement = pairs.last(where: { coordinate($0.0.frame) != coordinate($0.1.frame) }),
                  last.time - lastMovement.1.time <= 1.0 / 30 else { return 0 }
            guard pairs.allSatisfy({
                (coordinate($0.1.frame) - coordinate($0.0.frame)) * delta >= 0
            }) else { return 0 }
            return min(140, max(-140, delta / CGFloat(last.time - first.time)))
        }
        return Evidence(destination: destination, frame: last.frame, sampledAt: last.time,
            stableSince: first.time, velocity: CGPoint(x: velocity { $0.minX }, y: velocity { $0.minY }))
    }
}
