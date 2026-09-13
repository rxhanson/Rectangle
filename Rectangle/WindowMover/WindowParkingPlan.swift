import Foundation
import CoreGraphics

/// All rectangles use Core Graphics desktop coordinates (positive Y points down).
struct WindowParkingDisplay: Codable, Equatable {
    let id: UInt32
    let bounds: CGRect
    let visibleFrame: CGRect
}

struct WindowParkingOperation: Codable, Equatable {
    enum Attribute: String, Codable { case position, size }
    let attribute: Attribute
    let frame: CGRect
    let corner: Bool
    let phase: String
    /// A retained destination cover for a later parking pass in the same lease.
    var departureCover: CGRect? = nil
}

/// A refused shrink is still a usable preparation result while the original
/// source cover contains every pixel. This is not a minimum-size prediction:
/// subsequent parking and placement must verify their own exact frames.
enum WindowSourceCoverResize {
    static func accepts(actual: CGRect, requested: CGRect, source: CGRect) -> Bool {
        guard WindowRecoveryGeometry.valid(actual), WindowRecoveryGeometry.valid(requested),
              WindowRecoveryGeometry.valid(source), requested.origin == source.origin,
              source.contains(requested), source.contains(actual), actual.origin == source.origin else { return false }
        return actual.width >= requested.width && actual.height >= requested.height
    }
}

/// A verified-state route. Visible placement belongs to the coordinator, after proxy arrival.
struct WindowParkingPlan {
    enum Sizing { case hidden, covered }

    // Mail's native toolbar clamps bottom-corner parking upward by 65pt.
    // Planning and readback must allow the same bounded movement.
    static let maximumUpwardClamp: CGFloat = 65

    let source: CGRect
    let destination: CGRect
    let initialParking: CGRect
    let operations: [WindowParkingOperation]
    let widthDisplayID: UInt32
    let sizing: Sizing

    static func preferred(source: CGRect, destination: CGRect,
                          displays: [WindowParkingDisplay]) -> WindowParkingPlan? {
        // Moving a focused window to another display's corner can change the
        // active display before mouse-up. Preserve local parking during a drag.
        make(source: source, destination: destination, displays: displays, allowCrossDisplay: false)
            ?? makeCovered(source: source, destination: destination, displays: displays)
    }

    /// Display commands may grow beyond the source display's usable height.
    /// Keep a compact window at the source's safe corner, then grow only after
    /// it reaches the fully acknowledged destination cover. Native window apps
    /// can clamp an offscreen height expansion back into the source display.
    static func preferredForDisplayCommand(source: CGRect, destination: CGRect,
                                           displays: [WindowParkingDisplay], compactLimit: CGSize? = nil) -> WindowParkingPlan? {
        let preparation = CGRect(origin: destination.origin,
            size: CGSize(width: min(destination.width, compactLimit?.width ?? destination.width),
                         height: min(destination.height, compactLimit?.height ?? destination.height)))
        if let plan = makeCovered(source: source, destination: preparation, displays: displays, crossDisplay: true) {
            return WindowParkingPlan(source: source, destination: destination, initialParking: plan.initialParking,
                operations: plan.operations, widthDisplayID: plan.widthDisplayID, sizing: plan.sizing)
        }
        return preferredForReleasedSnap(source: source, destination: destination, displays: displays)
    }

    /// Prefer the source display even after mouse-up: visiting another display's
    /// corner changes the active menu bar while the proxy still animates locally.
    /// A cross-display snap may still need another display's verified corner.
    /// Do not shrink a straddling window in place: macOS can clamp that resize to
    /// preserve a titlebar on its native display, even under an adequate cover.
    static func preferredForReleasedSnap(source: CGRect, destination: CGRect,
                                         displays: [WindowParkingDisplay]) -> WindowParkingPlan? {
        guard valid(source), valid(destination), valid(displays),
              let display = sourceDisplay(source, displays: displays, releasedSnap: true),
              displays.contains(where: { $0.visibleFrame.contains(destination) }) else { return nil }
        if display.visibleFrame.contains(destination) {
            if let local = makeRoute(source: source, destination: destination, displays: displays,
                                     sourceDisplays: [display], allowCrossDisplay: false) { return local }
            // The local right corner can overlap a lower neighboring screen.
            // Shrink under the source cover and grow under the destination cover
            // so the compact window can remain at the safe local left corner.
            if let local = makeCovered(source: source, destination: destination, displays: displays) { return local }
            // A narrow source cannot lose width at its current left edge, and
            // native apps can refuse a width shrink at the hidden left corner.
            // Keep its size while parked, then resize under the destination
            // cover only if every excess pixel lies outside all displays.
            let parked = left(source.size, display)
            let operations = [operation(.position, parked, "initial-parking")]
            if coveredPlacementFrame(size: source.size, destination: destination, displays: displays) != nil,
               safe(operations, displays) {
                return WindowParkingPlan(source: source, destination: destination,
                    initialParking: parked, operations: operations,
                    widthDisplayID: display.id, sizing: .covered)
            }
        }
        if let hidden = makeRoute(source: source, destination: destination, displays: displays,
                                  sourceDisplays: [display], allowCrossDisplay: true) { return hidden }
        // A taller destination need not fit on the parking display. Prepare only
        // the shared size there, then grow under the acknowledged destination cover.
        let compact = CGRect(origin: destination.origin,
                             size: CGSize(width: min(source.width, destination.width),
                                          height: min(source.height, destination.height)))
        if let hidden = makeRoute(source: source, destination: compact, displays: displays,
                                  sourceDisplays: [display], allowCrossDisplay: true) {
            return WindowParkingPlan(source: source, destination: destination,
                                     initialParking: hidden.initialParking, operations: hidden.operations,
                                     widthDisplayID: hidden.widthDisplayID, sizing: .covered)
        }
        // Native drag settlement can restore a previous snap's tall size on a
        // shorter screen. Shrink height under the source cover before parking;
        // preserve width here so native titlebar visibility cannot clamp it.
        for parkingDisplay in displays.sorted(by: { $0.id < $1.id }) {
            let height = min(source.height, destination.height, parkingDisplay.visibleFrame.height)
            guard height < source.height else { continue }
            let shortened = CGRect(origin: source.origin, size: CGSize(width: source.width, height: height))
            let intermediate = CGRect(origin: destination.origin, size: CGSize(width: compact.width, height: height))
            guard let hidden = makeRoute(source: shortened, destination: intermediate, displays: displays,
                                         sourceDisplays: [display], allowCrossDisplay: true) else { continue }
            let shrink = WindowParkingOperation(attribute: .size, frame: shortened, corner: false,
                                                phase: "shrink-height-under-source-cover")
            return WindowParkingPlan(source: source, destination: destination, initialParking: hidden.initialParking,
                                     operations: [shrink] + hidden.operations,
                                     widthDisplayID: hidden.widthDisplayID, sizing: .covered)
        }
        return preferred(source: source, destination: destination, displays: displays)
    }

    /// A drag's first delivered movement may already cross a display edge. Its
    /// provisional position is not a parking constraint: prepare the requested
    /// size locally, then let the acknowledged cover follow the actual pointer.
    static func preferredForOwnedDrag(source: CGRect, destination: CGRect,
                                      displays: [WindowParkingDisplay]) -> WindowParkingPlan? {
        guard valid(source), valid(destination), valid(displays) else { return nil }
        if let display = sourceDisplay(source, displays: displays) {
            let usable = display.visibleFrame
            guard destination.width <= usable.width, destination.height <= usable.height else { return nil }
            var preparationTarget = destination
            preparationTarget.origin.x = min(max(destination.minX, usable.minX), usable.maxX - destination.width)
            preparationTarget.origin.y = min(max(destination.minY, usable.minY), usable.maxY - destination.height)
            // A restore commonly grows width while reducing height. Park the
            // unchanged snapped window first so pointer-following can begin;
            // shrinking beneath the stationary source cover adds a visible
            // preparation step before the drag moves. Prepare the shared size
            // only after parking, and grow beneath the destination cover.
            let compact = CGRect(origin: preparationTarget.origin,
                size: CGSize(width: min(source.width, destination.width),
                             height: min(source.height, destination.height)))
            if let hidden = makeRoute(source: source, destination: compact, displays: displays,
                                      sourceDisplays: [display], allowCrossDisplay: false) {
                return WindowParkingPlan(source: source, destination: preparationTarget,
                    initialParking: hidden.initialParking, operations: hidden.operations,
                    widthDisplayID: hidden.widthDisplayID,
                    sizing: compact.size == preparationTarget.size ? .hidden : .covered)
            }
            if let plan = preferred(source: source, destination: preparationTarget, displays: displays) { return plan }
        }
        return nil
    }

    /// After a covered native shrink was clamped, retry at a verified hidden
    /// corner only after release. Do not repeat the same covered shrink or infer
    /// a minimum size from the temporary titlebar-visibility constraint.
    static func replanReleasedOwnedDrag(source: CGRect, destination: CGRect,
                                        displays: [WindowParkingDisplay]) -> WindowParkingPlan? {
        guard valid(source), valid(destination), valid(displays),
              WindowRecoveryGeometry.visible(destination, displays: displays),
              let display = sourceDisplay(source, displays: displays, releasedSnap: true) else { return nil }
        // A free drag may end across a seam. Its destination position does not
        // constrain hidden sizing; makeRoute still validates every parked write.
        return makeRoute(source: source, destination: destination, displays: displays,
                         sourceDisplays: [display], allowCrossDisplay: true)
    }

    static func make(source: CGRect, destination: CGRect, displays: [WindowParkingDisplay],
                     minimumSize: CGSize? = nil, allowCrossDisplay: Bool = true) -> WindowParkingPlan? {
        guard valid(source), valid(destination), source != destination, valid(displays) else { return nil }
        if let minimumSize {
            guard minimumSize.width.isFinite, minimumSize.height.isFinite,
                  minimumSize.width > 0, minimumSize.height > 0,
                  destination.width >= minimumSize.width, destination.height >= minimumSize.height else { return nil }
        }
        // A parked source cannot establish the original display or recovery rectangle.
        let sourceDisplays = displays.filter {
            $0.bounds.contains(source) && $0.visibleFrame.contains(destination)
        }.sorted { $0.id < $1.id }
        return makeRoute(source: source, destination: destination, displays: displays,
                         sourceDisplays: sourceDisplays, allowCrossDisplay: allowCrossDisplay)
    }

    /// A released drag may choose a different snap size after the real window is
    /// already parked. Reuse the corner route without treating that hidden frame
    /// as a visible source or creating a new recovery lease.
    static func resizeParkedForDrag(source: CGRect, destination: CGRect, visibleSource: CGRect,
                                    displays: [WindowParkingDisplay]) -> WindowParkingPlan? {
        guard valid(destination), valid(visibleSource), valid(displays),
              let display = sourceDisplay(visibleSource, displays: displays) else { return nil }
        let usable = display.visibleFrame
        guard destination.width <= usable.width, destination.height <= usable.height else { return nil }
        var preparationTarget = destination
        preparationTarget.origin.x = min(max(destination.minX, usable.minX), usable.maxX - destination.width)
        preparationTarget.origin.y = min(max(destination.minY, usable.minY), usable.maxY - destination.height)
        return resizeParked(source: source, destination: preparationTarget, displays: displays)
    }

    static func resizeParked(source: CGRect, destination: CGRect,
                             displays: [WindowParkingDisplay]) -> WindowParkingPlan? {
        guard valid(source), valid(destination), valid(displays),
              narrow(source, displays) else { return nil }
        let destinationDisplays = displays.filter {
            $0.visibleFrame.contains(destination)
        }.sorted { $0.id < $1.id }
        return makeRoute(source: source, destination: destination, displays: displays,
                         sourceDisplays: destinationDisplays, allowCrossDisplay: false)
    }

    private static func makeRoute(source: CGRect, destination: CGRect,
                                  displays: [WindowParkingDisplay], sourceDisplays: [WindowParkingDisplay],
                                  allowCrossDisplay: Bool) -> WindowParkingPlan? {
        var candidates: [WindowParkingPlan] = []
        for sourceDisplay in sourceDisplays {
            if source.width == destination.width {
                let first = left(source.size, sourceDisplay)
                var ops = [operation(.position, first, "initial-parking")]
                if source.height != destination.height {
                    ops.append(operation(.size, left(destination.size, sourceDisplay), "height-left"))
                }
                if safe(ops, displays) {
                    candidates.append(WindowParkingPlan(source: source, destination: destination,
                                                        initialParking: first, operations: ops,
                                                        widthDisplayID: sourceDisplay.id, sizing: .hidden))
                }
                for widthDisplay in displays where allowCrossDisplay || widthDisplay.id == sourceDisplay.id {
                    guard max(source.height, destination.height) <= widthDisplay.visibleFrame.height else { continue }
                    let first = right(source.size, widthDisplay)
                    var rightOps = [operation(.position, first, "initial-parking")]
                    if source.height != destination.height {
                        rightOps.append(operation(.size, right(destination.size, widthDisplay), "height-right"))
                    }
                    if safe(rightOps, displays) {
                        candidates.append(WindowParkingPlan(source: source, destination: destination,
                                                            initialParking: first, operations: rightOps,
                                                            widthDisplayID: widthDisplay.id, sizing: .hidden))
                    }
                }
                continue
            }
            for widthDisplay in displays where allowCrossDisplay || widthDisplay.id == sourceDisplay.id {
                var ops: [WindowParkingOperation] = []
                let bothFit = max(source.height, destination.height) <= widthDisplay.visibleFrame.height
                if bothFit {
                    ops.append(operation(.position, right(source.size, widthDisplay), "initial-parking"))
                    ops.append(operation(.size, right(destination.size, widthDisplay), "resize-right"))
                } else {
                    let bridgeHeight = min(source.height, destination.height, widthDisplay.visibleFrame.height)
                    let bridge = CGSize(width: source.width, height: bridgeHeight)
                    if source.height == bridgeHeight {
                        ops.append(operation(.position, right(source.size, widthDisplay), "initial-parking"))
                    } else {
                        ops.append(operation(.position, left(source.size, sourceDisplay), "initial-parking"))
                        ops.append(operation(.size, left(bridge, sourceDisplay), "bridge-height-left"))
                        ops.append(operation(.position, right(bridge, widthDisplay), "move-right"))
                    }
                    let resized = CGSize(width: destination.width, height: bridgeHeight)
                    ops.append(operation(.size, right(resized, widthDisplay), "width-right"))
                    if destination.height != bridgeHeight {
                        ops.append(operation(.position, left(resized, sourceDisplay), "move-left"))
                        ops.append(operation(.size, left(destination.size, sourceDisplay), "final-height-left"))
                    }
                }
                if safe(ops, displays), let first = ops.first {
                    candidates.append(WindowParkingPlan(source: source, destination: destination,
                                                        initialParking: first.frame, operations: ops,
                                                        widthDisplayID: widthDisplay.id, sizing: .hidden))
                }
            }
        }
        // Fewer writes also means fewer independent compositor-settling waits.
        return candidates.sorted { lhs, rhs in
            if lhs.operations.count != rhs.operations.count { return lhs.operations.count < rhs.operations.count }
            let lhsLocal = sourceDisplays.contains { $0.id == lhs.widthDisplayID }
            let rhsLocal = sourceDisplays.contains { $0.id == rhs.widthDisplayID }
            if lhsLocal != rhsLocal { return lhsLocal }
            return lhs.widthDisplayID < rhs.widthDisplayID
        }.first
    }

    /// Resize only while covered at a visible endpoint. The parked intermediate
    /// fits inside both endpoint covers and never needs another display's corner.
    static func makeCovered(source: CGRect, destination: CGRect,
                            displays: [WindowParkingDisplay], crossDisplay: Bool = false) -> WindowParkingPlan? {
        guard valid(source), valid(destination), source != destination, valid(displays),
              let display = sourceDisplay(source, displays: displays),
              WindowRecoveryGeometry.visible(destination, displays: crossDisplay ? displays : [display]) else { return nil }
        let size = CGSize(width: min(source.width, destination.width),
                          height: min(source.height, destination.height))
        let compact = CGRect(origin: source.origin, size: size)
        for corner in [left(size, display), right(size, display)] {
            guard sweptSafe(corner, displays) else { continue }
            var operations: [WindowParkingOperation] = []
            if compact.size != source.size {
                operations.append(WindowParkingOperation(attribute: .size, frame: compact,
                                                         corner: false, phase: "shrink-under-source-cover"))
            }
            operations.append(operation(.position, corner, "initial-parking"))
            return WindowParkingPlan(source: source, destination: destination,
                                     initialParking: corner, operations: operations, widthDisplayID: display.id,
                                     sizing: .covered)
        }
        return nil
    }

    /// Place an intermediate beneath the final cover. Excess size is allowed
    /// only offscreen, including the entire resize envelope and its endpoint.
    static func coveredPlacementFrame(size: CGSize, destination: CGRect,
                                      displays: [WindowParkingDisplay]) -> CGRect? {
        let ordinary = CGRect(origin: destination.origin, size: size)
        guard valid(ordinary), valid(destination) else { return nil }
        if destination.contains(ordinary) { return ordinary }
        guard valid(displays), displays.contains(where: { $0.visibleFrame.contains(destination) }) else { return nil }
        for x in [destination.minX, destination.maxX - size.width] {
            for y in [destination.minY, destination.maxY - size.height] {
                let placed = CGRect(x: x, y: y, width: size.width, height: size.height)
                let resized = CGRect(origin: placed.origin, size: destination.size)
                let envelope = CGRect(x: x, y: y, width: max(size.width, destination.width),
                                      height: max(size.height, destination.height))
                guard WindowRecoveryGeometry.visible(placed, displays: displays),
                      WindowRecoveryGeometry.visible(resized, displays: displays),
                      displays.allSatisfy({ display in
                          let exposed = envelope.intersection(display.bounds)
                          return exposed.isNull || exposed.isEmpty || destination.contains(exposed)
                      }) else { continue }
                return placed
            }
        }
        return nil
    }

    /// A user can release a window across an edge. Its reachable titlebar and
    /// largest visible area identify the local display; a sliver at a parking
    /// corner must never qualify as a new visible source.
    private static func sourceDisplay(_ source: CGRect, displays: [WindowParkingDisplay], releasedSnap: Bool = false) -> WindowParkingDisplay? {
        let visible = releasedSnap ? WindowRecoveryGeometry.visibleReleasedSource : WindowRecoveryGeometry.visible
        return displays.filter { visible(source, [$0]) }.sorted {
            let lhs = $0.visibleFrame.intersection(source), rhs = $1.visibleFrame.intersection(source)
            let a = lhs.width * lhs.height, b = rhs.width * rhs.height
            return a == b ? $0.id < $1.id : a > b
        }.first
    }

    static func accepts(actual: CGRect, expected: CGRect, displays: [WindowParkingDisplay]) -> Bool {
        guard valid(actual), valid(expected), valid(displays) else { return false }
        let upward = expected.minY - actual.minY
        return abs(actual.minX - expected.minX) <= 0.1
            && abs(actual.width - expected.width) <= 0.1
            && abs(actual.height - expected.height) <= 0.1
            && upward >= 0 && upward <= maximumUpwardClamp && narrow(actual, displays)
    }

    private static func operation(_ attribute: WindowParkingOperation.Attribute, _ frame: CGRect,
                                  _ phase: String) -> WindowParkingOperation {
        WindowParkingOperation(attribute: attribute, frame: frame, corner: true, phase: phase)
    }

    private static func left(_ size: CGSize, _ display: WindowParkingDisplay) -> CGRect {
        CGRect(x: display.visibleFrame.minX - size.width + 1,
               y: display.visibleFrame.maxY - 1, width: size.width, height: size.height)
    }

    private static func right(_ size: CGSize, _ display: WindowParkingDisplay) -> CGRect {
        CGRect(x: display.visibleFrame.maxX - 1, y: display.visibleFrame.maxY - 1,
               width: size.width, height: size.height)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && [frame.origin.x, frame.origin.y, frame.width, frame.height, frame.maxX, frame.maxY].allSatisfy { $0.isFinite }
            && frame.size.width > 1.1 && frame.size.height > 1.1
    }

    private static func valid(_ displays: [WindowParkingDisplay]) -> Bool {
        !displays.isEmpty && Set(displays.map { $0.id }).count == displays.count && displays.allSatisfy {
            valid($0.bounds) && valid($0.visibleFrame) && $0.bounds.contains($0.visibleFrame)
        }
    }

    private static func narrow(_ frame: CGRect, _ displays: [WindowParkingDisplay]) -> Bool {
        displays.allSatisfy {
            let overlap = frame.intersection($0.bounds)
            return overlap.isNull || overlap.width <= 0 || overlap.height <= 0 || overlap.width <= 1.1
        }
    }

    private static func sweptSafe(_ frame: CGRect, _ displays: [WindowParkingDisplay]) -> Bool {
        valid(frame) && narrow(frame, displays)
            && narrow(CGRect(x: frame.minX, y: frame.minY - maximumUpwardClamp, width: frame.width,
                             height: frame.height + maximumUpwardClamp), displays)
    }

    private static func safe(_ operations: [WindowParkingOperation], _ displays: [WindowParkingDisplay]) -> Bool {
        guard !operations.isEmpty else { return false }
        for (index, operation) in operations.enumerated() {
            guard sweptSafe(operation.frame, displays) else { return false }
            if index > 0 && operation.attribute == .size {
                let previous = operations[index - 1].frame
                guard previous.origin == operation.frame.origin else { return false }
                // Either dimension can settle first. Validate their complete size envelope.
                let envelope = CGRect(origin: previous.origin,
                                      size: CGSize(width: max(previous.width, operation.frame.width),
                                                   height: max(previous.height, operation.frame.height)))
                guard sweptSafe(envelope, displays) else { return false }
            }
            // Position writes are discrete corner moves; their endpoint clamp sweeps are checked.
            // Runtime readback must still reject any unexpectedly wide intermediate observation.
        }
        return true
    }
}
