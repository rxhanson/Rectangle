import Cocoa

/// AX attributes can be accepted asynchronously. Acknowledge each attribute
/// before sending the next one so a delayed position write cannot discard an
/// earlier resize. Rollback uses the same acknowledgment path.
final class WindowDividerPlacement {
    enum State: Equatable { case waiting, completed, rolledBack, failed }
    enum Attribute { case size, position }
    private struct Pending {
        let index: Int
        let attribute: Attribute
        let before: CGRect
        let expected: CGRect
        let startedAt: TimeInterval
        var observed: CGRect
        var stableSince: TimeInterval
    }

    private let geometry: WindowDividerGeometry
    private let requested: CGFloat
    private let warningReference: CGFloat
    private let originals: [CGRect]
    private var targets: [CGRect]
    private var minima: [CGFloat]
    private var learnedMinima: [CGFloat?] = [nil, nil]
    private let write: (Bool, CGRect, Attribute) -> Bool
    private let readFrame: (Bool) -> CGRect
    private let acknowledged: ((Bool, CGRect) -> Bool)?
    private var readbacks: [Bool: CGRect] = [:]

    private func read(_ isLeft: Bool) -> CGRect {
        if let frame = readbacks[isLeft] { return frame }
        let frame = readFrame(isLeft)
        readbacks[isLeft] = frame
        return frame
    }
    private var order: [Int]
    private var cursor = 0
    private var pending: Pending?
    private var rollingBack = false
    private var rollbackIncomplete = false
    private var terminal: State?
    private var unreadableSince: TimeInterval?
    private(set) var verifiedPairSince: TimeInterval?

    /// Remembered bounds already stop the handle. Warn only about an additional
    /// acknowledged limit, never rounding, rollback, or a refused write.
    var minimumSizeReached: Bool {
        guard terminal == .completed else { return false }
        let actual = (geometry.axis.rect(left).maxX + geometry.axis.rect(right).minX) / 2
        return abs(actual - warningReference) > 1
    }

    var left: CGRect { targets[0] }
    var right: CGRect { targets[1] }

    init?(left: CGRect, right: CGRect, axis: WindowSplitAxis, divider: CGFloat,
          minimumLeft: CGFloat, minimumRight: CGFloat,
          rememberedMinimumLeft: CGFloat? = nil, rememberedMinimumRight: CGFloat? = nil,
          write: @escaping (Bool, CGRect, Attribute) -> Bool,
          read: @escaping (Bool) -> CGRect, acknowledged: ((Bool, CGRect) -> Bool)? = nil) {
        guard let geometry = WindowDividerGeometry(left: left, right: right, axis: axis),
              let target = geometry.frames(at: divider, minimumLeft: minimumLeft, minimumRight: minimumRight) else { return nil }
        self.geometry = geometry; requested = divider
        warningReference = geometry.warningReference(at: divider, rememberedMinimumLeft: rememberedMinimumLeft,
                                                     rememberedMinimumRight: rememberedMinimumRight)
        originals = [left, right]; targets = [target.left, target.right]
        minima = [minimumLeft, minimumRight]; self.write = write; self.readFrame = read; self.acknowledged = acknowledged
        order = axis.rect(target.left).width < axis.rect(left).width ? [0, 1] : [1, 0]
    }

    func advance(at time: TimeInterval) -> State {
        if let terminal { return terminal }
        readbacks.removeAll(keepingCapacity: true)
        if var waiting = pending {
            let actual = read(waiting.index == 0)
            // Reuse only simultaneous observations of both final frames. A new
            // write, changed target, or mismatch starts the stability period over.
            if LayoutHelperLayout.matches(actual, targets[waiting.index], tolerance: 1),
               LayoutHelperLayout.matches(read(waiting.index != 0), targets[1 - waiting.index], tolerance: 1) {
                if verifiedPairSince == nil { verifiedPairSince = time }
            } else { verifiedPairSince = nil }
            if !LayoutHelperLayout.matches(actual, waiting.observed, tolerance: 0.5) {
                waiting.observed = actual; waiting.stableSince = time
            }
            let stable = time - waiting.stableSince >= 0.05
            if LayoutHelperLayout.matches(actual, waiting.expected, tolerance: 1),
               stable || acknowledged?(waiting.index == 0, waiting.expected) == true {
                pending = nil
            } else if !rollingBack, waiting.attribute == .size, stable,
                      acceptClamp(actual, pending: waiting) {
                pending = nil
            } else if time - waiting.startedAt >= 0.6 {
                failCurrent()
            } else {
                pending = waiting
                return .waiting
            }
        }
        while cursor < order.count {
            let index = order[cursor], current = read(order[cursor] == 0), target = targets[index]
            guard !current.isNull, !current.isEmpty else {
                if let since = unreadableSince, time - since >= 0.6 { failCurrent() }
                else if unreadableSince == nil { unreadableSince = time }
                return .waiting
            }
            unreadableSince = nil
            if LayoutHelperLayout.matches(current, target, tolerance: 1) { cursor += 1; continue }
            let attribute: Attribute
            if geometry.axis.rect(target).minX < geometry.axis.rect(current).minX - 1 {
                attribute = .position
            } else if abs(current.width - target.width) > 1 || abs(current.height - target.height) > 1 {
                attribute = .size
            } else { attribute = .position }
            let expected = attribute == .size ? CGRect(origin: current.origin, size: target.size)
                : CGRect(origin: target.origin, size: current.size)
            // AX can report a timeout while the app still applies the request.
            // The bounded readback below decides whether placement succeeded.
            verifiedPairSince = nil
            _ = write(index == 0, expected, attribute)
            readbacks.removeAll(keepingCapacity: true)
            pending = Pending(index: index, attribute: attribute, before: current,
                              expected: expected, startedAt: time, observed: current, stableSince: time)
            return .waiting
        }
        let actualLeft = read(true), actualRight = read(false)
        guard !actualLeft.isNull, !actualLeft.isEmpty, !actualRight.isNull, !actualRight.isEmpty else {
            if let since = unreadableSince, time - since >= 0.6 {
                if rollingBack { terminal = .failed; return .failed }
                failCurrent()
            } else if unreadableSince == nil { unreadableSince = time }
            return .waiting
        }
        unreadableSince = nil
        guard LayoutHelperLayout.matches(actualLeft, targets[0], tolerance: 1),
              LayoutHelperLayout.matches(actualRight, targets[1], tolerance: 1) else {
            if rollingBack { terminal = .failed; return .failed }
            failCurrent(); return .waiting
        }
        terminal = rollbackIncomplete ? .failed : rollingBack ? .rolledBack : .completed
        return terminal!
    }

    private func acceptClamp(_ actual: CGRect, pending: Pending) -> Bool {
        let axis = geometry.axis
        let actual = axis.rect(actual), expected = axis.rect(pending.expected), before = axis.rect(pending.before)
        // An unchanged/refused write is not evidence of an app's minimum.
        guard !actual.isNull, abs(actual.minX - expected.minX) <= 1,
              abs(actual.minY - expected.minY) <= 1, abs(actual.height - expected.height) <= 1,
              actual.width > expected.width + 1, actual.width < before.width - 1 else { return false }
        var updated = minima; updated[pending.index] = max(updated[pending.index], actual.width)
        guard let corrected = geometry.frames(at: requested, minimumLeft: updated[0], minimumRight: updated[1]) else { return false }
        minima = updated; targets = [corrected.left, corrected.right]
        learnedMinima[pending.index] = actual.width
        verifiedPairSince = nil
        return true
    }

    private func failCurrent() {
        verifiedPairSince = nil
        pending = nil
        unreadableSince = nil
        if rollingBack {
            rollbackIncomplete = true; cursor += 1
        } else {
            rollingBack = true; targets = originals; cursor = 0
            // Release space before restoring the other member.
            order = geometry.axis.rect(read(true)).width > geometry.axis.rect(originals[0]).width ? [0, 1] : [1, 0]
        }
    }
}

extension WindowDividerPlacement {
    struct Result {
        let left: CGRect
        let right: CGRect
        let minimumSizeReached: Bool
        let minimumLeft: CGFloat?
        let minimumRight: CGFloat?
    }

    /// The existing incremental placement and reveal gates run on one worker.
    /// Check ownership between app replies; cancellation never waits on AX.
    func settle(isCurrent: () -> Bool,
                now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                pause: () -> Void = { Thread.sleep(forTimeInterval: 0.025) }) -> Result? {
        let deadline = now() + 6
        while isCurrent(), now() < deadline {
            switch advance(at: now()) {
            case .waiting: pause()
            case .failed: return nil
            case .completed, .rolledBack:
                var gate = WindowDividerRevealGate(left: left, right: right,
                    startedAt: now(), matchedSince: verifiedPairSince)
                while isCurrent(), now() < deadline {
                    let actualLeft = readFrame(true)
                    guard isCurrent() else { return nil }
                    let actualRight = readFrame(false)
                    guard isCurrent() else { return nil }
                    // The fast per-attribute acknowledgment is optional, but a
                    // supplied verifier must agree with both final frames before
                    // they can be revealed or retained as size-limit evidence.
                    let leftVerified = acknowledged?(true, actualLeft) ?? true
                    guard isCurrent() else { return nil }
                    let rightVerified = acknowledged?(false, actualRight) ?? true
                    guard isCurrent() else { return nil }
                    switch gate.observe(left: leftVerified ? actualLeft : .null,
                                        right: rightVerified ? actualRight : .null, at: now()) {
                    case .waiting: pause()
                    case .ready: return Result(left: left, right: right, minimumSizeReached: minimumSizeReached,
                        minimumLeft: terminal == .completed ? learnedMinima[0] : nil,
                        minimumRight: terminal == .completed ? learnedMinima[1] : nil)
                    case .timedOut: return nil
                    }
                }
                return nil
            }
        }
        return nil
    }
}
