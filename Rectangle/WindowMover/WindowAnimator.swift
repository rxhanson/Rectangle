/// WindowAnimator.swift

import Cocoa

struct WindowAnimationPlacement: Equatable {
    let screenFrame: CGRect
    let sharedEdges: Edge?
    let constrainToScreen: Bool
    let gap: CGFloat

    func positionBeforeGrowing(from previous: CGRect, to requested: CGRect) -> CGPoint? {
        guard constrainToScreen else { return nil }
        var position = previous.origin
        // Make room on an expanding axis before asking AX to resize. Otherwise
        // macOS can clip the new size at the old origin even though the next
        // animation frame fits, producing a stop/start edge during the resize.
        if requested.width > previous.width + 1,
           previous.minX + requested.width > screenFrame.maxX + 1,
           requested.minX < previous.minX {
            position.x = requested.minX
        }
        if requested.height > previous.height + 1,
           previous.minY + requested.height > screenFrame.maxY + 1,
           requested.minY < previous.minY {
            position.y = requested.minY
        }
        return position == previous.origin ? nil : position
    }

    func frame(for requested: CGRect, actualSize: CGSize, origin: CGRect, progress: CGFloat) -> CGRect {
        var frame = CGRect(origin: requested.origin, size: actualSize)
        if let sharedEdges {
            frame = ClampedWindowAligner.aligned(window: frame, inZone: requested, sharedEdges: sharedEdges)
        }
        guard constrainToScreen else { return frame }

        // Bring an initially out-of-bounds window back gradually instead of clipping its first frame.
        let initialBounds = screenFrame.union(origin)
        let progress = min(1, max(0, progress))
        let bounds = CGRect(x: initialBounds.minX + (screenFrame.minX - initialBounds.minX) * progress,
                            y: initialBounds.minY + (screenFrame.minY - initialBounds.minY) * progress,
                            width: initialBounds.width + (screenFrame.width - initialBounds.width) * progress,
                            height: initialBounds.height + (screenFrame.height - initialBounds.height) * progress)
        return WindowFrameBounds.constrained(frame, to: bounds, gap: gap)
    }

    /// A transient resize response must not send an intermediate position past
    /// its requested trajectory and then back when the size catches up.
    func intermediateFrame(_ resolved: CGRect, requested: CGRect, previous: CGRect, maximumCorrection: CGFloat = 0) -> CGRect {
        var result = resolved
        result.origin.x = min(max(resolved.minX, min(previous.minX, requested.minX)),
                              max(previous.minX, requested.minX))
        result.origin.y = min(max(resolved.minY, min(previous.minY, requested.minY)),
                              max(previous.minY, requested.minY))
        // Consume constraint changes gradually, including necessary movement
        // against the nominal trajectory near a screen edge.
        let limit = max(0, maximumCorrection)
        result.origin.x += min(limit, max(-limit, resolved.minX - result.minX))
        result.origin.y += min(limit, max(-limit, resolved.minY - result.minY))
        return result
    }
}

/// Geometry evidence is scoped to one animation. Oversized shrink responses
/// remain eligible for retry rather than becoming inferred minimum sizes.
struct WindowAnimationSizeFeedback {
    private struct Observation {
        let requested: CGSize
        let actual: CGSize
        let time: TimeInterval
    }
    private var observations: [Observation] = []
    private(set) var fixedWidth: CGFloat?
    private(set) var fixedHeight: CGFloat?
    private(set) var aspectRatio: CGFloat?

    mutating func observe(requested: CGSize, actual: CGRect, server: CGRect?, at time: TimeInterval) {
        guard let server, WindowAnimationGeometry.valid(actual),
              WindowAnimationGeometry.near(actual, server, tolerance: 1),
              actual.width <= requested.width + 1, actual.height <= requested.height + 1 else {
            reset()
            return
        }
        guard abs(actual.width - requested.width) > 1 || abs(actual.height - requested.height) > 1 else {
            reset()
            return
        }
        if let last = observations.last,
           abs(last.requested.width - requested.width) <= 1,
           abs(last.requested.height - requested.height) <= 1 { return }
        observations.append(Observation(requested: requested, actual: actual.size, time: time))
        if observations.count > 6 { observations.removeFirst() }
        guard observations.count >= 3, let first = observations.first,
              time - first.time >= 1.0 / 30 else { return }
        fixedWidth = abs(first.requested.width - requested.width) > 2
            && observations.allSatisfy { abs($0.actual.width - actual.width) <= 1 } ? actual.width : nil
        fixedHeight = abs(first.requested.height - requested.height) > 2
            && observations.allSatisfy { abs($0.actual.height - actual.height) <= 1 } ? actual.height : nil
        let ratio = actual.width / actual.height
        aspectRatio = fixedWidth == nil && fixedHeight == nil
            && abs(first.actual.width - actual.width) > 2 && abs(first.actual.height - actual.height) > 2
            && observations.allSatisfy { abs($0.actual.width / $0.actual.height - ratio) <= ratio * 0.005 }
            ? ratio : nil
    }

    func size(for requested: CGSize) -> CGSize {
        var result = CGSize(width: fixedWidth ?? requested.width, height: fixedHeight ?? requested.height)
        if let ratio = aspectRatio {
            result.width = min(result.width, result.height * ratio)
            result.height = result.width / ratio
        }
        return result
    }

    private mutating func reset() {
        observations.removeAll(keepingCapacity: true)
        fixedWidth = nil
        fixedHeight = nil
        aspectRatio = nil
    }
}

/// Suppresses repeated shrinking only for the current motion. Final placement
/// still retries the requested size; this state never becomes a learned limit.
struct WindowAnimationResizePause {
    private struct AxisObservation {
        var actual: CGFloat
        var firstRequest: CGFloat
        var lastRequest: CGFloat
        var startedAt: TimeInterval
        var count: Int
    }

    struct Motion {
        let destination: CGRect
        let startedAt: TimeInterval
        let width: CGFloat?
        let height: CGFloat?
        let x: WindowKeyboardMotion.Axis
        let y: WindowKeyboardMotion.Axis

        func sample(requested: CGRect, at time: TimeInterval) -> (frame: CGRect, velocity: [CGFloat?]) {
            let x = x.sample(at: max(0, time - startedAt))
            let y = y.sample(at: max(0, time - startedAt))
            return (CGRect(x: width == nil ? requested.minX : x.position.rounded(),
                           y: height == nil ? requested.minY : y.position.rounded(),
                           width: width ?? requested.width, height: height ?? requested.height),
                    [width == nil ? nil : x.velocity, height == nil ? nil : y.velocity,
                     width == nil ? nil : 0, height == nil ? nil : 0])
        }
    }

    private var width: AxisObservation?
    private var height: AxisObservation?
    private(set) var motion: Motion?

    mutating func observe(requested: CGSize, actual: CGRect, server: CGRect?, destination: CGRect,
                          placement: WindowAnimationPlacement, origin: CGRect, velocity: CGPoint,
                          at now: TimeInterval, endingAt: TimeInterval) {
        guard let server, WindowAnimationGeometry.valid(actual), WindowAnimationGeometry.valid(server) else {
            width = nil; height = nil; motion = nil
            return
        }
        let widthAgrees = abs(actual.width - server.width) <= 1
        let heightAgrees = abs(actual.height - server.height) <= 1
        let retainedWidth = motion?.width.flatMap {
            widthAgrees && abs(actual.width - $0) <= 1 && requested.width < $0 - 1 ? $0 : nil
        }
        let retainedHeight = motion?.height.flatMap {
            heightAgrees && abs(actual.height - $0) <= 1 && requested.height < $0 - 1 ? $0 : nil
        }
        if !widthAgrees { width = nil }
        if !heightAgrees { height = nil }
        let blockedWidth = widthAgrees
            && Self.observeAxis(&width, requested: requested.width, actual: actual.width, at: now)
        let blockedHeight = heightAgrees
            && Self.observeAxis(&height, requested: requested.height, actual: actual.height, at: now)
        let canStart = endingAt - now >= 0.04
        let heldWidth = retainedWidth ?? (canStart && blockedWidth ? actual.width : nil)
        let heldHeight = retainedHeight ?? (canStart && blockedHeight ? actual.height : nil)
        guard heldWidth != nil || heldHeight != nil else { motion = nil; return }
        guard motion == nil || heldWidth != motion?.width || heldHeight != motion?.height else { return }

        // Only the rejected axis pauses. The other dimension continues to
        // follow the original trajectory rather than growing at completion.
        let finalSize = CGSize(width: heldWidth ?? destination.width, height: heldHeight ?? destination.height)
        let aligned = placement.frame(for: destination, actualSize: finalSize, origin: origin, progress: 1)
        let remaining = max(1.0 / 120, endingAt - now)
        motion = Motion(destination: aligned, startedAt: now, width: heldWidth, height: heldHeight,
            x: WindowKeyboardMotion.Axis(origin: actual.minX, destination: aligned.minX,
                velocity: velocity.x, duration: remaining, maximumDrift: 0),
            y: WindowKeyboardMotion.Axis(origin: actual.minY, destination: aligned.minY,
                velocity: velocity.y, duration: remaining, maximumDrift: 0))
    }

    private static func observeAxis(_ observation: inout AxisObservation?, requested: CGFloat,
                                    actual: CGFloat, at now: TimeInterval) -> Bool {
        guard actual > requested + 1 else { observation = nil; return false }
        guard var previous = observation, now >= previous.startedAt,
              abs(previous.actual - actual) <= 1, requested <= previous.lastRequest + 1 else {
            observation = AxisObservation(actual: actual, firstRequest: requested,
                lastRequest: requested, startedAt: now, count: 1)
            return false
        }
        if requested < previous.lastRequest - 0.5 { previous.count += 1 }
        previous.lastRequest = requested
        observation = previous
        return previous.count >= 3 && previous.firstRequest - requested >= 2
            && now - previous.startedAt >= 1.0 / 30 - 0.000001
    }
}

/// Short-lived readback from the end of one animation. It is neither a size
/// limit nor a prediction of a later window response.
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
    private var handoff: WindowAnimationHandoff.Evidence?
    private(set) var reusedHandoff = false
    private let alignmentTolerance: CGFloat
    private let probeConstrainedPosition: Bool

    init(startedAt: TimeInterval, verifiedFrame: CGRect? = nil, alignmentTolerance: CGFloat = 1,
         handoff: WindowAnimationHandoff.Evidence? = nil, probeConstrainedPosition: Bool = false) {
        self.startedAt = startedAt
        verificationStartedAt = startedAt
        self.alignmentTolerance = alignmentTolerance
        self.probeConstrainedPosition = probeConstrainedPosition
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
                // A resize acknowledgment or external position change invalidates
                // the old trajectory. Recompute from corroborated actual geometry.
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
            return .align(next)
        }
        guard now - verificationStartedAt < 0.2 else { return .failed }
        guard let previous, WindowAnimationGeometry.near(previous, ax, tolerance: 1) else {
            self.previous = ax
            stableSince = now
            return .waiting
        }
        // Allow a short in-flight resize response to arrive before issuing
        // another size write or aligning to a temporarily stale width.
        let stabilityInterval: TimeInterval = sizeDiffers && sizeRetries == 0 ? 0.05 : 1.0 / 30
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
                    // Position-only motion can reach the clamped endpoint before
                    // verification. Retain a bounded inward probe so a temporary
                    // edge clamp is not accepted just because alignment is exact.
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
        if probeConstrainedPosition, sizeRetries > 0, sizeDiffers, distance <= 1.000001 {
            // The normal stable-read grace period has now elapsed. Restore a
            // one-point probe directly instead of scheduling another animation.
            resetObservation(at: now)
            return .align(aligned)
        }
        // Preserve the gentle constrained-size recovery. Only an ordinary
        // position residual with no size retries uses the shorter correction.
        let minimumDuration: TimeInterval = (sizeDiffers || sizeRetries > 0) && distance > 8 ? 0.18 : 1.0 / 30
        // If the inward probe released a temporary clamp, the new size can
        // expose an additional position residual. Ease that recovery rather
        // than jumping from the previously aligned constrained frame.
        let duration = probeConstrainedPosition && sizeRetries > 0 && !sizeDiffers
            ? min(0.85, max(minimumDuration, Double(distance) * 1.5 / 60))
            : min(0.3, max(minimumDuration, Double(distance) / 140))
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
            return .align(next)
        }
        return .waiting
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

/// Advances by elapsed time, skipping missed frames.
final class WindowFrameAnimation {
    let destination: CGRect
    private let origin: CGRect
    private let startTime: TimeInterval
    private let duration: TimeInterval
    private let offset: () -> CGPoint
    private let curve: (Double) -> CGFloat
    private let write: (CGRect, CGFloat) -> Bool
    private let finishedEarly: () -> Bool
    private let finalize: ((CGRect) -> Void)?
    private let cleanup: () -> Void
    private let completion: (CGRect) -> Void
    private let maximumFrameInterval: (() -> TimeInterval)?
    private let maximumDuration: TimeInterval?
    private var previousTime: TimeInterval
    private var elapsed: TimeInterval = 0
    private(set) var isFinished = false

    var remainingDuration: TimeInterval { max(0, duration - elapsed) }

    init(from: CGRect, to: CGRect, startTime: TimeInterval, duration: TimeInterval,
         offset: @escaping () -> CGPoint = { .zero },
         curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
         maximumFrameInterval: (() -> TimeInterval)? = nil,
         maximumDuration: TimeInterval? = nil,
         write: @escaping (CGRect, CGFloat) -> Bool,
         finishedEarly: @escaping () -> Bool = { false },
         finalize: ((CGRect) -> Void)? = nil,
         cleanup: @escaping () -> Void,
         completion: @escaping (CGRect) -> Void) {
        origin = from
        destination = to
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
        self.curve = curve
        self.maximumFrameInterval = maximumFrameInterval
        self.maximumDuration = maximumDuration
        previousTime = startTime
        self.write = write
        self.finishedEarly = finishedEarly
        self.finalize = finalize
        self.cleanup = cleanup
        self.completion = completion
    }

    func tick(at time: TimeInterval) {
        guard !isFinished else { return }
        if let maximumDuration, time - startTime >= maximumDuration {
            finish()
            return
        }
        if let maximumFrameInterval {
            // Slow Accessibility replies must not turn the next frame into a
            // catch-up jump when a caller opts into bounded playback steps.
            elapsed += min(max(0, time - previousTime), max(0, maximumFrameInterval()))
        } else {
            elapsed = max(0, time - startTime)
        }
        previousTime = max(previousTime, time)
        let progress = duration > 0 ? min(1, elapsed / duration) : 1
        if progress >= 1 {
            finish()
            return
        }
        let eased = curve(progress)
        let delta = offset()
        let frame = CGRect(x: origin.minX + (destination.minX - origin.minX) * eased + delta.x,
                           y: origin.minY + (destination.minY - origin.minY) * eased + delta.y,
                           width: origin.width + (destination.width - origin.width) * eased,
                           height: origin.height + (destination.height - origin.height) * eased)
        if !write(frame, eased) || finishedEarly() {
            // Let the normal mover settle the destination after a refused AX write.
            finish()
        }
    }

    func finish() {
        guard !isFinished else { return }
        let delta = offset()
        isFinished = true
        let finalFrame = destination.offsetBy(dx: delta.x, dy: delta.y)
        finalize?(finalFrame)
        cleanup()
        completion(finalFrame)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        cleanup()
    }
}

enum WindowAnimationInterruptionPolicy {
    static func isMissionControlElement(role: String?, identifier: String?) -> Bool {
        role == kAXGroupRole && identifier == "mc"
    }

    static var missionControlActive: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return false }
        // Mission Control does not necessarily activate Dock or change the current Space.
        // Its AX identifier is independent of the localized title. This is a best-effort
        // system marker; ordinary Dock groups and unavailable AX reads must not match.
        return children.contains { child in
            var role: CFTypeRef?
            var identifier: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard role as? String == kAXGroupRole else { return false }
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifier)
            return isMissionControlElement(role: role as? String, identifier: identifier as? String)
        }
    }

    static func shouldCancel(activatedPID: pid_t?, targetPID: pid_t) -> Bool {
        guard let activatedPID else { return false }
        return activatedPID != targetPID
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

enum WindowAnimationGeometry {
    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy { $0.isFinite } && frame.width > 0 && frame.height > 0
    }
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        valid(a) && valid(b) && abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance && abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
}

/// Opt-in local timing evidence. Normal app launches do no tracing or filesystem work.
/// Example Terminal command to launch Rectangle with this enabled:
/// open -a Rectangle --env RECTANGLE_ANIMATION_TRACE_PATH="/tmp/trace.json"
enum WindowAnimationDiagnostics {
    private static let path = ProcessInfo.processInfo.environment["RECTANGLE_ANIMATION_TRACE_PATH"]
    static var enabled: Bool { !(path ?? "").isEmpty }
    private static let queue = DispatchQueue(label: "Rectangle.WindowAnimation.diagnostics", qos: .utility)
    static func event(_ name: String, fields: [String: Any] = [:]) {
        guard let path, !path.isEmpty else { return }
        var record = fields
        record["event"] = name
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        record["timestamp"] = Date().timeIntervalSince1970
        record["pid"] = getpid()
        guard JSONSerialization.isValidJSONObject(record),
              var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async {
            let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                _ = Darwin.write(descriptor, base, buffer.count)
            }
        }
    }
}

/// Coordinates animation lifecycle and moves the actual application window.
final class WindowAnimator {
    static let shared = WindowAnimator()
    private let direct = DirectWindowAnimator()

    private init() {
        for name in [Notification.Name.windowAnimationPreferencesChanged, .configImported] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.finish()
            }
        }
        for name in [NSApplication.willTerminateNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.direct.cancel()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.direct.cancel()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.direct.cancelIfTargetDiffers(from: app?.processIdentifier)
        }
    }

    static var enabled: Bool {
        Defaults.experimentalWindowAnimations.enabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && !NSWorkspace.shared.isVoiceOverEnabled
            && !NSWorkspace.shared.isSwitchControlEnabled
    }

    func destination(for element: AccessibilityElement) -> CGRect? { direct.destination(for: element) }
    func logicalFrame(for element: AccessibilityElement) -> CGRect? { direct.destination(for: element) }
    func cancel(for element: AccessibilityElement) { direct.cancel(for: element) }
    func finish() { direct.finish() }
    func finishForNewDrag() {
        direct.mouseDown()
        finish()
    }

    func animate(_ element: AccessibilityElement, from startingFrame: CGRect? = nil, to destination: CGRect,
                 duration: TimeInterval = WindowAnimationCurve.duration,
                 resizeOnly: Bool = false, releasedSnap: Bool = false,
                 placement: WindowAnimationPlacement? = nil,
                 profile: WindowAnimationProfile = .standard,
                 offset: @escaping () -> CGPoint = { .zero },
                 curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
                 completion: @escaping (CGRect) -> Void) {
        direct.animate(element, from: startingFrame, to: destination, duration: duration,
                       resizeOnly: resizeOnly, releasedSnap: releasedSnap, placement: placement, profile: profile,
                       offset: offset, curve: curve, completion: completion)
    }

    static func crossesDisplays(from source: CGRect, to destination: CGRect) -> Bool {
        let frames = NSScreen.screens.map { $0.frame.screenFlipped }
        guard let a = WindowDisplayTransition.display(containing: source, displays: frames),
              let b = WindowDisplayTransition.display(containing: destination, displays: frames) else { return false }
        return a != b
    }
}
