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
        let layoutFrame: CGRect
        let role: AffectedRole
        let kind: Adjustment.Kind
        let minimumSize: CGSize
        let inclusionReason: String
    }

    private struct AffectedWindowsResult {
        let windows: [AffectedWindow]
        let debugLog: [String]
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

    static func detectionTolerance(screenFrame: CGRect, configuredGap: CGFloat) -> CGFloat {
        let proportionalTolerance = min(screenFrame.width, screenFrame.height) * 0.015
        return min(24, max(8, proportionalTolerance))
    }

    static func captureTolerance(screenFrame: CGRect, axis: CornerCycleExpansionAxis) -> CGFloat {
        let dimension = axis == .horizontal ? screenFrame.width : screenFrame.height
        return min(96, max(8, dimension * 0.08))
    }

    static func framesDiffer(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        guard !lhs.isNull, !rhs.isNull else { return lhs.isNull != rhs.isNull }
        return abs(lhs.minX - rhs.minX) > tolerance
            || abs(lhs.minY - rhs.minY) > tolerance
            || abs(lhs.width - rhs.width) > tolerance
            || abs(lhs.height - rhs.height) > tolerance
    }

    static func frameNeedsApplication(currentFrame: CGRect,
                                      solvedFrame: CGRect,
                                      screenFrame: CGRect,
                                      layoutTolerance: CGFloat) -> Bool {
        frameNeedsCorrection(plannedFrame: solvedFrame,
                             actualFrame: currentFrame,
                             screenFrame: screenFrame,
                             tolerance: layoutTolerance)
    }

    static func focusedFramePreservingOccupiedCell(requestedFocusedFrame: CGRect,
                                                   screenFrame: CGRect,
                                                   candidates: [Candidate],
                                                   axis: CornerCycleExpansionAxis,
                                                   movedEdge: MovedEdge,
                                                   tolerance: CGFloat) -> CGRect {
        guard !requestedFocusedFrame.isNull,
              !screenFrame.isNull
        else {
            return requestedFocusedFrame
        }

        let requestedSize = axisSize(requestedFocusedFrame.size, axis)
        let desiredEdge = edgeCoordinate(requestedFocusedFrame, movedEdge)
        let matchingCandidates = candidates.filter { candidate in
            let frame = candidate.frame
            guard !frame.isNull,
                  screenFrame.intersects(frame),
                  axisSize(frame.size, axis) < requestedSize - tolerance,
                  matchesPerpendicularSpan(frame, requestedFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
                  isContainedInSameSideRegion(frame, requestedFocusedFrame, movedEdge: movedEdge, axis: axis, tolerance: tolerance)
            else {
                return false
            }

            let candidateEdge = edgeCoordinate(frame, movedEdge)
            switch movedEdge {
            case .right, .top:
                return candidateEdge < desiredEdge - tolerance
            case .left, .bottom:
                return candidateEdge > desiredEdge + tolerance
            }
        }

        guard let occupiedCell = matchingCandidates.min(by: { lhs, rhs in
            let lhsSize = axisSize(lhs.frame.size, axis)
            let rhsSize = axisSize(rhs.frame.size, axis)
            if abs(lhsSize - rhsSize) > tolerance {
                return lhsSize < rhsSize
            }
            return lhs.id < rhs.id
        }) else {
            return requestedFocusedFrame
        }

        return roundedFrameInsideVisibleFrame(
            sameSideFrame(baseFrame: requestedFocusedFrame,
                          movedEdge: movedEdge,
                          axis: axis,
                          edge: edgeCoordinate(occupiedCell.frame, movedEdge),
                          newFocusedFrame: requestedFocusedFrame,
                          screenFrame: screenFrame),
            visibleFrame: screenFrame
        )
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
                            minimumSize: CGSize,
                            gapSize: CGFloat = 0,
                            captureTolerance: CGFloat? = nil,
                            movedEdgeOverride: MovedEdge? = nil,
                            candidateDiscoveryFrame: CGRect? = nil,
                            actionDescription: String = "repeated cooperative resize") -> [Adjustment] {
        plan(oldFocusedFrame: oldFocusedFrame,
             newFocusedFrame: newFocusedFrame,
             screenFrame: screenFrame,
             candidates: candidates,
             axis: axis,
             tolerance: tolerance,
             minimumSize: minimumSize,
             gapSize: gapSize,
             captureTolerance: captureTolerance,
             movedEdgeOverride: movedEdgeOverride,
             candidateDiscoveryFrame: candidateDiscoveryFrame,
             actionDescription: actionDescription)?.adjustments ?? []
    }

    static func plan(oldFocusedFrame: CGRect,
                     newFocusedFrame: CGRect,
                     screenFrame: CGRect,
                     candidates: [Candidate],
                     axis: CornerCycleExpansionAxis,
                     tolerance: CGFloat,
                     minimumSize: CGSize,
                     focusedMinimumSize: CGSize? = nil,
                     gapSize: CGFloat = 0,
                     captureTolerance: CGFloat? = nil,
                     movedEdgeOverride: MovedEdge? = nil,
                     candidateDiscoveryFrame: CGRect? = nil,
                     actionDescription: String = "repeated cooperative resize") -> Plan? {
        guard !oldFocusedFrame.isNull,
              !newFocusedFrame.isNull,
              !screenFrame.isNull
        else {
            return nil
        }

        guard let movedEdge = movedEdgeOverride ?? movedEdge(from: oldFocusedFrame,
                                                             to: newFocusedFrame,
                                                             axis: axis,
                                                             tolerance: tolerance) else {
            return nil
        }

        let fallbackMinimumSize = normalizedMinimumSize(minimumSize)
        let resolvedFocusedMinimumSize = normalizedMinimumSize(focusedMinimumSize ?? fallbackMinimumSize)
        let resolvedCaptureTolerance = captureTolerance ?? tolerance
        let resolvedPerpendicularCaptureTolerance = captureTolerance == nil
            ? tolerance
            : Self.captureTolerance(screenFrame: screenFrame, axis: perpendicularAxis(to: axis))
        let discoveryFrame = candidateDiscoveryFrame ?? oldFocusedFrame
        let affectedWindowsResult = affectedWindows(discoveryFocusedFrame: discoveryFrame,
                                                    newFocusedFrame: newFocusedFrame,
                                                    screenFrame: screenFrame,
                                                    candidates: candidates,
                                                    movedEdge: movedEdge,
                                                    tolerance: tolerance,
                                                    captureTolerance: resolvedCaptureTolerance,
                                                    perpendicularCaptureTolerance: resolvedPerpendicularCaptureTolerance,
                                                    fallbackMinimumSize: fallbackMinimumSize,
                                                    gapSize: gapSize)
        let affectedWindows = affectedWindowsResult.windows
        guard !affectedWindows.isEmpty else { return nil }

        let oldEdge = edgeCoordinate(oldFocusedFrame, movedEdge)
        let desiredEdge = edgeCoordinate(newFocusedFrame, movedEdge)
        let requestedDelta = desiredEdge - oldEdge
        var debugLog = [
            "Cooperative resize action type: \(actionDescription)",
            "Cooperative resize visible frame: \(screenFrame.debugDescription)",
            "Cooperative resize configured gap: \(gapSize)",
            "Cooperative resize detection tolerance: \(tolerance)",
            "Cooperative resize aggressive capture tolerance: axis \(resolvedCaptureTolerance), perpendicular \(resolvedPerpendicularCaptureTolerance)",
            "Cooperative resize requested delta: \(requestedDelta)",
            "Cooperative resize affected windows: \(affectedWindows.map { "\($0.candidate.id) (\($0.inclusionReason))" }.joined(separator: ", "))"
        ] + affectedWindowsResult.debugLog

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
                                    screenFrame: screenFrame,
                                    gapSize: gapSize)
        }

        let clampedEdge = roundedEdge(clamp(desiredEdge, min: edgeRange.min, max: edgeRange.max),
                                      legalMin: edgeRange.min,
                                      legalMax: edgeRange.max)
        let focusedFrame = roundedFrameInsideVisibleFrame(
            frameWithMinimumSize(sameSideFrame(baseFrame: newFocusedFrame,
                                               movedEdge: movedEdge,
                                               axis: axis,
                                               edge: clampedEdge,
                                               newFocusedFrame: newFocusedFrame,
                                               screenFrame: screenFrame),
                                 minimumSize: resolvedFocusedMinimumSize,
                                 resizeAxis: axis,
                                 visibleFrame: screenFrame),
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
                                                               screenFrame: screenFrame,
                                                               gapSize: gapSize)
            let clampedFrame = clampedFrameForAffectedWindow(affectedWindow,
                                                             clampedEdge: clampedEdge,
                                                             movedEdge: movedEdge,
                                                             axis: axis,
                                                             newFocusedFrame: newFocusedFrame,
                                                             screenFrame: screenFrame,
                                                             gapSize: gapSize)
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
        if edgeRange.min > edgeRange.max {
            debugLog.append("Cooperative resize layout over-constrained: legal shared-edge range \(edgeRange.min)...\(edgeRange.max)")
        }

        return Plan(focusedFrame: focusedFrame,
                    adjustments: adjustments,
                    debugLog: debugLog)
    }

    static func correctionPlan(oldFocusedFrame: CGRect,
                               requestedFocusedFrame: CGRect,
                               plannedPlan: Plan,
                               screenFrame: CGRect,
                               candidates: [Candidate],
                               actualFocusedFrame: CGRect,
                               actualCandidateFramesById: [CGWindowID: CGRect],
                               axis: CornerCycleExpansionAxis,
                               tolerance: CGFloat,
                               layoutTolerance: CGFloat,
                               minimumSize: CGSize,
                               focusedMinimumSize: CGSize? = nil,
                               gapSize: CGFloat = 0,
                               captureTolerance: CGFloat? = nil,
                               movedEdgeOverride: MovedEdge? = nil,
                               candidateDiscoveryFrame: CGRect? = nil,
                               actionDescription: String = "cooperative resize settling pass") -> Plan? {
        let plannedAdjustmentsById = Dictionary(uniqueKeysWithValues: plannedPlan.adjustments.map { ($0.id, $0) })
        let focusedNeedsCorrection = frameNeedsCorrection(plannedFrame: plannedPlan.focusedFrame,
                                                          actualFrame: actualFocusedFrame,
                                                          screenFrame: screenFrame,
                                                          tolerance: layoutTolerance)
        let cooperatingNeedsCorrection = plannedPlan.adjustments.contains { adjustment in
            guard let actualFrame = actualCandidateFramesById[adjustment.id] else { return false }
            return frameNeedsCorrection(plannedFrame: adjustment.newFrame,
                                        actualFrame: actualFrame,
                                        screenFrame: screenFrame,
                                        tolerance: layoutTolerance)
        }

        guard focusedNeedsCorrection || cooperatingNeedsCorrection else {
            return nil
        }

        let fallbackMinimumSize = normalizedMinimumSize(minimumSize)
        let effectiveFocusedMinimumSize = effectiveMinimumSize(base: focusedMinimumSize ?? fallbackMinimumSize,
                                                               plannedFrame: plannedPlan.focusedFrame,
                                                               actualFrame: actualFocusedFrame,
                                                               layoutTolerance: layoutTolerance)
        let effectiveCandidates = candidates.map { candidate -> Candidate in
            guard let plannedAdjustment = plannedAdjustmentsById[candidate.id],
                  let actualFrame = actualCandidateFramesById[candidate.id]
            else {
                return candidate
            }

            let baseMinimumSize = candidate.minimumSize ?? fallbackMinimumSize
            let effectiveMinimum = effectiveMinimumSize(base: baseMinimumSize,
                                                        plannedFrame: plannedAdjustment.newFrame,
                                                        actualFrame: actualFrame,
                                                        layoutTolerance: layoutTolerance)
            return Candidate(id: candidate.id, frame: candidate.frame, minimumSize: effectiveMinimum)
        }

        guard let correctedPlan = plan(oldFocusedFrame: oldFocusedFrame,
                                       newFocusedFrame: requestedFocusedFrame,
                                       screenFrame: screenFrame,
                                       candidates: effectiveCandidates,
                                       axis: axis,
                                       tolerance: tolerance,
                                       minimumSize: minimumSize,
                                       focusedMinimumSize: effectiveFocusedMinimumSize,
                                       gapSize: gapSize,
                                       captureTolerance: captureTolerance,
                                       movedEdgeOverride: movedEdgeOverride,
                                       candidateDiscoveryFrame: candidateDiscoveryFrame,
                                       actionDescription: actionDescription)
        else {
            return nil
        }

        return Plan(focusedFrame: correctedPlan.focusedFrame,
                    adjustments: correctedPlan.adjustments,
                    debugLog: ["Cooperative resize settling pass: actual frames rejected planned layout"] + correctedPlan.debugLog)
    }

    static func focusedWindowIsExpanding(oldFrame: CGRect, newFrame: CGRect, axis: CornerCycleExpansionAxis) -> Bool {
        switch axis {
        case .horizontal:
            return newFrame.width > oldFrame.width
        case .vertical:
            return newFrame.height > oldFrame.height
        }
    }

    private static func affectedWindows(discoveryFocusedFrame: CGRect,
                                        newFocusedFrame: CGRect,
                                        screenFrame: CGRect,
                                        candidates: [Candidate],
                                        movedEdge: MovedEdge,
                                        tolerance: CGFloat,
                                        captureTolerance: CGFloat,
                                        perpendicularCaptureTolerance: CGFloat,
                                        fallbackMinimumSize: CGSize,
                                        gapSize: CGFloat) -> AffectedWindowsResult {
        var matchingFocusedFrameAdjustments: [AffectedWindow] = []
        var matchingMovingSpanAdjustments: [AffectedWindow] = []
        var adjacentAdjustments: [AffectedWindow] = []
        var debugLog: [String] = []

        for candidate in candidates {
            guard !candidate.frame.isNull else {
                debugLog.append("Cooperative resize candidate \(candidate.id) excluded: null frame")
                continue
            }
            guard screenFrame.intersects(candidate.frame) else {
                debugLog.append("Cooperative resize candidate \(candidate.id) excluded: outside visible frame")
                continue
            }

            let minimumSize = normalizedMinimumSize(candidate.minimumSize ?? fallbackMinimumSize)
            let strictLayoutFrame = normalizedFullSpanFrame(candidate.frame,
                                                           focusedFrame: discoveryFocusedFrame,
                                                           movedEdge: movedEdge,
                                                           tolerance: tolerance)

            if approximatelyMatchesFrame(candidate.frame, discoveryFocusedFrame, tolerance: tolerance) {
                matchingFocusedFrameAdjustments.append(AffectedWindow(candidate: candidate,
                                                                      layoutFrame: strictLayoutFrame,
                                                                      role: .matchingFocusedFrame,
                                                                      kind: .matchingFocusedFrame,
                                                                      minimumSize: minimumSize,
                                                                      inclusionReason: "matches focused frame"))
                debugLog.append("Cooperative resize candidate \(candidate.id) included: matches focused frame")
                continue
            }

            if matchesMovingSpan(candidate.frame, discoveryFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
               isSupportedPerpendicularSpan(candidate.frame, discoveryFocusedFrame, movedEdge: movedEdge, tolerance: tolerance) {
                matchingMovingSpanAdjustments.append(AffectedWindow(candidate: candidate,
                                                                   layoutFrame: strictLayoutFrame,
                                                                   role: .matchingMovingSpan,
                                                                   kind: .matchingFocusedFrame,
                                                                   minimumSize: minimumSize,
                                                                   inclusionReason: "matches moving span"))
                debugLog.append("Cooperative resize candidate \(candidate.id) included: matches moving span")
                continue
            }

            if isSupportedPerpendicularSpan(candidate.frame, discoveryFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
               touchesOldMovingEdge(candidate.frame, discoveryFocusedFrame, movedEdge: movedEdge, tolerance: tolerance, gapSize: gapSize) {
                adjacentAdjustments.append(AffectedWindow(candidate: candidate,
                                                         layoutFrame: strictLayoutFrame,
                                                         role: .adjacent,
                                                         kind: .adjacent,
                                                         minimumSize: minimumSize,
                                                         inclusionReason: "touches shared edge"))
                debugLog.append("Cooperative resize candidate \(candidate.id) included: touches shared edge")
                continue
            }

            guard let captured = capturedWindow(candidate: candidate,
                                                discoveryFocusedFrame: discoveryFocusedFrame,
                                                newFocusedFrame: newFocusedFrame,
                                                screenFrame: screenFrame,
                                                movedEdge: movedEdge,
                                                captureTolerance: captureTolerance,
                                                perpendicularCaptureTolerance: perpendicularCaptureTolerance,
                                                gapSize: gapSize,
                                                minimumSize: minimumSize)
            else {
                debugLog.append("Cooperative resize candidate \(candidate.id) excluded: no shared edge, boundary crossing, or capture-tolerance match")
                continue
            }

            switch captured.role {
            case .matchingFocusedFrame:
                matchingFocusedFrameAdjustments.append(captured)
            case .matchingMovingSpan:
                matchingMovingSpanAdjustments.append(captured)
            case .adjacent:
                adjacentAdjustments.append(captured)
            }
            debugLog.append("Cooperative resize candidate \(candidate.id) included: \(captured.inclusionReason)")
        }

        return AffectedWindowsResult(windows: matchingFocusedFrameAdjustments + matchingMovingSpanAdjustments + adjacentAdjustments,
                                     debugLog: debugLog)
    }

    private static func capturedWindow(candidate: Candidate,
                                       discoveryFocusedFrame: CGRect,
                                       newFocusedFrame: CGRect,
                                       screenFrame: CGRect,
                                       movedEdge: MovedEdge,
                                       captureTolerance: CGFloat,
                                       perpendicularCaptureTolerance: CGFloat,
                                       gapSize: CGFloat,
                                       minimumSize: CGSize) -> AffectedWindow? {
        let perpendicularSupported = isSupportedPerpendicularSpan(candidate.frame,
                                                                  discoveryFocusedFrame,
                                                                  movedEdge: movedEdge,
                                                                  tolerance: perpendicularCaptureTolerance)
        let perpendicularOverlaps = perpendicularOverlap(candidate.frame,
                                                        discoveryFocusedFrame,
                                                        movedEdge: movedEdge) > 0

        let touchesDiscoveryEdge = touchesOldMovingEdge(candidate.frame,
                                                        discoveryFocusedFrame,
                                                        movedEdge: movedEdge,
                                                        tolerance: captureTolerance,
                                                        gapSize: gapSize)
        let touchesTargetEdge = touchesOldMovingEdge(candidate.frame,
                                                     newFocusedFrame,
                                                     movedEdge: movedEdge,
                                                     tolerance: captureTolerance,
                                                     gapSize: gapSize)
        let crossesDiscoveryBoundary = crossesSharedBoundary(candidate.frame,
                                                             boundary: edgeCoordinate(discoveryFocusedFrame, movedEdge),
                                                             movedEdge: movedEdge,
                                                             gapSize: gapSize)
        let crossesTargetBoundary = crossesSharedBoundary(candidate.frame,
                                                          boundary: edgeCoordinate(newFocusedFrame, movedEdge),
                                                          movedEdge: movedEdge,
                                                          gapSize: gapSize)
        let overlapsTargetBoundary = overlapsBoundaryBand(candidate.frame,
                                                          boundary: edgeCoordinate(newFocusedFrame, movedEdge),
                                                          axis: axis(for: movedEdge),
                                                          tolerance: captureTolerance)

        let edgeCapture = perpendicularSupported && (touchesDiscoveryEdge
            || touchesTargetEdge
            || (newFocusedFrame.intersects(candidate.frame) && overlapsTargetBoundary))
        let boundaryCapture = perpendicularOverlaps && (crossesDiscoveryBoundary || crossesTargetBoundary)

        guard edgeCapture || boundaryCapture
        else {
            return nil
        }

        let assignment = nearestRole(candidate.frame,
                                     focusedFrame: newFocusedFrame,
                                     screenFrame: screenFrame,
                                     movedEdge: movedEdge,
                                     gapSize: gapSize)
        let layoutFrame = normalizedCapturedFrame(candidate.frame,
                                                  focusedFrame: discoveryFocusedFrame,
                                                  screenFrame: screenFrame,
                                                  movedEdge: movedEdge,
                                                  role: assignment,
                                                  tolerance: perpendicularCaptureTolerance,
                                                  gapSize: gapSize)
        let reasonParts = [
            touchesDiscoveryEdge ? "capture-tolerance shared edge" : nil,
            touchesTargetEdge ? "capture-tolerance target edge" : nil,
            crossesDiscoveryBoundary || crossesTargetBoundary ? "boundary crossing" : nil,
            overlapsTargetBoundary ? "target-boundary overlap" : nil,
            "nearest-region \(assignment)"
        ].compactMap { $0 }
        let kind: Adjustment.Kind = assignment == .adjacent ? .adjacent : .matchingFocusedFrame

        return AffectedWindow(candidate: candidate,
                              layoutFrame: layoutFrame,
                              role: assignment,
                              kind: kind,
                              minimumSize: minimumSize,
                              inclusionReason: reasonParts.joined(separator: ", "))
    }

    private static func nearestRole(_ candidate: CGRect,
                                    focusedFrame: CGRect,
                                    screenFrame: CGRect,
                                    movedEdge: MovedEdge,
                                    gapSize: CGFloat) -> AffectedRole {
        let axis = axis(for: movedEdge)
        let boundary = edgeCoordinate(focusedFrame, movedEdge)
        let sameInterval: (min: CGFloat, max: CGFloat)
        let adjacentInterval: (min: CGFloat, max: CGFloat)

        switch movedEdge {
        case .right, .top:
            sameInterval = (axisMin(focusedFrame, axis), boundary)
            adjacentInterval = (boundary + gapSize, axisMax(screenFrame, axis))
        case .left, .bottom:
            sameInterval = (boundary, axisMax(focusedFrame, axis))
            adjacentInterval = (axisMin(screenFrame, axis), boundary - gapSize)
        }

        let candidateInterval = (axisMin(candidate, axis), axisMax(candidate, axis))
        let sameOverlap = intervalOverlap(candidateInterval, sameInterval)
        let adjacentOverlap = intervalOverlap(candidateInterval, adjacentInterval)

        if abs(adjacentOverlap - sameOverlap) > 0.001 {
            return adjacentOverlap > sameOverlap ? .adjacent : .matchingMovingSpan
        }

        let center = (candidateInterval.0 + candidateInterval.1) / 2.0
        switch movedEdge {
        case .right, .top:
            return center >= boundary ? .adjacent : .matchingMovingSpan
        case .left, .bottom:
            return center <= boundary ? .adjacent : .matchingMovingSpan
        }
    }

    private static func crossesSharedBoundary(_ candidate: CGRect,
                                              boundary: CGFloat,
                                              movedEdge: MovedEdge,
                                              gapSize: CGFloat) -> Bool {
        let axis = axis(for: movedEdge)
        let candidateMin = axisMin(candidate, axis)
        let candidateMax = axisMax(candidate, axis)

        switch movedEdge {
        case .right, .top:
            return candidateMin < boundary + gapSize && candidateMax > boundary
        case .left, .bottom:
            return candidateMin < boundary && candidateMax > boundary - gapSize
        }
    }

    private static func overlapsBoundaryBand(_ candidate: CGRect,
                                             boundary: CGFloat,
                                             axis: CornerCycleExpansionAxis,
                                             tolerance: CGFloat) -> Bool {
        axisMin(candidate, axis) <= boundary + tolerance
            && axisMax(candidate, axis) >= boundary - tolerance
    }

    private static func perpendicularOverlap(_ candidate: CGRect,
                                             _ focused: CGRect,
                                             movedEdge: MovedEdge) -> CGFloat {
        switch movedEdge {
        case .left, .right:
            return intervalOverlap((candidate.minY, candidate.maxY), (focused.minY, focused.maxY))
        case .top, .bottom:
            return intervalOverlap((candidate.minX, candidate.maxX), (focused.minX, focused.maxX))
        }
    }

    private static func intervalOverlap(_ lhs: (CGFloat, CGFloat), _ rhs: (CGFloat, CGFloat)) -> CGFloat {
        max(0, min(lhs.1, rhs.1) - max(lhs.0, rhs.0))
    }

    private static func normalizedCapturedFrame(_ candidate: CGRect,
                                                focusedFrame: CGRect,
                                                screenFrame: CGRect,
                                                movedEdge: MovedEdge,
                                                role: AffectedRole,
                                                tolerance: CGFloat,
                                                gapSize: CGFloat) -> CGRect {
        var result = normalizedFullSpanFrame(candidate,
                                             focusedFrame: focusedFrame,
                                             movedEdge: movedEdge,
                                             tolerance: tolerance)
        guard role == .adjacent else {
            return result
        }

        switch movedEdge {
        case .right:
            result.size.width = outerMax(for: candidate.maxX,
                                         screenMin: screenFrame.minX,
                                         screenMax: screenFrame.maxX,
                                         gapSize: gapSize) - result.minX
        case .left:
            let oldMaxX = result.maxX
            result.origin.x = outerMin(for: candidate.minX,
                                       screenMin: screenFrame.minX,
                                       screenMax: screenFrame.maxX,
                                       gapSize: gapSize)
            result.size.width = oldMaxX - result.minX
        case .top:
            result.size.height = outerMax(for: candidate.maxY,
                                          screenMin: screenFrame.minY,
                                          screenMax: screenFrame.maxY,
                                          gapSize: gapSize) - result.minY
        case .bottom:
            let oldMaxY = result.maxY
            result.origin.y = outerMin(for: candidate.minY,
                                       screenMin: screenFrame.minY,
                                       screenMax: screenFrame.maxY,
                                       gapSize: gapSize)
            result.size.height = oldMaxY - result.minY
        }
        return result
    }

    private static func outerMin(for candidateMin: CGFloat,
                                 screenMin: CGFloat,
                                 screenMax: CGFloat,
                                 gapSize: CGFloat) -> CGFloat {
        let resolvedGapSize = max(0, min(gapSize, (screenMax - screenMin) / 2.0))
        guard resolvedGapSize > 0 else { return screenMin }

        let gapMin = screenMin + resolvedGapSize
        return abs(candidateMin - screenMin) < abs(candidateMin - gapMin)
            ? screenMin
            : gapMin
    }

    private static func outerMax(for candidateMax: CGFloat,
                                 screenMin: CGFloat,
                                 screenMax: CGFloat,
                                 gapSize: CGFloat) -> CGFloat {
        let resolvedGapSize = max(0, min(gapSize, (screenMax - screenMin) / 2.0))
        guard resolvedGapSize > 0 else { return screenMax }

        let gapMax = screenMax - resolvedGapSize
        return abs(candidateMax - screenMax) < abs(candidateMax - gapMax)
            ? screenMax
            : gapMax
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
                                                screenFrame: CGRect,
                                                gapSize: CGFloat) {
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
                                    candidateFrame: affectedWindow.layoutFrame,
                                    screenFrame: screenFrame,
                                    minimumSize: affectedWindow.minimumSize,
                                    gapSize: gapSize)
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
                                                minimumSize: CGSize,
                                                gapSize: CGFloat) {
        let minimumAxisSize = axisSize(minimumSize, axis)
        switch movedEdge {
        case .right, .top:
            let outerMax = min(axisMax(candidateFrame, axis), axisMax(screenFrame, axis))
            edgeRange.requireMax(outerMax - gapSize - minimumAxisSize, reason: "\(label) minimum \(axisSizeName(axis)) inside visible frame with gap")
        case .left, .bottom:
            let outerMin = max(axisMin(candidateFrame, axis), axisMin(screenFrame, axis))
            edgeRange.requireMin(outerMin + gapSize + minimumAxisSize, reason: "\(label) minimum \(axisSizeName(axis)) inside visible frame with gap")
        }
    }

    private static func proposedFrameForAffectedWindow(_ affectedWindow: AffectedWindow,
                                                       desiredEdge: CGFloat,
                                                       movedEdge: MovedEdge,
                                                       axis: CornerCycleExpansionAxis,
                                                       newFocusedFrame: CGRect,
                                                       screenFrame: CGRect,
                                                       gapSize: CGFloat) -> CGRect {
        frameForAffectedWindow(affectedWindow,
                               edge: desiredEdge,
                               movedEdge: movedEdge,
                               axis: axis,
                               newFocusedFrame: newFocusedFrame,
                               screenFrame: screenFrame,
                               gapSize: gapSize)
    }

    private static func clampedFrameForAffectedWindow(_ affectedWindow: AffectedWindow,
                                                      clampedEdge: CGFloat,
                                                      movedEdge: MovedEdge,
                                                      axis: CornerCycleExpansionAxis,
                                                      newFocusedFrame: CGRect,
                                                      screenFrame: CGRect,
                                                      gapSize: CGFloat) -> CGRect {
        roundedFrameInsideVisibleFrame(
            frameForAffectedWindow(affectedWindow,
                                   edge: clampedEdge,
                                   movedEdge: movedEdge,
                                   axis: axis,
                                   newFocusedFrame: newFocusedFrame,
                                   screenFrame: screenFrame,
                                   gapSize: gapSize),
            visibleFrame: screenFrame
        )
    }

    private static func frameForAffectedWindow(_ affectedWindow: AffectedWindow,
                                               edge: CGFloat,
                                               movedEdge: MovedEdge,
                                               axis: CornerCycleExpansionAxis,
                                               newFocusedFrame: CGRect,
                                               screenFrame: CGRect,
                                               gapSize: CGFloat) -> CGRect {
        switch affectedWindow.role {
        case .matchingFocusedFrame:
            return frameWithMinimumSize(sameSideFrame(baseFrame: newFocusedFrame,
                                                      movedEdge: movedEdge,
                                                      axis: axis,
                                                      edge: edge,
                                                      newFocusedFrame: newFocusedFrame,
                                                      screenFrame: screenFrame),
                                        minimumSize: affectedWindow.minimumSize,
                                        resizeAxis: axis,
                                        visibleFrame: screenFrame)
        case .matchingMovingSpan:
            return frameWithMinimumSize(sameSideFrame(baseFrame: affectedWindow.layoutFrame,
                                                      movedEdge: movedEdge,
                                                      axis: axis,
                                                      edge: edge,
                                                      newFocusedFrame: newFocusedFrame,
                                                      screenFrame: screenFrame),
                                        minimumSize: affectedWindow.minimumSize,
                                        resizeAxis: axis,
                                        visibleFrame: screenFrame)
        case .adjacent:
            return frameWithMinimumSize(adjacentFrame(baseFrame: affectedWindow.layoutFrame,
                                                      movedEdge: movedEdge,
                                                      axis: axis,
                                                      edge: edge,
                                                      screenFrame: screenFrame,
                                                      gapSize: gapSize),
                                        minimumSize: affectedWindow.minimumSize,
                                        resizeAxis: axis,
                                        visibleFrame: screenFrame)
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
                                      screenFrame: CGRect,
                                      gapSize: CGFloat) -> CGRect {
        switch movedEdge {
        case .right, .top:
            let outerMax = min(axisMax(baseFrame, axis), axisMax(screenFrame, axis))
            return frame(baseFrame, axis: axis, min: edge + gapSize, max: outerMax, visibleFrame: screenFrame)
        case .left, .bottom:
            let outerMin = max(axisMin(baseFrame, axis), axisMin(screenFrame, axis))
            return frame(baseFrame, axis: axis, min: outerMin, max: edge - gapSize, visibleFrame: screenFrame)
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

    private static func frameWithMinimumSize(_ frame: CGRect,
                                             minimumSize: CGSize,
                                             resizeAxis: CornerCycleExpansionAxis,
                                             visibleFrame: CGRect) -> CGRect {
        var rect = frame
        switch resizeAxis {
        case .horizontal:
            if rect.height < minimumSize.height {
                rect.size.height = min(minimumSize.height, visibleFrame.height)
                if rect.maxY > visibleFrame.maxY {
                    rect.origin.y = visibleFrame.maxY - rect.height
                }
                if rect.minY < visibleFrame.minY {
                    rect.origin.y = visibleFrame.minY
                }
            }
        case .vertical:
            if rect.width < minimumSize.width {
                rect.size.width = min(minimumSize.width, visibleFrame.width)
                if rect.maxX > visibleFrame.maxX {
                    rect.origin.x = visibleFrame.maxX - rect.width
                }
                if rect.minX < visibleFrame.minX {
                    rect.origin.x = visibleFrame.minX
                }
            }
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

    private static func frameNeedsCorrection(plannedFrame: CGRect,
                                             actualFrame: CGRect,
                                             screenFrame: CGRect,
                                             tolerance: CGFloat) -> Bool {
        guard !actualFrame.isNull else { return false }
        if !screenFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(actualFrame) {
            return true
        }
        return abs(plannedFrame.minX - actualFrame.minX) > tolerance
            || abs(plannedFrame.minY - actualFrame.minY) > tolerance
            || abs(plannedFrame.width - actualFrame.width) > tolerance
            || abs(plannedFrame.height - actualFrame.height) > tolerance
    }

    private static func effectiveMinimumSize(base: CGSize,
                                             plannedFrame: CGRect,
                                             actualFrame: CGRect,
                                             layoutTolerance: CGFloat) -> CGSize {
        let normalizedBase = normalizedMinimumSize(base)
        guard !actualFrame.isNull else { return normalizedBase }

        let effectiveWidth = actualFrame.width > plannedFrame.width + layoutTolerance
            ? max(normalizedBase.width, actualFrame.width)
            : normalizedBase.width
        let effectiveHeight = actualFrame.height > plannedFrame.height + layoutTolerance
            ? max(normalizedBase.height, actualFrame.height)
            : normalizedBase.height
        return CGSize(width: effectiveWidth, height: effectiveHeight)
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

    private static func axis(for movedEdge: MovedEdge) -> CornerCycleExpansionAxis {
        switch movedEdge {
        case .left, .right:
            return .horizontal
        case .top, .bottom:
            return .vertical
        }
    }

    private static func perpendicularAxis(to axis: CornerCycleExpansionAxis) -> CornerCycleExpansionAxis {
        axis == .horizontal ? .vertical : .horizontal
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

    private static func normalizedFullSpanFrame(_ candidate: CGRect,
                                                focusedFrame: CGRect,
                                                movedEdge: MovedEdge,
                                                tolerance: CGFloat) -> CGRect {
        var result = candidate
        switch movedEdge {
        case .left, .right:
            if abs(candidate.minY - focusedFrame.minY) <= tolerance,
               abs(candidate.maxY - focusedFrame.maxY) <= tolerance {
                result.origin.y = focusedFrame.minY
                result.size.height = focusedFrame.height
            }
        case .top, .bottom:
            if abs(candidate.minX - focusedFrame.minX) <= tolerance,
               abs(candidate.maxX - focusedFrame.maxX) <= tolerance {
                result.origin.x = focusedFrame.minX
                result.size.width = focusedFrame.width
            }
        }
        return result
    }

    private static func touchesOldMovingEdge(_ candidate: CGRect,
                                             _ focused: CGRect,
                                             movedEdge: MovedEdge,
                                             tolerance: CGFloat,
                                             gapSize: CGFloat) -> Bool {
        switch movedEdge {
        case .left:
            return abs((focused.minX - candidate.maxX) - gapSize) <= tolerance
        case .right:
            return abs((candidate.minX - focused.maxX) - gapSize) <= tolerance
        case .bottom:
            return abs((focused.minY - candidate.maxY) - gapSize) <= tolerance
        case .top:
            return abs((candidate.minY - focused.maxY) - gapSize) <= tolerance
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

    private static func matchesPerpendicularSpan(_ candidate: CGRect,
                                                 _ focused: CGRect,
                                                 movedEdge: MovedEdge,
                                                 tolerance: CGFloat) -> Bool {
        switch movedEdge {
        case .left, .right:
            return abs(candidate.minY - focused.minY) <= tolerance
                && abs(candidate.maxY - focused.maxY) <= tolerance
        case .top, .bottom:
            return abs(candidate.minX - focused.minX) <= tolerance
                && abs(candidate.maxX - focused.maxX) <= tolerance
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

    private static func isContainedInSameSideRegion(_ candidate: CGRect,
                                                    _ focused: CGRect,
                                                    movedEdge: MovedEdge,
                                                    axis: CornerCycleExpansionAxis,
                                                    tolerance: CGFloat) -> Bool {
        let candidateMin = axisMin(candidate, axis)
        let candidateMax = axisMax(candidate, axis)
        let focusedMin = axisMin(focused, axis)
        let focusedMax = axisMax(focused, axis)
        let candidateIsWithinFocused = candidateMin >= focusedMin - tolerance
            && candidateMax <= focusedMax + tolerance

        guard candidateIsWithinFocused else {
            return false
        }

        switch movedEdge {
        case .right, .top:
            return abs(candidateMin - focusedMin) <= tolerance
        case .left, .bottom:
            return abs(candidateMax - focusedMax) <= tolerance
        }
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
