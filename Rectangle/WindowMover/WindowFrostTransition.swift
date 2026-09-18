/// WindowFrostTransition.swift

import Cocoa

/// Opt-in local timing evidence. Normal app launches do no tracing or filesystem work.
enum WindowFrostDiagnostics {
    private static let path = ProcessInfo.processInfo.environment["RECTANGLE_FROST_TRACE_PATH"]
    static var enabled: Bool { !(path ?? "").isEmpty }
    private static let queue = DispatchQueue(label: "Rectangle.WindowFrost.diagnostics", qos: .utility)
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

/// The transition owns a lease, never an Accessibility write on the app's main thread.
protocol WindowFrostRecovery: AnyObject {
    func perform(_ operation: WindowParkingOperation, timeout: TimeInterval,
                 completion: @escaping (Result<CGRect, Error>) -> Void)
    func recover(reason: String, completion: @escaping (Result<CGRect, Error>) -> Void)
    func finish(frame: CGRect, completion: @escaping (Result<Void, Error>) -> Void)
}

protocol WindowFrostRendering: AnyObject {
    var diagnosticID: String? { get }
    var currentFrame: CGRect { get }
    func show()
    func prepare(completion: @escaping (Bool) -> Void)
    func cover(frame: CGRect, completion: @escaping (Bool) -> Void)
    func animate(to frame: CGRect, duration: TimeInterval, curve: @escaping (Double) -> CGFloat,
                 offset: @escaping () -> CGPoint, completion: @escaping () -> Void)
    func retarget(to frame: CGRect, duration: TimeInterval, completion: @escaping () -> Void)
    func enableDisplayCommand()
    func update(frame: CGRect)
    func freeze()
    func follow(frame: CGRect)
    func configureFinalMaterial(resizingUnderCover: Bool)
    func release()
    func resumeAutomatic()
    func close()
    func dismiss()
}

extension WindowFrostRendering {
    func enableDisplayCommand() {}
    func retarget(to frame: CGRect, duration: TimeInterval, completion: @escaping () -> Void) {
        animate(to: frame, duration: duration, curve: WindowAnimationCurve.value, offset: { .zero }, completion: completion)
    }
    var diagnosticID: String? { nil }
    func configureFinalMaterial(resizingUnderCover: Bool) {}
    func release() {}
    func resumeAutomatic() {}
    func dismiss() { close() }
    func prepare(completion: @escaping (Bool) -> Void) { show(); completion(true) }
    func follow(frame: CGRect) { update(frame: frame) }
    func freeze() { update(frame: currentFrame) }
    func cover(frame: CGRect, completion: @escaping (Bool) -> Void) { update(frame: frame); completion(true) }
}

extension WindowFrostOverlay: WindowFrostRendering {}
extension WindowRecoverySession: WindowFrostRecovery {}

/// A small asynchronous state machine with injected transport/rendering for deterministic tests.
/// Motion and hidden sizing overlap after the first verified parking operation.
final class WindowFrostTransition {
    enum Outcome { case placed(CGRect), fallback, placeOrdinarily(CGRect), cancelled }
    enum Phase: Equatable { case ready, arming, parking, preparing, placing, revealing, finishing, recovering, draggingOrdinarily, complete }
    struct Dependencies {
        let acquire: (@escaping (Result<WindowFrostRecovery, Error>) -> Void) -> Void
        let plan: (CGRect, CGRect) -> [WindowParkingOperation]?
        let afterFrame: (@escaping () -> Void) -> Void
        let afterRelease: (@escaping () -> Void) -> Void
        var repark: ((CGRect, CGRect) -> WindowParkingPlan?)? = nil
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var after: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        var displays: () -> [WindowParkingDisplay] = { [] }
        var replanCoveredResize: ((CGRect, CGRect) -> WindowParkingPlan?)? = nil
        var moveOrdinarily: (CGRect) -> Void = { _ in }
    }

    var onDestinationCovered: ((CGRect) -> Void)?
    var onPreviewDragAvailability: ((Bool) -> Void)?

    let source: CGRect
    private(set) var destination: CGRect
    private(set) var phase: Phase = .ready {
        didSet {
            trace("phase", ["phase": String(describing: phase)])
            if phase != .preparing { onPreviewDragAvailability?(false) }
        }
    }
    private var initialDestination: CGRect
    private let overlay: WindowFrostRendering
    private let dependencies: Dependencies
    private var coveredResizePlanner: ((CGRect, CGRect) -> WindowParkingPlan?)?
    private var duration: TimeInterval
    private let curve: (Double) -> CGFloat
    private let completion: (Outcome) -> Void
    private var externallyOwnedDrag: Bool
    private var coveredSizing: Bool
    private let initialCursorOffset: CGPoint
    private var session: WindowFrostRecovery?
    private var acquireStarted = false
    private var operations: [WindowParkingOperation]
    private var parkedFrame: CGRect?
    private var operationIndex = 0
    private var epoch = 0
    private var motionArrived = false
    private var preparationFinished = false
    private var held: Bool
    private var pendingCoveredResize: CGRect?
    private var replannedOwnedResize = false
    private var finalTargetChanged = false
    private var recoveryOutcome: Outcome?
    private var immediateFinish = false
    private var didStartMotion = false
    private var motionGeneration = 0
    private var commandRetargeted = false
    private var lastCommandTime: TimeInterval = 0
    private var settlingGeneration = 0
    private var placementWriteStarted = false
    private var pendingPlacementTarget = false
    private(set) var previewPaused = false
    private let traceID = UUID().uuidString

    init(source: CGRect, destination: CGRect, operations: [WindowParkingOperation],
         overlay: WindowFrostRendering, dependencies: Dependencies,
         duration: TimeInterval = WindowAnimationCurve.duration,
         curve: @escaping (Double) -> CGFloat = WindowAnimationCurve.value,
         externallyOwnedDrag: Bool = false, initialCursorOffset: CGPoint = .zero,
         coveredSizing: Bool = false,
         completion: @escaping (Outcome) -> Void) {
        self.coveredSizing = coveredSizing
        self.source = source
        self.destination = destination
        initialDestination = destination
        self.operations = operations
        self.overlay = overlay
        self.dependencies = dependencies
        coveredResizePlanner = dependencies.replanCoveredResize
        self.duration = duration
        self.curve = curve
        self.externallyOwnedDrag = externallyOwnedDrag
        self.initialCursorOffset = initialCursorOffset
        held = externallyOwnedDrag
        self.completion = completion
    }

    var isRecovering: Bool { phase == .recovering }
    var isComplete: Bool { phase == .complete }
    var isFinishingPlacement: Bool { phase == .finishing }
    var ownsDrag: Bool { externallyOwnedDrag || previewPaused }

    /// Keep the current cover and lease. Outstanding AX writes must acknowledge
    /// before any additional sizing; their epoch is deliberately left intact.
    func canRetarget(to frame: CGRect) -> Bool {
        guard [.arming, .parking, .preparing, .placing, .revealing].contains(phase), !ownsDrag,
              !immediateFinish, recoveryOutcome == nil, Self.valid(frame) else { return false }
        if phase == .placing || phase == .revealing { return dependencies.repark != nil }
        if coveredSizing, let prepared = preparationFinished ? parkedFrame : operations.last?.frame {
            return WindowParkingPlan.coveredPlacementFrame(size: prepared.size, destination: frame,
                                                          displays: dependencies.displays()) != nil
        }
        return true
    }

    func retarget(to frame: CGRect, duration: TimeInterval, displayCommand: Bool = false,
                  replanCoveredResize: ((CGRect, CGRect) -> WindowParkingPlan?)? = nil) {
        guard canRetarget(to: frame) else { return }
        // A replacement must bring its own alignment policy. Without one, keep
        // the safe recovery route instead of reusing the previous command's.
        coveredResizePlanner = replanCoveredResize
        let interruptedPlacement = phase == .placing || phase == .revealing
        if displayCommand { overlay.enableDisplayCommand() }
        destination = frame; initialDestination = frame; self.duration = duration
        commandRetargeted = true; finalTargetChanged = false; motionArrived = false
        lastCommandTime = dependencies.now(); settlingGeneration += 1
        onPreviewDragAvailability?(false)
        overlay.configureFinalMaterial(resizingUnderCover: requiresCoveredResize)
        trace("command-retarget", ["destination": Self.values(frame)])
        if interruptedPlacement {
            pendingPlacementTarget = true
            if phase == .placing && !placementWriteStarted {
                // The real window is still parked. Supersede the cover ACK,
                // without releasing its lease or invalidating an AX write.
                epoch += 1; phase = .preparing; pendingPlacementTarget = false
                trace("placement-cover-retarget")
            } else { return } // Keep covering the in-flight write until verified.
        }
        if phase == .preparing {
            motionGeneration += 1
            let generation = motionGeneration
            overlay.retarget(to: frame, duration: duration) { [weak self] in
                guard let self, self.motionGeneration == generation, self.phase == .preparing else { return }
                self.trace("motion-arrived")
                self.motionArrived = true
                self.advanceToPlacementIfReady()
            }
            advanceToPlacementIfReady()
        }
    }

    /// Mouse-down holds the existing lease and cover while the renderer samples
    /// its presentation frame. Pending hidden writes keep their original epoch.
    func pauseForPreviewDrag() -> Bool {
        guard phase == .preparing, didStartMotion, !motionArrived,
              !externallyOwnedDrag, !previewPaused else { return false }
        previewPaused = true; held = true; motionGeneration += 1
        onPreviewDragAvailability?(false)
        trace("preview-drag-paused")
        return true
    }

    func resumeAfterPreviewClick() {
        guard previewPaused, phase == .preparing else { return }
        previewPaused = false; held = false; motionArrived = false
        overlay.resumeAutomatic()
        startMotion()
    }

    func adoptPreviewDrag(destination: CGRect, initialCursorOffset: CGPoint) -> Bool {
        guard previewPaused, phase == .preparing, Self.valid(destination) else { return false }
        previewPaused = false; externallyOwnedDrag = true; held = true
        self.destination = destination
        initialDestination = destination.offsetBy(dx: -initialCursorOffset.x, dy: -initialCursorOffset.y)
        duration = WindowAnimationCurve.unsnapDuration; motionArrived = false; finalTargetChanged = false
        trace("preview-drag-adopted", ["destination": Self.values(destination)])
        startMotion()
        return true
    }

    func start() {
        guard phase == .ready else { return }
        phase = .arming
        overlay.configureFinalMaterial(resizingUnderCover: requiresCoveredResize)
        overlay.prepare { [weak self] ready in
            guard let self, self.phase == .arming else { return }
            guard ready else { self.complete(self.recoveryOutcome ?? .fallback); return }
            if let outcome = self.recoveryOutcome { self.complete(outcome); return }
            self.acquireStarted = true
            self.acquireLease()
        }
    }

    private func acquireLease() {
        trace("source-shown", ["source": Self.values(source), "destination": Self.values(destination),
                               "ownedDrag": externallyOwnedDrag, "sizing": coveredSizing ? "covered" : "hidden"])
        dependencies.acquire { [weak self] result in
            guard let self, self.phase == .arming else { return }
            switch result {
            case .failure:
                self.trace("arm-failed")
                // Admission can time out with a live recovery child. Even without a returned
                // session object, its durable reservation must settle before a fallback writes.
                self.phase = .recovering
                self.trace("recovery-pending")
                self.overlay.close()
                self.dependencies.afterRelease { [weak self] in
                    guard let self else { return }
                    self.complete(self.recoveryOutcome ?? .fallback)
                }
            case .success(let session):
                self.trace("armed")
                self.session = session
                if let outcome = self.recoveryOutcome { self.recover(outcome: outcome, reason: "cancelled while arming") }
                else { self.phase = .parking; self.performNext() }
            }
        }
    }

    /// Interruptions invalidate all in-flight acknowledgements, but never release the lease early.
    func cancel() {
        if phase == .draggingOrdinarily { complete(.cancelled); return }
        if phase == .recovering { recoveryOutcome = .cancelled; return }
        recover(outcome: .cancelled, reason: "interrupted")
    }

    func finish() {
        guard phase != .complete, phase != .recovering else { return }
        held = false
        immediateFinish = true
        if phase == .draggingOrdinarily { complete(.placeOrdinarily(destination)); return }
        if let achieved = pendingCoveredResize {
            pendingCoveredResize = nil
            overlay.release()
            replanCoveredResize(from: achieved)
            return
        }
        if phase == .preparing {
            overlay.update(frame: destination)
            motionArrived = true
            advanceToPlacementIfReady()
        }
    }

    func updateDrag(destination: CGRect) {
        guard externallyOwnedDrag, held, acceptsDragAfterFailure,
              Self.valid(destination), destination.size == initialDestination.size else { return }
        self.destination = destination
        if phase == .draggingOrdinarily { dependencies.moveOrdinarily(destination); return }
        if phase == .preparing {
            overlay.follow(frame: destination)
        }
    }

    func endDrag(destination: CGRect) {
        let accepted = externallyOwnedDrag && held && Self.valid(destination) && acceptsDragAfterFailure
        trace("owned-drag-end", ["accepted": accepted, "phase": String(describing: phase),
                                 "destination": Self.values(destination), "held": held])
        guard accepted else { return }
        held = false
        finalTargetChanged = destination.size != initialDestination.size
        self.destination = destination
        // Pointer coordinates can be fractional, while Brave rounds AX window
        // positions to whole points. Settle the release once so the destination
        // cover, placement, growth and readback all use the same requested origin.
        // Keep sub-point tracking while held and strict verification for parking.
        self.destination.origin.x = destination.minX.rounded()
        self.destination.origin.y = destination.minY.rounded()
        if phase == .draggingOrdinarily { complete(.placeOrdinarily(self.destination)); return }
        // Recovery still owns the window. Preserve the exact release target,
        // including snap size, but perform no writes until its lease is gone.
        if phase == .recovering { return }
        // The release can choose a different snap size. Select its material
        // before starting the fade, even while the parking operation is pending.
        overlay.configureFinalMaterial(resizingUnderCover: requiresCoveredResize)
        overlay.release()
        if let achieved = pendingCoveredResize {
            pendingCoveredResize = nil
            replanCoveredResize(from: achieved)
            return
        }
        if finalTargetChanged {
            // The final snap is a new visual target. The hidden resize is replanned after the
            // current operation settles, under the same recovery lease.
            motionArrived = false
            overlay.freeze()
        }
        if phase == .preparing { advanceToPlacementIfReady() }
    }

    private var acceptsDragAfterFailure: Bool {
        if phase == .complete { return false }
        if case .cancelled? = recoveryOutcome { return false }
        return true
    }

    private var dragOffset: CGPoint {
        CGPoint(x: destination.minX - initialDestination.minX,
                y: destination.minY - initialDestination.minY)
    }

    private var requiresCoveredResize: Bool {
        guard coveredSizing,
              let prepared = preparationFinished ? parkedFrame : operations.last?.frame else { return false }
        let placed = CGRect(origin: destination.origin, size: prepared.size)
        return !Self.matches(placed, destination)
    }

    private func performNext() {
        guard phase == .parking || phase == .preparing, let session else { return }
        guard operationIndex < operations.count else {
            preparationFinished = true
            advanceToPlacementIfReady()
            return
        }
        let index = operationIndex
        let operation = operations[index]
        let expectedEpoch = epoch
        trace("operation-start", ["operation": operation.phase, "frame": Self.values(operation.frame)])
        // Some native moves first reach WindowServer near 500ms; allow the second
        // matching sample without turning an otherwise successful move into recovery.
        session.perform(operation, timeout: 1.0) { [weak self] result in
            guard let self, self.epoch == expectedEpoch,
                  self.phase == .parking || self.phase == .preparing else { return }
            switch result {
            case .failure:
                self.recover(outcome: .fallback, reason: "hidden adjustment failed")
            case .success(let frame):
                self.trace("operation-verified", ["operation": operation.phase, "frame": Self.values(frame)])
                if !Self.matches(frame, operation.frame), operation.attribute == .size,
                   !operation.corner, operation.phase == "shrink-under-source-cover",
                   WindowSourceCoverResize.accepts(actual: frame, requested: operation.frame, source: self.source) {
                    if self.externallyOwnedDrag && self.held && !self.didStartMotion {
                        // The retained source still covers the achieved frame.
                        // Wait for the release target before considering another
                        // display's parking corner; no native writes while held.
                        self.pendingCoveredResize = frame
                        self.trace("covered-resize-awaiting-release")
                        self.dependencies.after(0.15) { [weak self] in
                            guard let self, self.epoch == expectedEpoch, self.held,
                                  self.pendingCoveredResize != nil, self.phase == .parking else { return }
                            self.pendingCoveredResize = nil
                            // A sustained drag must regain ordinary following;
                            // never leave its preview stationary until mouse-up.
                            self.recover(outcome: .fallback, reason: "covered resize remained held after release grace period")
                        }
                    } else {
                        self.replanCoveredResize(from: frame)
                    }
                    return
                }
                guard Self.matchesHidden(frame, operation: operation) else {
                    self.recover(outcome: .fallback, reason: "hidden adjustment did not reach the requested frame")
                    return
                }
                self.parkedFrame = frame
                self.operationIndex += 1
                if self.phase == .parking && operation.corner {
                    self.phase = .preparing
                    self.startMotion()
                }
                self.performNext()
            }
        }
    }

    private func replanCoveredResize(from frame: CGRect) {
        guard !didStartMotion, !replannedOwnedResize,
              let plan = coveredResizePlanner?(frame, destination), !plan.operations.isEmpty else {
            recover(outcome: .fallback, reason: "covered resize has no safe route from its achieved size")
            return
        }
        replannedOwnedResize = externallyOwnedDrag
        trace("covered-resize-replanned", ["actual": Self.values(frame), "destination": Self.values(plan.destination)])
        destination = plan.destination
        initialDestination = plan.destination
        operations = plan.operations
        operationIndex = 0
        coveredSizing = plan.sizing == .covered
        overlay.configureFinalMaterial(resizingUnderCover: requiresCoveredResize)
        performNext()
    }

    private func startMotion() {
        if externallyOwnedDrag && !didStartMotion {
            // Keep the original real window completely covered until parking is verified.
            overlay.update(frame: source.offsetBy(dx: initialCursorOffset.x, dy: initialCursorOffset.y))
        }
        didStartMotion = true
        motionGeneration += 1
        let expectedMotion = motionGeneration
        onPreviewDragAvailability?(!externallyOwnedDrag && !commandRetargeted)
        trace("motion-start", ["duration": immediateFinish ? 0 : duration])
        let expectedEpoch = epoch
        let movingToFinalTarget = finalTargetChanged
        let target = movingToFinalTarget ? destination : initialDestination
        finalTargetChanged = false
        let curve = externallyOwnedDrag ? WindowAnimationCurve.unsnapValue : self.curve
        overlay.animate(to: target, duration: immediateFinish ? 0 : duration, curve: curve,
                        offset: { [weak self] in
            guard let self, self.externallyOwnedDrag, !movingToFinalTarget else { return .zero }
            return self.dragOffset
        }) { [weak self] in
            guard let self, self.epoch == expectedEpoch, self.motionGeneration == expectedMotion,
                  self.phase == .preparing else { return }
            self.trace("motion-arrived")
            self.onPreviewDragAvailability?(false)
            self.motionArrived = true
            self.advanceToPlacementIfReady()
        }
    }

    private func advanceToPlacementIfReady() {
        guard phase == .preparing, preparationFinished, !held, let parkedFrame else { return }
        if coveredSizing && WindowParkingPlan.coveredPlacementFrame(size: parkedFrame.size, destination: destination,
                                                                    displays: dependencies.displays()) == nil {
            // A newly chosen snap target can be smaller than the admitted intermediate.
            // Do not expose it outside that cover or resize it at an unsafe corner.
            recover(outcome: .placeOrdinarily(destination), reason: "final cover is smaller than the parked intermediate")
            return
        }
        if !coveredSizing && (abs(parkedFrame.width - destination.width) >= 0.75 || abs(parkedFrame.height - destination.height) >= 0.75) {
            guard let next = dependencies.plan(parkedFrame, destination), !next.isEmpty else {
                recover(outcome: externallyOwnedDrag ? .placeOrdinarily(destination) : .fallback,
                        reason: "final drag target cannot be prepared safely")
                return
            }
            operations = next
            operationIndex = 0
            preparationFinished = false
            if !commandRetargeted {
                epoch += 1
                motionArrived = false
            // An early release may already have animated toward the new target
            // while the old preparation finished. Replanning must not animate
            // back to the original restore size.
                finalTargetChanged = true
                startMotion()
            }
            performNext()
            return
        }
        if finalTargetChanged && !motionArrived {
            finalTargetChanged = false
            epoch += 1
            let expectedEpoch = epoch
            overlay.animate(to: destination, duration: immediateFinish ? 0 : duration,
                            curve: curve, offset: { .zero }) { [weak self] in
                guard let self, self.epoch == expectedEpoch, self.phase == .preparing else { return }
                self.motionArrived = true
                self.advanceToPlacementIfReady()
            }
            return
        }
        guard motionArrived else { return }
        if commandRetargeted, dependencies.repark != nil, !immediateFinish {
            let remaining = 0.18 - (dependencies.now() - lastCommandTime)
            if remaining > 0 {
                let generation = settlingGeneration
                dependencies.after(remaining) { [weak self] in
                    guard let self, self.settlingGeneration == generation else { return }
                    self.advanceToPlacementIfReady()
                }
                return
            }
        }
        if coveredSizing {
            placeCovered(intermediate: parkedFrame)
            return
        }
        placePrepared()
    }

    /// The real window already has its final size. Only its position changes
    /// after the renderer acknowledges the destination, including release rounding.
    private func placePrepared() {
        guard let session else { return }
        phase = .placing; placementWriteStarted = false
        let expectedEpoch = epoch, target = destination
        overlay.configureFinalMaterial(resizingUnderCover: false)
        overlay.cover(frame: target) { [weak self] ready in
            guard let self, self.epoch == expectedEpoch, self.phase == .placing else { return }
            guard ready else { self.recover(outcome: .fallback, reason: "destination cover was not ready"); return }
            self.trace("destination-covered", ["frame": Self.values(target)])
            self.onDestinationCovered?(target)
            self.trace("placement-start", ["frame": Self.values(target)])
            self.placementWriteStarted = true
            let placement = WindowParkingOperation(attribute: .position, frame: target, corner: false, phase: "place")
            session.perform(placement, timeout: 1.0) { [weak self] result in
                guard let self, self.epoch == expectedEpoch, self.phase == .placing else { return }
                guard case .success(let frame) = result, Self.matches(frame, target) else {
                    self.recover(outcome: .fallback, reason: "final placement failed or was clamped"); return
                }
                if self.resumePendingCommand(from: frame) { return }
                self.revealVerified(frame: frame, epoch: expectedEpoch)
            }
        }
    }

    /// A new target never changes the geometry protecting an in-flight write.
    /// Snapshot that write's target, then repark from its verified result if a
    /// newer command arrived. No recovery to the original source is necessary.
    private func placeCovered(intermediate: CGRect) {
        guard let session else { return }
        phase = .placing; placementWriteStarted = false
        let expectedEpoch = epoch, target = destination
        guard let compact = WindowParkingPlan.coveredPlacementFrame(size: intermediate.size, destination: target,
                                                                    displays: dependencies.displays()) else {
            recover(outcome: .fallback, reason: "no protected intermediate placement"); return
        }
        overlay.configureFinalMaterial(resizingUnderCover: !Self.matches(compact, target))
        overlay.cover(frame: target) { [weak self] ready in
            guard let self, self.epoch == expectedEpoch, self.phase == .placing else { return }
            guard ready else { self.recover(outcome: .fallback, reason: "destination cover was not ready"); return }
            self.trace("destination-covered", ["frame": Self.values(target)])
            self.onDestinationCovered?(target)
            self.trace("placement-start", ["frame": Self.values(compact)])
            self.placementWriteStarted = true
            let placement = WindowParkingOperation(attribute: .position, frame: compact, corner: false, phase: "place-under-destination-cover")
            session.perform(placement, timeout: 1.0) { [weak self] result in
                guard let self, self.epoch == expectedEpoch, self.phase == .placing else { return }
                guard case .success(let placed) = result, Self.matches(placed, compact) else {
                    self.recover(outcome: .fallback, reason: "covered placement failed"); return
                }
                self.trace("compact-placement-verified", ["frame": Self.values(placed)])
                if self.resumePendingCommand(from: placed) { return }
                if Self.matches(placed, target) { self.revealVerified(frame: placed, epoch: expectedEpoch); return }
                let resized = CGRect(origin: compact.origin, size: target.size)
                let expansion = WindowParkingOperation(attribute: .size, frame: resized, corner: false,
                                                       phase: "grow-under-destination-cover")
                self.trace("covered-growth-start", ["frame": Self.values(resized)])
                session.perform(expansion, timeout: 1.0) { [weak self] result in
                    guard let self, self.epoch == expectedEpoch, self.phase == .placing else { return }
                    guard case .success(let frame) = result, Self.matchesCoveredResult(frame, resized) else {
                        self.recover(outcome: .fallback, reason: "covered growth failed"); return
                    }
                    if self.resumePendingCommand(from: frame) { return }
                    if compact.origin == target.origin {
                        self.revealVerified(frame: frame, epoch: expectedEpoch)
                    } else {
                        // The intermediate was aligned to hide its excess offscreen.
                        // Keep the same acknowledged cover through final alignment.
                        let alignment = WindowParkingOperation(attribute: .position, frame: target, corner: false,
                                                               phase: "align-under-destination-cover")
                        session.perform(alignment, timeout: 1.0) { [weak self] result in
                            guard let self, self.epoch == expectedEpoch, self.phase == .placing else { return }
                            guard case .success(let aligned) = result, Self.matchesCoveredResult(aligned, target) else {
                                self.recover(outcome: .fallback, reason: "covered alignment failed"); return
                            }
                            if self.resumePendingCommand(from: aligned) { return }
                            self.revealVerified(frame: aligned, epoch: expectedEpoch)
                        }
                    }
                }
            }
        }
    }

    private func resumePendingCommand(from frame: CGRect) -> Bool {
        guard pendingPlacementTarget else { return false }
        pendingPlacementTarget = false
        if Self.matches(frame, destination) { return false }
        guard let plan = dependencies.repark?(frame, destination), !plan.operations.isEmpty else {
            recover(outcome: .placeOrdinarily(destination), reason: "latest command cannot repark safely")
            return true
        }
        trace("command-repark", ["from": Self.values(frame), "destination": Self.values(destination)])
        epoch += 1
        coveredSizing = plan.sizing == .covered
        operations = plan.operations.map { operation in
            var operation = operation
            if operation.corner && operation.phase == "initial-parking" {
                // This endpoint has passed AX/WindowServer verification and its
                // cover stays still until parking is acknowledged again.
                operation.departureCover = frame
            }
            return operation
        }
        operationIndex = 0; parkedFrame = nil
        preparationFinished = false; placementWriteStarted = false; motionArrived = false
        overlay.configureFinalMaterial(resizingUnderCover: requiresCoveredResize)
        phase = .parking
        performNext()
        return true
    }

    private func revealVerified(frame: CGRect, epoch expectedEpoch: Int) {
        guard let session else { return }
        trace("placement-verified", ["frame": Self.values(frame)])
        phase = .revealing
        dependencies.afterFrame { [weak self] in
            guard let self, self.epoch == expectedEpoch, self.phase == .revealing else { return }
            if self.resumePendingCommand(from: frame) { return }
            self.trace("reveal-ready")
            self.phase = .finishing
            session.finish(frame: frame) { [weak self] result in
                guard let self, self.epoch == expectedEpoch, self.phase == .finishing else { return }
                switch result {
                case .success: self.complete(.placed(frame))
                case .failure: self.recover(outcome: .fallback, reason: "recovery lease could not be disarmed")
                }
            }
        }
    }

    private func recover(outcome: Outcome, reason: String) {
        guard phase != .complete, phase != .recovering else { return }
        recoveryOutcome = outcome
        guard let session else {
            if phase == .ready || (phase == .arming && !acquireStarted) { complete(outcome) }
            return // An in-flight acquire must return its lease before recovery can start.
        }
        epoch += 1
        phase = .recovering
        trace("recovery-start", ["reason": reason])
        overlay.update(frame: overlay.currentFrame)
        session.recover(reason: reason) { [weak self] result in
            guard let self, self.phase == .recovering else { return }
            // Recovery transport calls back only after the reservation has been released.
            switch result {
            case .success: self.complete(self.recoveryOutcome ?? outcome)
            case .failure:
                // A hung target may keep its journal/lease pending. Remove the visual cover,
                // then wait for the helper to verify recovery before allowing another writer.
                self.trace("recovery-pending")
                self.overlay.close()
                self.dependencies.afterRelease { [weak self] in
                    guard let self else { return }
                    self.complete(self.recoveryOutcome ?? outcome)
                }
            }
        }
    }

    private func complete(_ outcome: Outcome) {
        guard phase != .complete else { return }
        var outcome = outcome
        if externallyOwnedDrag, case .fallback = outcome {
            // Every caller reaches completion only after any recovery lease
            // has been released. Keep the accepted pointer sequence alive;
            // failure of the visual route must not discard its final position.
            if held {
                phase = .draggingOrdinarily
                epoch += 1
                session = nil
                recoveryOutcome = nil
                overlay.close()
                trace("owned-drag-ordinary", ["destination": Self.values(destination)])
                dependencies.moveOrdinarily(destination)
                return
            }
            outcome = .placeOrdinarily(destination)
        }
        phase = .complete
        epoch += 1
        if case .placed = outcome { overlay.dismiss() } else { overlay.close() }
        trace("complete", ["outcome": String(describing: outcome)])
        session = nil
        completion(outcome)
    }

    private func trace(_ event: String, _ fields: [String: Any] = [:]) {
        var fields = fields
        fields["transition"] = traceID
        if let id = overlay.diagnosticID { fields["overlay"] = id }
        WindowFrostDiagnostics.event(event, fields: fields)
    }

    private static func values(_ frame: CGRect) -> [Double] {
        [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)]
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isEmpty && [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
    }

    private static func matchesHidden(_ actual: CGRect, operation: WindowParkingOperation) -> Bool {
        guard operation.corner else { return matches(actual, operation.frame) }
        let expected = operation.frame
        let upward = expected.minY - actual.minY
        // The helper has also checked the narrow-strip envelope against every display.
        // Use the same clamp bound as route planning and native readback.
        return valid(actual) && abs(actual.minX - expected.minX) <= 0.1
            && abs(actual.width - expected.width) <= 0.1 && abs(actual.height - expected.height) <= 0.1
            && upward >= 0 && upward <= WindowParkingPlan.maximumUpwardClamp
    }

    private static func matches(_ actual: CGRect, _ expected: CGRect) -> Bool {
        valid(actual) && abs(actual.minX - expected.minX) < 0.75 && abs(actual.minY - expected.minY) < 0.75
            && abs(actual.width - expected.width) < 0.75 && abs(actual.height - expected.height) < 0.75
    }

    /// Brave can settle one point smaller at a display edge. Accept only a
    /// verified result that stays completely inside the acknowledged cover.
    private static func matchesCoveredResult(_ actual: CGRect, _ expected: CGRect) -> Bool {
        matches(actual, expected)
            || (expected.contains(actual) && WindowRecoveryGeometry.near(actual, expected, tolerance: 1))
    }
}
