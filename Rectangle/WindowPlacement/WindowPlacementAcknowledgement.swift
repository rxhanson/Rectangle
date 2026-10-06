import Cocoa

/// Size requests receive at most two retries. An unchanged size without
/// reported constraints gets one bounded growth probe.
struct WindowPlacementAcknowledgement {
    enum Decision { case waiting, position(CGPoint), size(CGSize), complete(CGRect), failed }
    let target: CGRect
    let bounds: CGRect?
    private var waitingUntil: TimeInterval
    private var pending: Decision = .waiting
    private var positionWrites = 0
    private var sizeWrites = 0
    private var stableAt: TimeInterval?
    private let placement: WindowAnimationPlacement?
    private let original: CGRect?
    private let reportedMinimum: CGSize?
    private var previousSize: CGSize?
    private var sizeStableAt: TimeInterval?
    private var resizeResponded = false
    private var probeAttempted = false
    private var probeSize: CGSize?
    private var verifiedProbeSize: CGSize?
    private var probePosition: CGPoint?
    private var acceptedSize: CGSize?
    private var animationEvidence: WindowPlacementAnimationEvidence?
    private let directPlacement: Bool
    private let minimumHint: CGSize?
    private var sizeRequestedAt: TimeInterval?

    init(target: CGRect, startedAt: TimeInterval, pendingWrite: Bool, bounds: CGRect? = nil,
         placement: WindowAnimationPlacement? = nil, original: CGRect? = nil, reportedMinimum: CGSize? = nil,
         animationEvidence: WindowPlacementAnimationEvidence? = nil,
         directPlacement: Bool = false, minimumHint: CGSize? = nil) {
        self.target = target
        self.bounds = bounds
        self.placement = placement
        self.original = original
        self.reportedMinimum = reportedMinimum
        self.animationEvidence = animationEvidence
        self.directPlacement = directPlacement
        self.minimumHint = minimumHint
        waitingUntil = startedAt + (pendingWrite ? 0.65 : 0)
    }

    mutating func observe(_ frame: CGRect?, at now: TimeInterval) -> Decision {
        if let evidence = animationEvidence,
           !evidence.isCurrent(target: target, placement: placement, at: now) {
            animationEvidence = nil
            stableAt = nil
        }
        guard let frame, WindowAnimationGeometry.valid(frame) else {
            stableAt = nil; sizeStableAt = nil; previousSize = nil
            return .waiting
        }
        if let evidence = animationEvidence {
            if WindowAnimationGeometry.near(frame, evidence.frame, tolerance: 1) {
                // observe receives only fresh, agreeing AX/WindowServer frames.
                // Reuse the animation's resize retries instead of repeating them
                // or visibly probing a window that has already settled.
                if let stableAt, now - stableAt >= 0.04 { return .complete(frame) }
                if stableAt == nil { stableAt = now }
                return .waiting
            }
            animationEvidence = nil
            stableAt = nil
        }
        if let original, !sameSize(frame.size, original.size) { resizeResponded = true }
        if let previousSize, !sameSize(frame.size, previousSize) { resizeResponded = true }
        if previousSize.map({ sameSize($0, frame.size) }) != true { sizeStableAt = now }
        previousSize = frame.size
        if let acceptedSize, !sameSize(frame.size, acceptedSize) {
            self.acceptedSize = nil
            stableAt = nil
        }
        if directPlacement, acceptedSize == nil, placement != nil, probeSize == nil,
           let requestedAt = sizeRequestedAt, now - requestedAt >= 0.12,
           let sizeStableAt, now - sizeStableAt >= 0.12,
           verifiedConstrainedSize(frame.size) {
            acceptedSize = frame.size
            waitingUntil = now
        }
        if let acceptedSize {
            guard let placement else { return .failed }
            let aligned = placement.frame(for: target, actualSize: acceptedSize, origin: frame, progress: 1)
            if WindowAnimationGeometry.near(frame, aligned, tolerance: 1) {
                if let stableAt, now - stableAt >= 0.02 { return .complete(frame) }
                stableAt = now
                return .waiting
            }
            stableAt = nil
            guard now >= waitingUntil else { return .waiting }
            guard positionWrites < 2 else { return .failed }
            positionWrites += 1
            waitingUntil = now + 0.65
            return .position(aligned.origin)
        }
        let positionMatches = abs(frame.minX - target.minX) <= 1 && abs(frame.minY - target.minY) <= 1
        let sizeMatches = abs(frame.width - target.width) <= 1 && abs(frame.height - target.height) <= 1
        if positionMatches && sizeMatches {
            if let stableAt, now - stableAt >= 0.02 { return .complete(frame) }
            stableAt = now
            return .waiting
        }
        stableAt = nil
        switch pending {
        case .position(let point):
            if abs(frame.minX - point.x) <= 1 && abs(frame.minY - point.y) <= 1 { waitingUntil = now; pending = .waiting }
        case .size(let requested):
            if sameSize(frame.size, requested) {
                if probeSize != nil { resizeResponded = true; verifiedProbeSize = frame.size; probeSize = nil }
                waitingUntil = now; pending = .waiting
            }
        default: break
        }
        guard now >= waitingUntil else { return .waiting }
        if let point = probePosition, let probeSize {
            guard abs(frame.minX - point.x) <= 1, abs(frame.minY - point.y) <= 1 else { return .failed }
            probePosition = nil
            pending = .size(probeSize); waitingUntil = now + 0.65
            return pending
        }
        if probeSize != nil { return .failed }
        var position = target.origin
        if !sizeMatches, let bounds {
            // Reserve room for the larger size on each axis, including growth.
            // This prevents Dock/edge clipping from masquerading as a minimum.
            if directPlacement, bounds.insetBy(dx: -1, dy: -1).contains(frame) {
                // A same-screen shrink needs no staging move. Only make room
                // on growing axes that would otherwise be clipped by an edge.
                position = frame.origin
                if target.width > frame.width + 1 {
                    position.x = min(position.x, max(bounds.minX, bounds.maxX - target.width))
                }
                if target.height > frame.height + 1 {
                    position.y = min(position.y, max(bounds.minY, bounds.maxY - target.height))
                }
            } else {
                position.x = min(max(position.x, bounds.minX), max(bounds.minX, bounds.maxX - max(frame.width, target.width)))
                position.y = min(max(position.y, bounds.minY), max(bounds.minY, bounds.maxY - max(frame.height, target.height)))
            }
        }
        let needsPosition = abs(frame.minX - position.x) > 1 || abs(frame.minY - position.y) > 1
        if needsPosition && (positionWrites == 0 || sizeMatches) {
            guard positionWrites < 2 else { return .failed }
            positionWrites += 1
            pending = .position(position)
        } else if !sizeMatches {
            if sizeWrites >= 2 || (directPlacement && sizeWrites == 1 && !resizeResponded && !probeAttempted) {
                guard let placement, frame.width >= target.width - 1, frame.height >= target.height - 1 else { return .failed }
                guard let sizeStableAt, now - sizeStableAt >= 0.12 else { return .waiting }
                if !verifiedConstrainedSize(frame.size) {
                    // A successful AX return alone does not prove a resize was
                    // honored. Verify responsiveness before accepting a plateau.
                    guard !probeAttempted else { return .failed }
                    let probe = CGSize(width: frame.width + (frame.width > target.width + 1 ? 2 : 0),
                                       height: frame.height + (frame.height > target.height + 1 ? 2 : 0))
                    guard !placement.constrainToScreen
                        || (probe.width <= placement.screenFrame.width
                            && probe.height <= placement.screenFrame.height) else { return .failed }
                    probeAttempted = true; probeSize = probe; sizeWrites = 1
                    var point = frame.origin
                    if placement.constrainToScreen {
                        point.x = min(max(point.x, placement.screenFrame.minX), placement.screenFrame.maxX - probe.width)
                        point.y = min(max(point.y, placement.screenFrame.minY), placement.screenFrame.maxY - probe.height)
                    }
                    if abs(frame.minX - point.x) > 1 || abs(frame.minY - point.y) > 1 {
                        probePosition = point
                        pending = .position(point)
                    } else { pending = .size(probe) }
                    waitingUntil = now + 0.65
                    return pending
                }
                acceptedSize = frame.size
                waitingUntil = now
                return observe(frame, at: now)
            }
            sizeWrites += 1
            sizeRequestedAt = now
            pending = .size(target.size)
        } else { return .failed }
        waitingUntil = now + 0.65
        return pending
    }

    private func verifiedConstrainedSize(_ size: CGSize) -> Bool {
        guard size.width >= target.width - 1, size.height >= target.height - 1,
              !sameSize(size, target.size) else { return false }
        func verified(_ actual: CGFloat, _ requested: CGFloat, _ previous: CGFloat?,
                      _ reported: CGFloat?, _ hint: CGFloat?) -> Bool {
            if actual <= requested + 1 { return true }
            if let previous, actual < previous - 1 { return true }
            return [reported, hint].contains { value in
                guard let value, value.isFinite, value > 0 else { return false }
                return abs(value - actual) <= 1
            }
        }
        // Each constrained axis needs evidence. A change in height alone must
        // not justify accepting an ignored width request.
        return verified(size.width, target.width, verifiedProbeSize?.width ?? original?.width, reportedMinimum?.width, minimumHint?.width)
            && verified(size.height, target.height, verifiedProbeSize?.height ?? original?.height, reportedMinimum?.height, minimumHint?.height)
    }

    private func sameSize(_ first: CGSize, _ second: CGSize) -> Bool {
        abs(first.width - second.width) <= 1 && abs(first.height - second.height) <= 1
    }
}
