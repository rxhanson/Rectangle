/// CooperativeCornerResize.swift

import Cocoa

struct CooperativeCornerResize {
    struct Candidate {
        let id: CGWindowID
        let frame: CGRect
        let minimumSize: CGSize?

        init(id: CGWindowID, frame: CGRect, minimumSize: CGSize? = nil) {
            self.id = id
            self.frame = frame
            self.minimumSize = minimumSize
        }
    }

    struct Adjustment {
        let id: CGWindowID
        let oldFrame: CGRect
        let newFrame: CGRect
        let kind: Kind

        enum Kind {
            case matchingFocusedFrame
            case adjacent
        }
    }

    struct Plan {
        let focusedFrame: CGRect
        let adjustments: [Adjustment]
        let debugLog: [String]
    }

    enum MovedEdge {
        case left, right, top, bottom
    }

    private enum AffectedRole {
        case matchingFocusedFrame
        case matchingMovingSpan
        case adjacent
    }

    private struct AffectedWindow {
        let candidate: Candidate
        let role: AffectedRole
        let kind: Adjustment.Kind
        let minimumSize: CGSize
    }

    private struct EdgeRange {
        var min: CGFloat
        var max: CGFloat
        var lowerReasons: [String] = []
        var upperReasons: [String] = []

        mutating func requireMin(_ value: CGFloat, reason: String) {
            if value > min + 0.001 {
                min = value
                lowerReasons = [reason]
            } else if abs(value - min) <= 0.001 {
                lowerReasons.append(reason)
            }
        }

        mutating func requireMax(_ value: CGFloat, reason: String) {
            if value < max - 0.001 {
                max = value
                upperReasons = [reason]
            } else if abs(value - max) <= 0.001 {
                upperReasons.append(reason)
            }
        }
    }

    static func movedEdge(from oldFocusedFrame: CGRect,
                          to newFocusedFrame: CGRect,
                          axis: CornerCycleExpansionAxis,
                          tolerance: CGFloat) -> MovedEdge? {
        switch axis {
        case .horizontal:
            let leftMoved = abs(oldFocusedFrame.minX - newFocusedFrame.minX) > tolerance
            let rightMoved = abs(oldFocusedFrame.maxX - newFocusedFrame.maxX) > tolerance
            guard leftMoved != rightMoved else { return nil }
            return leftMoved ? .left : .right
        case .vertical:
            let bottomMoved = abs(oldFocusedFrame.minY - newFocusedFrame.minY) > tolerance
            let topMoved = abs(oldFocusedFrame.maxY - newFocusedFrame.maxY) > tolerance
            guard bottomMoved != topMoved else { return nil }
            return bottomMoved ? .bottom : .top
        }
    }

    static func adjustments(oldFocusedFrame: CGRect,
                            newFocusedFrame: CGRect,
                            screenFrame: CGRect,
                            candidates: [Candidate],
                            axis: CornerCycleExpansionAxis,
                            tolerance: CGFloat,
                            minimumSize: CGSize) -> [Adjustment] {
        plan(oldFocusedFrame: oldFocusedFrame,
             newFocusedFrame: newFocusedFrame,
             screenFrame: screenFrame,
             candidates: candidates,
             axis: axis,
             tolerance: tolerance,
             minimumSize: minimumSize)?.adjustments ?? []
    }

    static func plan(oldFocusedFrame: CGRect,
                     newFocusedFrame: CGRect,
                     screenFrame: CGRect,
                     candidates: [Candidate],
                     axis: CornerCycleExpansionAxis,
                     tolerance: CGFloat,
                     minimumSize: CGSize,
                     focusedMinimumSize: CGSize? = nil) -> Plan? {
        guard let movedEdge = movedEdge(from: oldFocusedFrame, to: newFocusedFrame, axis: axis, tolerance: tolerance),
              !oldFocusedFrame.isNull,
              !newFocusedFrame.isNull,
              !screenFrame.isNull
        else {
            return nil
        }

        let fallbackMinimumSize = normalizedMinimumSize(minimumSize)
        let resolvedFocusedMinimumSize = normalizedMinimumSize(focusedMinimumSize ?? fallbackMinimumSize)
        let affectedWindows = affectedWindows(oldFocusedFrame: oldFocusedFrame,
                                              newFocusedFrame: newFocusedFrame,
                                              screenFrame: screenFrame,
                                              candidates: candidates,
                                              movedEdge: movedEdge,
                                              tolerance: tolerance,
                                              fallbackMinimumSize: fallbackMinimumSize)
        guard !affectedWindows.isEmpty else { return nil }

        let oldEdge = edgeCoordinate(oldFocusedFrame, movedEdge)
        let desiredEdge = edgeCoordinate(newFocusedFrame, movedEdge)
        let requestedDelta = desiredEdge - oldEdge
        var debugLog = [
            "Cooperative resize visible frame: \(screenFrame.debugDescription)",
            "Cooperative resize requested delta: \(requestedDelta)",
            "Cooperative resize affected windows: \(affectedWindows.map { "\($0.candidate.id)" }.joined(separator: ", "))"
        ]

        var edgeRange = EdgeRange(min: axisMin(screenFrame, axis), max: axisMax(screenFrame, axis))
        constrainFocusedWindow(&edgeRange,
                               movedEdge: movedEdge,
                               axis: axis,
                               newFocusedFrame: newFocusedFrame,
                               screenFrame: screenFrame,
                               minimumSize: resolvedFocusedMinimumSize)

        for affectedWindow in affectedWindows {
            constrainAffectedWindow(&edgeRange,
                                    affectedWindow: affectedWindow,
                                    movedEdge: movedEdge,
                                    axis: axis,
                                    newFocusedFrame: newFocusedFrame,
                                    screenFrame: screenFrame)
        }

        let clampedEdge = roundedEdge(clamp(desiredEdge, min: edgeRange.min, max: edgeRange.max),
                                      legalMin: edgeRange.min,
                                      legalMax: edgeRange.max)
        let focusedFrame = roundedFrameInsideVisibleFrame(
            sameSideFrame(baseFrame: newFocusedFrame,
                          movedEdge: movedEdge,
                          axis: axis,
                          edge: clampedEdge,
                          newFocusedFrame: newFocusedFrame,
                          screenFrame: screenFrame),
            visibleFrame: screenFrame
        )
        let proposedFocusedFrame = sameSideFrame(baseFrame: newFocusedFrame,
                                                 movedEdge: movedEdge,
                                                 axis: axis,
                                                 edge: desiredEdge,
                                                 newFocusedFrame: newFocusedFrame,
                                                 screenFrame: screenFrame)

        debugLog.append("Cooperative resize proposed focused rectangle: \(proposedFocusedFrame.debugDescription)")
        debugLog.append("Cooperative resize clamped focused rectangle: \(focusedFrame.debugDescription)")

        let adjustments = affectedWindows.map { affectedWindow -> Adjustment in
            let proposedFrame = proposedFrameForAffectedWindow(affectedWindow,
                                                               desiredEdge: desiredEdge,
                                                               movedEdge: movedEdge,
                                                               axis: axis,
                                                               newFocusedFrame: newFocusedFrame,
                                                               screenFrame: screenFrame)
            let clampedFrame = clampedFrameForAffectedWindow(affectedWindow,
                                                             clampedEdge: clampedEdge,
                                                             movedEdge: movedEdge,
                                                             axis: axis,
                                                             newFocusedFrame: newFocusedFrame,
                                                             screenFrame: screenFrame)
            debugLog.append("Cooperative resize proposed rectangle for \(affectedWindow.candidate.id): \(proposedFrame.debugDescription)")
            debugLog.append("Cooperative resize clamped rectangle for \(affectedWindow.candidate.id): \(clampedFrame.debugDescription)")

            return Adjustment(id: affectedWindow.candidate.id,
                              oldFrame: affectedWindow.candidate.frame,
                              newFrame: clampedFrame,
                              kind: affectedWindow.kind)
        }

        let appliedDelta = clampedEdge - oldEdge
        if abs(appliedDelta - requestedDelta) > 0.001 {
            let reasons = reductionReasons(forDesiredEdge: desiredEdge, edgeRange: edgeRange)
            debugLog.append("Cooperative resize reduced requested movement from \(requestedDelta) to \(appliedDelta): \(reasons.joined(separator: "; "))")
        }

        return Plan(focusedFrame: focusedFrame,
                    adjustments: adjustments,
                    debugLog: debugLog)
    }

    static func focusedWindowIsExpanding(oldFrame: CGRect, newFrame: CGRect, axis: CornerCycleExpansionAxis) -> Bool {
        switch axis {
        case .horizontal:
            return newFrame.width > oldFrame.width
        case .vertical:
            return newFrame.height > oldFrame.height
        }
    }

    private static func affectedWindows(oldFocusedFrame: CGRect,
                                        newFocusedFrame: CGRect,
                                        screenFrame: CGRect,
                                        candidates: [Candidate],
                                        movedEdge: MovedEdge,
                                        tolerance: CGFloat,
                                        fallbackMinimumSize: CGSize) -> [AffectedWindow] {
        let matchingFocusedFrameAdjustments = candidates.compactMap { candidate -> AffectedWindow? in
            guard !candidate.frame.isNull,
                  screenFrame.intersects(candidate.frame),
                  approximatelyMatchesFrame(candidate.frame, oldFocusedFrame, tolerance: tolerance)
            else {
                return nil
            }

            return AffectedWindow(candidate: candidate,
                                  role: .matchingFocusedFrame,
                                  kind: .matchingFocusedFrame,
                                  minimumSize: normalizedMinimumSize(candidate.minimumSize ?? fallbackMinimumSize))
        }

        let matchingFocusedFrameIds = Set(matchingFocusedFrameAdjustments.map(\.candidate.id))

        let matchingMovingSpanAdjustments = candidates.compactMap { candidate -> AffectedWindow? in
            guard !matchingFocusedFrameIds.contains(candidate.id),
                  !candidate.frame.isNull,
                  screenFrame.intersects(candidate.frame),
                  matchesMovingSpan(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
                  isSupportedPerpendicularSpan(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance)
            else {
                return nil
            }

            return AffectedWindow(candidate: candidate,
                                  role: .matchingMovingSpan,
                                  kind: .matchingFocusedFrame,
                                  minimumSize: normalizedMinimumSize(candidate.minimumSize ?? fallbackMinimumSize))
        }

        let matchingMovingSpanIds = Set(matchingMovingSpanAdjustments.map(\.candidate.id))

        let adjacentAdjustments = candidates.compactMap { candidate -> AffectedWindow? in
            guard !matchingFocusedFrameIds.contains(candidate.id),
                  !matchingMovingSpanIds.contains(candidate.id),
                  !candidate.frame.isNull,
                  screenFrame.intersects(candidate.frame),
                  isSupportedPerpendicularSpan(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
                  touchesOldMovingEdge(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance)
            else {
                return nil
            }

            return AffectedWindow(candidate: candidate,
                                  role: .adjacent,
                                  kind: .adjacent,
                                  minimumSize: normalizedMinimumSize(candidate.minimumSize ?? fallbackMinimumSize))
        }

        return matchingFocusedFrameAdjustments + matchingMovingSpanAdjustments + adjacentAdjustments
    }

    private static func constrainFocusedWindow(_ edgeRange: inout EdgeRange,
                                               movedEdge: MovedEdge,
                                               axis: CornerCycleExpansionAxis,
                                               newFocusedFrame: CGRect,
                                               screenFrame: CGRect,
                                               minimumSize: CGSize) {
        constrainSameSideWindow(&edgeRange,
                                label: "focused window",
                                movedEdge: movedEdge,
                                axis: axis,
                                newFocusedFrame: newFocusedFrame,
                                screenFrame: screenFrame,
                                minimumSize: minimumSize)
    }

    private static func constrainAffectedWindow(_ edgeRange: inout EdgeRange,
                                                affectedWindow: AffectedWindow,
                                                movedEdge: MovedEdge,
                                                axis: CornerCycleExpansionAxis,
                                                newFocusedFrame: CGRect,
                                                screenFrame: CGRect) {
        let label = "window \(affectedWindow.candidate.id)"
        switch affectedWindow.role {
        case .matchingFocusedFrame, .matchingMovingSpan:
            constrainSameSideWindow(&edgeRange,
                                    label: label,
                                    movedEdge: movedEdge,
                                    axis: axis,
                                    newFocusedFrame: newFocusedFrame,
                                    screenFrame: screenFrame,
                                    minimumSize: affectedWindow.minimumSize)
        case .adjacent:
            constrainAdjacentWindow(&edgeRange,
                                    label: label,
                                    movedEdge: movedEdge,
                                    axis: axis,
                                    candidateFrame: affectedWindow.candidate.frame,
                                    screenFrame: screenFrame,
                                    minimumSize: affectedWindow.minimumSize)
        }
    }

    private static func constrainSameSideWindow(_ edgeRange: inout EdgeRange,
                                                label: String,
                                                movedEdge: MovedEdge,
                                                axis: CornerCycleExpansionAxis,
                                                newFocusedFrame: CGRect,
                                                screenFrame: CGRect,
                                                minimumSize: CGSize) {
        let minimumAxisSize = axisSize(minimumSize, axis)
        switch movedEdge {
        case .right, .top:
            let fixedMin = clamp(axisMin(newFocusedFrame, axis),
                                 min: axisMin(screenFrame, axis),
                                 max: axisMax(screenFrame, axis))
            edgeRange.requireMin(fixedMin + minimumAxisSize, reason: "\(label) minimum \(axisSizeName(axis))")
        case .left, .bottom:
            let fixedMax = clamp(axisMax(newFocusedFrame, axis),
                                 min: axisMin(screenFrame, axis),
                                 max: axisMax(screenFrame, axis))
            edgeRange.requireMax(fixedMax - minimumAxisSize, reason: "\(label) minimum \(axisSizeName(axis))")
        }
    }

    private static func constrainAdjacentWindow(_ edgeRange: inout EdgeRange,
                                                label: String,
                                                movedEdge: MovedEdge,
                                                axis: CornerCycleExpansionAxis,
                                                candidateFrame: CGRect,
                                                screenFrame: CGRect,
                                                minimumSize: CGSize) {
        let minimumAxisSize = axisSize(minimumSize, axis)
        switch movedEdge {
        case .right, .top:
            let outerMax = min(axisMax(candidateFrame, axis), axisMax(screenFrame, axis))
            edgeRange.requireMax(outerMax - minimumAxisSize, reason: "\(label) minimum \(axisSizeName(axis)) inside visible frame")
        case .left, .bottom:
            let outerMin = max(axisMin(candidateFrame, axis), axisMin(screenFrame, axis))
            edgeRange.requireMin(outerMin + minimumAxisSize, reason: "\(label) minimum \(axisSizeName(axis)) inside visible frame")
        }
    }

    private static func proposedFrameForAffectedWindow(_ affectedWindow: AffectedWindow,
                                                       desiredEdge: CGFloat,
                                                       movedEdge: MovedEdge,
                                                       axis: CornerCycleExpansionAxis,
                                                       newFocusedFrame: CGRect,
                                                       screenFrame: CGRect) -> CGRect {
        frameForAffectedWindow(affectedWindow,
                               edge: desiredEdge,
                               movedEdge: movedEdge,
                               axis: axis,
                               newFocusedFrame: newFocusedFrame,
                               screenFrame: screenFrame)
    }

    private static func clampedFrameForAffectedWindow(_ affectedWindow: AffectedWindow,
                                                      clampedEdge: CGFloat,
                                                      movedEdge: MovedEdge,
                                                      axis: CornerCycleExpansionAxis,
                                                      newFocusedFrame: CGRect,
                                                      screenFrame: CGRect) -> CGRect {
        roundedFrameInsideVisibleFrame(
            frameForAffectedWindow(affectedWindow,
                                   edge: clampedEdge,
                                   movedEdge: movedEdge,
                                   axis: axis,
                                   newFocusedFrame: newFocusedFrame,
                                   screenFrame: screenFrame),
            visibleFrame: screenFrame
        )
    }

    private static func frameForAffectedWindow(_ affectedWindow: AffectedWindow,
                                               edge: CGFloat,
                                               movedEdge: MovedEdge,
                                               axis: CornerCycleExpansionAxis,
                                               newFocusedFrame: CGRect,
                                               screenFrame: CGRect) -> CGRect {
        switch affectedWindow.role {
        case .matchingFocusedFrame:
            return sameSideFrame(baseFrame: newFocusedFrame,
                                 movedEdge: movedEdge,
                                 axis: axis,
                                 edge: edge,
                                 newFocusedFrame: newFocusedFrame,
                                 screenFrame: screenFrame)
        case .matchingMovingSpan:
            return sameSideFrame(baseFrame: affectedWindow.candidate.frame,
                                 movedEdge: movedEdge,
                                 axis: axis,
                                 edge: edge,
                                 newFocusedFrame: newFocusedFrame,
                                 screenFrame: screenFrame)
        case .adjacent:
            return adjacentFrame(baseFrame: affectedWindow.candidate.frame,
                                 movedEdge: movedEdge,
                                 axis: axis,
                                 edge: edge,
                                 screenFrame: screenFrame)
        }
    }

    private static func sameSideFrame(baseFrame: CGRect,
                                      movedEdge: MovedEdge,
                                      axis: CornerCycleExpansionAxis,
                                      edge: CGFloat,
                                      newFocusedFrame: CGRect,
                                      screenFrame: CGRect) -> CGRect {
        let visibleMin = axisMin(screenFrame, axis)
        let visibleMax = axisMax(screenFrame, axis)
        switch movedEdge {
        case .right, .top:
            let fixedMin = clamp(axisMin(newFocusedFrame, axis), min: visibleMin, max: visibleMax)
            return frame(baseFrame, axis: axis, min: fixedMin, max: edge, visibleFrame: screenFrame)
        case .left, .bottom:
            let fixedMax = clamp(axisMax(newFocusedFrame, axis), min: visibleMin, max: visibleMax)
            return frame(baseFrame, axis: axis, min: edge, max: fixedMax, visibleFrame: screenFrame)
        }
    }

    private static func adjacentFrame(baseFrame: CGRect,
                                      movedEdge: MovedEdge,
                                      axis: CornerCycleExpansionAxis,
                                      edge: CGFloat,
                                      screenFrame: CGRect) -> CGRect {
        switch movedEdge {
        case .right, .top:
            let outerMax = min(axisMax(baseFrame, axis), axisMax(screenFrame, axis))
            return frame(baseFrame, axis: axis, min: edge, max: outerMax, visibleFrame: screenFrame)
        case .left, .bottom:
            let outerMin = max(axisMin(baseFrame, axis), axisMin(screenFrame, axis))
            return frame(baseFrame, axis: axis, min: outerMin, max: edge, visibleFrame: screenFrame)
        }
    }

    private static func frame(_ baseFrame: CGRect,
                              axis: CornerCycleExpansionAxis,
                              min: CGFloat,
                              max: CGFloat,
                              visibleFrame: CGRect) -> CGRect {
        var rect = baseFrame
        let orderedMin = Swift.min(min, max)
        let orderedMax = Swift.max(min, max)
        switch axis {
        case .horizontal:
            let perpMin = Swift.max(baseFrame.minY, visibleFrame.minY)
            let perpMax = Swift.min(baseFrame.maxY, visibleFrame.maxY)
            rect.origin.x = orderedMin
            rect.size.width = orderedMax - orderedMin
            rect.origin.y = perpMin
            rect.size.height = Swift.max(0, perpMax - perpMin)
        case .vertical:
            let perpMin = Swift.max(baseFrame.minX, visibleFrame.minX)
            let perpMax = Swift.min(baseFrame.maxX, visibleFrame.maxX)
            rect.origin.x = perpMin
            rect.size.width = Swift.max(0, perpMax - perpMin)
            rect.origin.y = orderedMin
            rect.size.height = orderedMax - orderedMin
        }
        return rect
    }

    private static func roundedFrameInsideVisibleFrame(_ frame: CGRect, visibleFrame: CGRect) -> CGRect {
        var rect = CGRect(x: round(frame.origin.x),
                          y: round(frame.origin.y),
                          width: round(frame.width),
                          height: round(frame.height))

        if rect.minX < visibleFrame.minX {
            let delta = visibleFrame.minX - rect.minX
            rect.origin.x += delta
            rect.size.width = Swift.max(0, rect.width - delta)
        }
        if rect.minY < visibleFrame.minY {
            let delta = visibleFrame.minY - rect.minY
            rect.origin.y += delta
            rect.size.height = Swift.max(0, rect.height - delta)
        }
        if rect.maxX > visibleFrame.maxX {
            rect.size.width = Swift.max(0, visibleFrame.maxX - rect.minX)
        }
        if rect.maxY > visibleFrame.maxY {
            rect.size.height = Swift.max(0, visibleFrame.maxY - rect.minY)
        }

        return rect
    }

    private static func roundedEdge(_ edge: CGFloat, legalMin: CGFloat, legalMax: CGFloat) -> CGFloat {
        let rounded = round(edge)
        let integerMin = ceil(legalMin)
        let integerMax = floor(legalMax)
        guard integerMin <= integerMax else {
            return rounded
        }
        return clamp(rounded, min: integerMin, max: integerMax)
    }

    private static func reductionReasons(forDesiredEdge desiredEdge: CGFloat, edgeRange: EdgeRange) -> [String] {
        if edgeRange.min > edgeRange.max {
            return (edgeRange.lowerReasons + edgeRange.upperReasons).isEmpty
                ? ["no legal shared-edge position satisfies all constraints"]
                : edgeRange.lowerReasons + edgeRange.upperReasons
        }
        if desiredEdge < edgeRange.min {
            return edgeRange.lowerReasons.isEmpty ? ["visible frame lower bound"] : edgeRange.lowerReasons
        }
        if desiredEdge > edgeRange.max {
            return edgeRange.upperReasons.isEmpty ? ["visible frame upper bound"] : edgeRange.upperReasons
        }
        return ["integer pixel rounding"]
    }

    private static func edgeCoordinate(_ frame: CGRect, _ edge: MovedEdge) -> CGFloat {
        switch edge {
        case .left:
            return frame.minX
        case .right:
            return frame.maxX
        case .top:
            return frame.maxY
        case .bottom:
            return frame.minY
        }
    }

    private static func axisMin(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.minX : frame.minY
    }

    private static func axisMax(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.maxX : frame.maxY
    }

    private static func axisSize(_ size: CGSize, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? size.width : size.height
    }

    private static func axisSizeName(_ axis: CornerCycleExpansionAxis) -> String {
        axis == .horizontal ? "width" : "height"
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if min > max {
            return value < min ? min : max
        }
        return Swift.min(Swift.max(value, min), max)
    }

    private static func normalizedMinimumSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width), height: max(1, size.height))
    }

    private static func touchesOldMovingEdge(_ candidate: CGRect,
                                             _ focused: CGRect,
                                             movedEdge: MovedEdge,
                                             tolerance: CGFloat) -> Bool {
        switch movedEdge {
        case .left:
            return abs(candidate.maxX - focused.minX) <= tolerance
        case .right:
            return abs(candidate.minX - focused.maxX) <= tolerance
        case .bottom:
            return abs(candidate.maxY - focused.minY) <= tolerance
        case .top:
            return abs(candidate.minY - focused.maxY) <= tolerance
        }
    }

    private static func isSupportedPerpendicularSpan(_ candidate: CGRect,
                                                     _ focused: CGRect,
                                                     movedEdge: MovedEdge,
                                                     tolerance: CGFloat) -> Bool {
        switch movedEdge {
        case .left, .right:
            return approximatelyMatchesSpan(candidateMin: candidate.minY,
                                            candidateMax: candidate.maxY,
                                            focusedMin: focused.minY,
                                            focusedMax: focused.maxY,
                                            tolerance: tolerance)
        case .top, .bottom:
            return approximatelyMatchesSpan(candidateMin: candidate.minX,
                                            candidateMax: candidate.maxX,
                                            focusedMin: focused.minX,
                                            focusedMax: focused.maxX,
                                            tolerance: tolerance)
        }
    }

    private static func matchesMovingSpan(_ candidate: CGRect,
                                          _ focused: CGRect,
                                          movedEdge: MovedEdge,
                                          tolerance: CGFloat) -> Bool {
        switch movedEdge {
        case .left, .right:
            return abs(candidate.minX - focused.minX) <= tolerance
                && abs(candidate.maxX - focused.maxX) <= tolerance
        case .top, .bottom:
            return abs(candidate.minY - focused.minY) <= tolerance
                && abs(candidate.maxY - focused.maxY) <= tolerance
        }
    }

    private static func approximatelyMatchesSpan(candidateMin: CGFloat,
                                                 candidateMax: CGFloat,
                                                 focusedMin: CGFloat,
                                                 focusedMax: CGFloat,
                                                 tolerance: CGFloat) -> Bool {
        let fullMatch = abs(candidateMin - focusedMin) <= tolerance
            && abs(candidateMax - focusedMax) <= tolerance
        if fullMatch {
            return true
        }

        let candidateIsWithinFocused = candidateMin >= focusedMin - tolerance
            && candidateMax <= focusedMax + tolerance
        let sharesFocusedBoundary = abs(candidateMin - focusedMin) <= tolerance
            || abs(candidateMax - focusedMax) <= tolerance
        let meaningfulSpan = candidateMax - candidateMin > tolerance

        return candidateIsWithinFocused && sharesFocusedBoundary && meaningfulSpan
    }

    private static func approximatelyMatchesFrame(_ candidate: CGRect,
                                                  _ focused: CGRect,
                                                  tolerance: CGFloat) -> Bool {
        abs(candidate.minX - focused.minX) <= tolerance
            && abs(candidate.maxX - focused.maxX) <= tolerance
            && abs(candidate.minY - focused.minY) <= tolerance
            && abs(candidate.maxY - focused.maxY) <= tolerance
    }
}
