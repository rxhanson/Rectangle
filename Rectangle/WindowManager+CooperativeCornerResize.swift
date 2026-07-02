/// WindowManager+CooperativeCornerResize.swift

import Cocoa

extension WindowManager {

    func applyCooperativeCornerResize(result: ResultParameters,
                                      plan: CooperativeCornerApplicationPlan) -> CGRect {
        var activePlan = plan
        let focusedWindowIsExpanding = CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: result.windowElement.frame.screenFlipped,
                                                                                        newFrame: activePlan.focusedFrame,
                                                                                        axis: activePlan.axis)

        if focusedWindowIsExpanding {
            apply(activePlan.adjustments,
                  kind: .adjacent,
                  screenFrame: activePlan.screenFrame,
                  layoutTolerance: activePlan.layoutTolerance)
            apply(activePlan.adjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: activePlan.screenFrame,
                  layoutTolerance: activePlan.layoutTolerance)

            if let correctedPlan = correctionPlanAfterApplyingCooperatingWindows(activePlan) {
                activePlan = correctedPlan
                apply(activePlan.adjustments,
                      kind: .adjacent,
                      screenFrame: activePlan.screenFrame,
                      layoutTolerance: activePlan.layoutTolerance)
                apply(activePlan.adjustments,
                      kind: .matchingFocusedFrame,
                      screenFrame: activePlan.screenFrame,
                      layoutTolerance: activePlan.layoutTolerance)
            }

            var resultingRect = applyFocusedCooperativeFrameIfNeeded(activePlan.focusedFrame,
                                                                     result: result,
                                                                     layoutTolerance: activePlan.layoutTolerance)
            if let settledRect = settleCooperativeCornerResizeIfNeeded(plan: activePlan,
                                                                       focusedWindowElement: result.windowElement,
                                                                       result: result) {
                resultingRect = settledRect
            }
            return resultingRect
        }

        var resultingRect = applyFocusedCooperativeFrameIfNeeded(activePlan.focusedFrame,
                                                                 result: result,
                                                                 layoutTolerance: activePlan.layoutTolerance)
        apply(activePlan.adjustments,
              kind: .matchingFocusedFrame,
              screenFrame: activePlan.screenFrame,
              layoutTolerance: activePlan.layoutTolerance)
        apply(activePlan.adjustments,
              kind: .adjacent,
              screenFrame: activePlan.screenFrame,
              layoutTolerance: activePlan.layoutTolerance)

        if let settledRect = settleCooperativeCornerResizeIfNeeded(plan: activePlan,
                                                                   focusedWindowElement: result.windowElement,
                                                                   result: result) {
            resultingRect = settledRect
        }
        return resultingRect
    }

    func cooperativeCornerResizePlan(focusedWindowId: CGWindowID,
                                     focusedWindowIsFixedSize: Bool,
                                     focusedWindowMinimumSize: CGSize?,
                                     action: WindowAction,
                                     source: ExecutionSource,
                                     oldFocusedFrame: CGRect,
                                     newFocusedFrame: CGRect,
                                     screenFrame: CGRect,
                                     destinationScreenIsCurrentScreen: Bool,
                                     lastRectangleAction: RectangleAction?) -> CooperativeCornerApplicationPlan? {
        guard Defaults.cooperativeCornerResize.enabled,
              source.allowsCooperativeResize,
              !focusedWindowIsFixedSize,
              destinationScreenIsCurrentScreen,
              let cooperativeAxis = action.cooperativeResizeAxis,
              let movedEdge = action.cooperativeResizeMovedEdge
        else {
            return nil
        }

        let gapSize = max(0, CGFloat(Defaults.gapSize.value))
        let tolerance = CooperativeCornerResize.detectionTolerance(screenFrame: screenFrame, configuredGap: gapSize)
        let captureTolerance = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: cooperativeAxis)
        let isRepeatedCooperativeAction = action.isCompatibleRepeatedResizeAction(with: lastRectangleAction?.action)
        let actionDescription = isRepeatedCooperativeAction ? "repeated cooperative resize" : "initial corner/side cooperative placement"
        let screenFrameAX = screenFrame.screenFlipped
        let elementsById = AccessibilityElement.getAllWindowElements().reduce(into: [CGWindowID: AccessibilityElement]()) { elements, element in
            guard let candidateId = element.getWindowId(),
                  candidateId != focusedWindowId,
                  element.isWindow == true,
                  element.isMinimized != true,
                  element.isFullScreen != true,
                  element.isHidden != true,
                  element.isSheet != true,
                  element.isResizable()
            else {
                return
            }

            let frame = element.frame
            guard !frame.isNull, screenFrameAX.intersects(frame) else {
                return
            }

            elements[candidateId] = element
        }

        let candidates = elementsById.map { id, element in
            CooperativeCornerResize.Candidate(id: id,
                                              frame: element.frame.screenFlipped,
                                              minimumSize: element.minimumSize)
        }
        let minimumSize = CGSize(width: max(1, CGFloat(Defaults.minimumWindowWidth.value)),
                                 height: max(1, CGFloat(Defaults.minimumWindowHeight.value)))
        let requestedFocusedFrame = (!isRepeatedCooperativeAction && action.isCooperativeCornerAction)
            ? CooperativeCornerResize.focusedFrameResolvingRealizedCornerBoundary(requestedFocusedFrame: newFocusedFrame,
                                                                                  screenFrame: screenFrame,
                                                                                  candidates: candidates,
                                                                                  axis: cooperativeAxis,
                                                                                  movedEdge: movedEdge,
                                                                                  tolerance: tolerance,
                                                                                  gapSize: gapSize)
            : newFocusedFrame
        let candidateDiscoveryFrame = isRepeatedCooperativeAction ? oldFocusedFrame : requestedFocusedFrame
        guard let plan = CooperativeCornerResize.plan(oldFocusedFrame: oldFocusedFrame,
                                                      newFocusedFrame: requestedFocusedFrame,
                                                      screenFrame: screenFrame,
                                                      candidates: candidates,
                                                      axis: cooperativeAxis,
                                                      tolerance: tolerance,
                                                      minimumSize: minimumSize,
                                                      focusedMinimumSize: focusedWindowMinimumSize,
                                                      gapSize: gapSize,
                                                      captureTolerance: captureTolerance,
                                                      movedEdgeOverride: movedEdge,
                                                      candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                      actionDescription: actionDescription)
        else {
            return nil
        }

        plan.debugLog.forEach(Logger.log)

        let adjustments: [CooperativeCornerWindowAdjustment] = plan.adjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element,
                                                    id: adjustment.id,
                                                    newFrame: adjustment.newFrame,
                                                    kind: adjustment.kind)
        }
        guard !adjustments.isEmpty else { return nil }

        return CooperativeCornerApplicationPlan(oldFocusedFrame: oldFocusedFrame,
                                                requestedFocusedFrame: requestedFocusedFrame,
                                                focusedFrame: plan.focusedFrame,
                                                screenFrame: screenFrame,
                                                candidates: candidates,
                                                axis: cooperativeAxis,
                                                detectionTolerance: tolerance,
                                                captureTolerance: captureTolerance,
                                                layoutTolerance: 4,
                                                minimumSize: minimumSize,
                                                focusedMinimumSize: focusedWindowMinimumSize,
                                                gapSize: gapSize,
                                                movedEdge: movedEdge,
                                                candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                actionDescription: actionDescription,
                                                adjustments: adjustments,
                                                debugLog: plan.debugLog)
    }

    func applyCooperativeCornerCleanupIfNeeded(focusedWindowId: CGWindowID,
                                               source: ExecutionSource,
                                               oldFocusedFrame: CGRect,
                                               newFocusedFrame: CGRect,
                                               screenFrame: CGRect,
                                               currentAction: WindowAction,
                                               lastRectangleAction: RectangleAction?) {
        guard Defaults.cooperativeCornerResize.enabled,
              source.allowsCooperativeResize,
              let previousAction = lastRectangleAction?.action,
              previousAction.isCooperativeCornerAction,
              currentAction != previousAction,
              let cooperativeAxis = previousAction.cooperativeResizeAxis,
              let movedEdge = previousAction.cooperativeResizeMovedEdge,
              !oldFocusedFrame.isNull,
              !newFocusedFrame.isNull,
              !screenFrame.isNull,
              screenFrame.intersects(oldFocusedFrame)
        else {
            return
        }

        let gapSize = max(0, CGFloat(Defaults.gapSize.value))
        let tolerance = CooperativeCornerResize.detectionTolerance(screenFrame: screenFrame, configuredGap: gapSize)
        let captureTolerance = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: cooperativeAxis)
        let layoutTolerance: CGFloat = 4
        let screenFrameAX = screenFrame.screenFlipped
        let allElementsById = AccessibilityElement.getAllWindowElements().reduce(into: [CGWindowID: AccessibilityElement]()) { elements, element in
            guard let candidateId = element.getWindowId(),
                  element.isWindow == true,
                  element.isMinimized != true,
                  element.isFullScreen != true,
                  element.isHidden != true,
                  element.isSheet != true,
                  element.isResizable()
            else {
                return
            }

            let frame = element.frame
            guard !frame.isNull, screenFrameAX.intersects(frame) else {
                return
            }

            elements[candidateId] = element
        }
        var elementsById = allElementsById.filter { $0.key != focusedWindowId }

        let candidates = elementsById.map { id, element in
            CooperativeCornerResize.Candidate(id: id,
                                              frame: element.frame.screenFlipped,
                                              minimumSize: element.minimumSize)
        }
        guard let observedCornerFrame = observedCornerOccupantFrame(action: previousAction,
                                                                    oldFocusedFrame: oldFocusedFrame,
                                                                    candidates: candidates,
                                                                    screenFrame: screenFrame,
                                                                    axis: cooperativeAxis,
                                                                    tolerance: tolerance,
                                                                    captureTolerance: captureTolerance,
                                                                    gapSize: gapSize),
              let targetFrame = cleanupTargetFrame(action: previousAction,
                                                   observedFrame: observedCornerFrame,
                                                   screenFrame: screenFrame,
                                                   axis: cooperativeAxis,
                                                   movedEdge: movedEdge,
                                                   tolerance: tolerance,
                                                   includeCycleTargets: (lastRectangleAction?.count ?? 0) > 1)
        else {
            return
        }

        let minimumSize = CGSize(width: max(1, CGFloat(Defaults.minimumWindowWidth.value)),
                                 height: max(1, CGFloat(Defaults.minimumWindowHeight.value)))
        let syntheticFocusedMinimumSize = CGSize(width: 1, height: 1)
        if let focusedElement = allElementsById[focusedWindowId],
           frameIsAdjacentToCleanupSource(focusedElement.frame.screenFlipped,
                                          sourceFrame: observedCornerFrame,
                                          movedEdge: movedEdge,
                                          axis: cooperativeAxis,
                                          tolerance: tolerance,
                                          gapSize: gapSize) {
            elementsById[focusedWindowId] = focusedElement
        }

        let cleanupCandidates = elementsById.map { id, element in
            CooperativeCornerResize.Candidate(id: id,
                                              frame: element.frame.screenFlipped,
                                              minimumSize: element.minimumSize)
        }
        guard let cleanupPlan = CooperativeCornerResize.plan(oldFocusedFrame: observedCornerFrame,
                                                             newFocusedFrame: targetFrame,
                                                             screenFrame: screenFrame,
                                                             candidates: cleanupCandidates,
                                                             axis: cooperativeAxis,
                                                             tolerance: tolerance,
                                                             minimumSize: minimumSize,
                                                             focusedMinimumSize: syntheticFocusedMinimumSize,
                                                             gapSize: gapSize,
                                                             captureTolerance: captureTolerance,
                                                             movedEdgeOverride: movedEdge,
                                                             candidateDiscoveryFrame: observedCornerFrame,
                                                             actionDescription: "cooperative resize cleanup after focused window left corner")
        else {
            return
        }

        cleanupPlan.debugLog.forEach(Logger.log)
        let cleanupAdjustments = applicationAdjustments(for: cleanupPlan.adjustments, elementsById: elementsById)
        guard cleanupAdjustments.contains(where: { adjustment in
            CooperativeCornerResize.frameNeedsApplication(currentFrame: adjustment.element.frame.screenFlipped,
                                                         solvedFrame: adjustment.newFrame,
                                                         screenFrame: screenFrame,
                                                         layoutTolerance: layoutTolerance)
        }) else {
            Logger.log("Cooperative resize cleanup no-op: solved frames already match current frames")
            return
        }

        applyCleanupAdjustments(cleanupAdjustments,
                                oldFocusedFrame: observedCornerFrame,
                                solvedFocusedFrame: cleanupPlan.focusedFrame,
                                axis: cooperativeAxis,
                                screenFrame: screenFrame,
                                layoutTolerance: layoutTolerance)

        let actualCandidateFramesById = Dictionary(uniqueKeysWithValues: cleanupAdjustments.map { adjustment in
            (adjustment.id, adjustment.element.frame.screenFlipped)
        })
        guard let correctionPlan = CooperativeCornerResize.correctionPlan(oldFocusedFrame: observedCornerFrame,
                                                                          requestedFocusedFrame: targetFrame,
                                                                          plannedPlan: cleanupPlan,
                                                                          screenFrame: screenFrame,
                                                                          candidates: cleanupCandidates,
                                                                          actualFocusedFrame: cleanupPlan.focusedFrame,
                                                                          actualCandidateFramesById: actualCandidateFramesById,
                                                                          axis: cooperativeAxis,
                                                                          tolerance: tolerance,
                                                                          layoutTolerance: layoutTolerance,
                                                                          minimumSize: minimumSize,
                                                                          focusedMinimumSize: syntheticFocusedMinimumSize,
                                                                          gapSize: gapSize,
                                                                          captureTolerance: captureTolerance,
                                                                          movedEdgeOverride: movedEdge,
                                                                          candidateDiscoveryFrame: observedCornerFrame,
                                                                          actionDescription: "cooperative resize cleanup settling pass")
        else {
            return
        }

        correctionPlan.debugLog.forEach(Logger.log)
        applyCleanupAdjustments(applicationAdjustments(for: correctionPlan.adjustments, elementsById: elementsById),
                                oldFocusedFrame: observedCornerFrame,
                                solvedFocusedFrame: correctionPlan.focusedFrame,
                                axis: cooperativeAxis,
                                screenFrame: screenFrame,
                                layoutTolerance: layoutTolerance)
    }

    private func applicationAdjustments(for geometryAdjustments: [CooperativeCornerResize.Adjustment],
                                        elementsById: [CGWindowID: AccessibilityElement]) -> [CooperativeCornerWindowAdjustment] {
        geometryAdjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element,
                                                    id: adjustment.id,
                                                    newFrame: adjustment.newFrame,
                                                    kind: adjustment.kind)
        }
    }

    private func applyCleanupAdjustments(_ adjustments: [CooperativeCornerWindowAdjustment],
                                         oldFocusedFrame: CGRect,
                                         solvedFocusedFrame: CGRect,
                                         axis: CornerCycleExpansionAxis,
                                         screenFrame: CGRect,
                                         layoutTolerance: CGFloat) {
        let focusedWindowIsExpanding = CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: oldFocusedFrame,
                                                                                        newFrame: solvedFocusedFrame,
                                                                                        axis: axis)
        if focusedWindowIsExpanding {
            apply(adjustments,
                  kind: .adjacent,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance)
            apply(adjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance)
        } else {
            apply(adjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance)
            apply(adjustments,
                  kind: .adjacent,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance)
        }
    }

    private func observedCornerOccupantFrame(action: WindowAction,
                                             oldFocusedFrame: CGRect,
                                             candidates: [CooperativeCornerResize.Candidate],
                                             screenFrame: CGRect,
                                             axis: CornerCycleExpansionAxis,
                                             tolerance: CGFloat,
                                             captureTolerance: CGFloat,
                                             gapSize: CGFloat) -> CGRect? {
        let cornerCandidates = candidates.filter { candidate in
            let frame = candidate.frame
            return abs(axisSize(frame, axis) - axisSize(oldFocusedFrame, axis)) <= max(tolerance, captureTolerance)
                && self.frame(frame,
                              occupiesCornerFor: action,
                              screenFrame: screenFrame,
                              tolerance: tolerance,
                              gapSize: gapSize)
        }

        return cornerCandidates.max { lhs, rhs in
            let lhsSize = axisSize(lhs.frame, axis)
            let rhsSize = axisSize(rhs.frame, axis)
            if abs(lhsSize - rhsSize) > tolerance {
                return lhsSize < rhsSize
            }
            return lhs.id > rhs.id
        }?.frame
    }

    func cleanupTargetFrame(action: WindowAction,
                            observedFrame: CGRect,
                            screenFrame: CGRect,
                            axis: CornerCycleExpansionAxis,
                            movedEdge: CooperativeCornerResize.MovedEdge,
                            tolerance: CGFloat,
                            includeCycleTargets: Bool) -> CGRect? {
        let observedSize = axisSize(observedFrame, axis)
        guard let configuredFrame = configuredCornerFrame(action: action, screenFrame: screenFrame),
              observedSize > axisSize(configuredFrame, axis) + tolerance
        else {
            return nil
        }

        let intendedSizes = intendedCornerAxisSizes(action: action,
                                                   screenFrame: screenFrame,
                                                   axis: axis,
                                                   includeCycleTargets: includeCycleTargets)
        guard let targetSize = intendedSizes.min(by: { lhs, rhs in
            abs(lhs - observedSize) < abs(rhs - observedSize)
        }),
              abs(targetSize - observedSize) > tolerance
        else {
            return nil
        }

        return frame(observedFrame,
                     axis: axis,
                     movedEdge: movedEdge,
                     size: targetSize,
                     screenFrame: screenFrame)
    }

    func frameIsAdjacentToCleanupSource(_ frame: CGRect,
                                        sourceFrame: CGRect,
                                        movedEdge: CooperativeCornerResize.MovedEdge,
                                        axis: CornerCycleExpansionAxis,
                                        tolerance: CGFloat,
                                        gapSize: CGFloat) -> Bool {
        guard movedEdgeMatches(axis: axis, movedEdge: movedEdge),
              matchesPerpendicularSpan(frame, sourceFrame: sourceFrame, movedEdge: movedEdge, tolerance: tolerance)
        else {
            return false
        }

        switch movedEdge {
        case .right:
            return abs((frame.minX - sourceFrame.maxX) - gapSize) <= tolerance
        case .left:
            return abs((sourceFrame.minX - frame.maxX) - gapSize) <= tolerance
        case .top:
            return abs((frame.minY - sourceFrame.maxY) - gapSize) <= tolerance
        case .bottom:
            return abs((sourceFrame.minY - frame.maxY) - gapSize) <= tolerance
        }
    }

    private func movedEdgeMatches(axis: CornerCycleExpansionAxis,
                                  movedEdge: CooperativeCornerResize.MovedEdge) -> Bool {
        switch (axis, movedEdge) {
        case (.horizontal, .left), (.horizontal, .right), (.vertical, .top), (.vertical, .bottom):
            return true
        default:
            return false
        }
    }

    private func matchesPerpendicularSpan(_ frame: CGRect,
                                          sourceFrame: CGRect,
                                          movedEdge: CooperativeCornerResize.MovedEdge,
                                          tolerance: CGFloat) -> Bool {
        switch movedEdge {
        case .left, .right:
            return abs(frame.minY - sourceFrame.minY) <= tolerance
                && abs(frame.maxY - sourceFrame.maxY) <= tolerance
        case .top, .bottom:
            return abs(frame.minX - sourceFrame.minX) <= tolerance
                && abs(frame.maxX - sourceFrame.maxX) <= tolerance
        }
    }

    private func intendedCornerAxisSizes(action: WindowAction,
                                         screenFrame: CGRect,
                                         axis: CornerCycleExpansionAxis,
                                         includeCycleTargets: Bool) -> [CGFloat] {
        var sizes: [CGFloat] = []
        func appendUnique(_ value: CGFloat) {
            guard value > 0,
                  !sizes.contains(where: { abs($0 - value) <= 0.001 })
            else {
                return
            }
            sizes.append(value)
        }

        if let configuredFrame = configuredCornerFrame(action: action, screenFrame: screenFrame) {
            appendUnique(axisSize(configuredFrame, axis))
        }

        guard includeCycleTargets,
              Defaults.subsequentExecutionMode.resizes else {
            return sizes
        }

        let useDefaultPositions = !Defaults.cycleSizesIsChanged.enabled
        let positions = useDefaultPositions ? CycleSize.defaultSizes : Defaults.selectedCycleSizes.value
        let sortedPositions = CycleSize.sortedSizes.filter { positions.contains($0) }
        let screenSize = axis == .horizontal ? screenFrame.width : screenFrame.height
        sortedPositions.forEach { cycleSize in
            appendUnique(floor(screenSize * CGFloat(cycleSize.fraction) + 0.0001))
        }
        return sizes
    }

    private func configuredCornerFrame(action: WindowAction, screenFrame: CGRect) -> CGRect? {
        let horizontalRatio = Defaults.horizontalSplitRatio.value / 100.0
        let verticalRatio = Defaults.verticalSplitRatio.value / 100.0
        let horizontalSide: HalfSplitSide
        let verticalSide: HalfSplitSide
        let horizontalFraction: Float
        let verticalFraction: Float

        switch action {
        case .topLeft:
            horizontalSide = .leading
            verticalSide = .leading
            horizontalFraction = horizontalRatio
            verticalFraction = verticalRatio
        case .topRight:
            horizontalSide = .trailing
            verticalSide = .leading
            horizontalFraction = 1.0 - horizontalRatio
            verticalFraction = verticalRatio
        case .bottomLeft:
            horizontalSide = .leading
            verticalSide = .trailing
            horizontalFraction = horizontalRatio
            verticalFraction = 1.0 - verticalRatio
        case .bottomRight:
            horizontalSide = .trailing
            verticalSide = .trailing
            horizontalFraction = 1.0 - horizontalRatio
            verticalFraction = 1.0 - verticalRatio
        default:
            return nil
        }

        return HalfSplitFrameCalculation.cornerRect(in: screenFrame,
                                                    horizontalSide: horizontalSide,
                                                    verticalSide: verticalSide,
                                                    horizontalFraction: horizontalFraction,
                                                    verticalFraction: verticalFraction)
    }

    private func frame(_ frame: CGRect,
                       occupiesCornerFor action: WindowAction,
                       screenFrame: CGRect,
                       tolerance: CGFloat,
                       gapSize: CGFloat) -> Bool {
        guard !frame.isNull,
              screenFrame.intersects(frame)
        else {
            return false
        }

        switch action {
        case .topLeft:
            return matchesOuterMin(frame.minX, screenFrame: screenFrame, axis: .horizontal, tolerance: tolerance, gapSize: gapSize)
                && matchesOuterMax(frame.maxY, screenFrame: screenFrame, axis: .vertical, tolerance: tolerance, gapSize: gapSize)
        case .topRight:
            return matchesOuterMax(frame.maxX, screenFrame: screenFrame, axis: .horizontal, tolerance: tolerance, gapSize: gapSize)
                && matchesOuterMax(frame.maxY, screenFrame: screenFrame, axis: .vertical, tolerance: tolerance, gapSize: gapSize)
        case .bottomLeft:
            return matchesOuterMin(frame.minX, screenFrame: screenFrame, axis: .horizontal, tolerance: tolerance, gapSize: gapSize)
                && matchesOuterMin(frame.minY, screenFrame: screenFrame, axis: .vertical, tolerance: tolerance, gapSize: gapSize)
        case .bottomRight:
            return matchesOuterMax(frame.maxX, screenFrame: screenFrame, axis: .horizontal, tolerance: tolerance, gapSize: gapSize)
                && matchesOuterMin(frame.minY, screenFrame: screenFrame, axis: .vertical, tolerance: tolerance, gapSize: gapSize)
        default:
            return false
        }
    }

    private func frame(_ observedFrame: CGRect,
                       axis: CornerCycleExpansionAxis,
                       movedEdge: CooperativeCornerResize.MovedEdge,
                       size: CGFloat,
                       screenFrame: CGRect) -> CGRect {
        var target = observedFrame
        let boundedSize = max(0, min(size, axis == .horizontal ? screenFrame.width : screenFrame.height))
        switch movedEdge {
        case .right:
            target.size.width = boundedSize
        case .left:
            target.origin.x = observedFrame.maxX - boundedSize
            target.size.width = boundedSize
        case .top:
            target.size.height = boundedSize
        case .bottom:
            target.origin.y = observedFrame.maxY - boundedSize
            target.size.height = boundedSize
        }
        return target
    }

    private func axisSize(_ frame: CGRect, _ axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.width : frame.height
    }

    private func matchesOuterMin(_ value: CGFloat,
                                 screenFrame: CGRect,
                                 axis: CornerCycleExpansionAxis,
                                 tolerance: CGFloat,
                                 gapSize: CGFloat) -> Bool {
        let screenMin = axis == .horizontal ? screenFrame.minX : screenFrame.minY
        return abs(value - screenMin) <= tolerance
            || abs(value - (screenMin + gapSize)) <= tolerance
    }

    private func matchesOuterMax(_ value: CGFloat,
                                 screenFrame: CGRect,
                                 axis: CornerCycleExpansionAxis,
                                 tolerance: CGFloat,
                                 gapSize: CGFloat) -> Bool {
        let screenMax = axis == .horizontal ? screenFrame.maxX : screenFrame.maxY
        return abs(value - screenMax) <= tolerance
            || abs(value - (screenMax - gapSize)) <= tolerance
    }

    private func apply(_ adjustments: [CooperativeCornerWindowAdjustment],
                       kind: CooperativeCornerResize.Adjustment.Kind,
                       screenFrame: CGRect,
                       layoutTolerance: CGFloat) {
        adjustments.filter { $0.kind == kind }.forEach { adjustment in
            if CooperativeCornerResize.frameNeedsApplication(currentFrame: adjustment.element.frame.screenFlipped,
                                                             solvedFrame: adjustment.newFrame,
                                                             screenFrame: screenFrame,
                                                             layoutTolerance: layoutTolerance) {
                adjustment.element.setFrame(adjustment.newFrame.screenFlipped)
            } else {
                Logger.log("Cooperative resize no-op for \(adjustment.id): current frame already matches solved frame")
            }
        }
    }

    private func correctionPlanAfterApplyingCooperatingWindows(_ plan: CooperativeCornerApplicationPlan) -> CooperativeCornerApplicationPlan? {
        let actualCandidateFramesById = Dictionary(uniqueKeysWithValues: plan.adjustments.map { adjustment in
            (adjustment.id, adjustment.element.frame.screenFlipped)
        })

        guard let correctionPlan = CooperativeCornerResize.correctionPlan(oldFocusedFrame: plan.oldFocusedFrame,
                                                                          requestedFocusedFrame: plan.requestedFocusedFrame,
                                                                          plannedPlan: plan.asGeometryPlan(),
                                                                          screenFrame: plan.screenFrame,
                                                                          candidates: plan.candidates,
                                                                          actualFocusedFrame: plan.focusedFrame,
                                                                          actualCandidateFramesById: actualCandidateFramesById,
                                                                          axis: plan.axis,
                                                                          tolerance: plan.detectionTolerance,
                                                                          layoutTolerance: plan.layoutTolerance,
                                                                          minimumSize: plan.minimumSize,
                                                                          focusedMinimumSize: plan.focusedMinimumSize,
                                                                          gapSize: plan.gapSize,
                                                                          captureTolerance: plan.captureTolerance,
                                                                          movedEdgeOverride: plan.movedEdge,
                                                                          candidateDiscoveryFrame: plan.candidateDiscoveryFrame,
                                                                          actionDescription: plan.actionDescription)
        else {
            return nil
        }

        correctionPlan.debugLog.forEach(Logger.log)
        return plan.replacingGeometry(with: correctionPlan)
    }

    private func settleCooperativeCornerResizeIfNeeded(plan: CooperativeCornerApplicationPlan,
                                                       focusedWindowElement: AccessibilityElement,
                                                       result: ResultParameters) -> CGRect? {
        let actualFocusedFrame = focusedWindowElement.frame.screenFlipped
        let actualCandidateFramesById = Dictionary(uniqueKeysWithValues: plan.adjustments.map { adjustment in
            (adjustment.id, adjustment.element.frame.screenFlipped)
        })

        guard let correctionPlan = CooperativeCornerResize.correctionPlan(oldFocusedFrame: plan.oldFocusedFrame,
                                                                          requestedFocusedFrame: plan.requestedFocusedFrame,
                                                                          plannedPlan: plan.asGeometryPlan(),
                                                                          screenFrame: plan.screenFrame,
                                                                          candidates: plan.candidates,
                                                                          actualFocusedFrame: actualFocusedFrame,
                                                                          actualCandidateFramesById: actualCandidateFramesById,
                                                                          axis: plan.axis,
                                                                          tolerance: plan.detectionTolerance,
                                                                          layoutTolerance: plan.layoutTolerance,
                                                                          minimumSize: plan.minimumSize,
                                                                          focusedMinimumSize: plan.focusedMinimumSize,
                                                                          gapSize: plan.gapSize,
                                                                          captureTolerance: plan.captureTolerance,
                                                                          movedEdgeOverride: plan.movedEdge,
                                                                          candidateDiscoveryFrame: plan.candidateDiscoveryFrame,
                                                                          actionDescription: plan.actionDescription)
        else {
            return nil
        }

        correctionPlan.debugLog.forEach(Logger.log)
        let elementsById = Dictionary(uniqueKeysWithValues: plan.adjustments.map { ($0.id, $0.element) })
        let correctionAdjustments: [CooperativeCornerWindowAdjustment] = correctionPlan.adjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element,
                                                    id: adjustment.id,
                                                    newFrame: adjustment.newFrame,
                                                    kind: adjustment.kind)
        }

        let focusedWindowIsExpanding = CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: plan.oldFocusedFrame,
                                                                                        newFrame: correctionPlan.focusedFrame,
                                                                                        axis: plan.axis)
        if focusedWindowIsExpanding {
            apply(correctionAdjustments,
                  kind: .adjacent,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
            apply(correctionAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
            _ = applyFocusedCooperativeFrameIfNeeded(correctionPlan.focusedFrame,
                                                     result: result,
                                                     layoutTolerance: plan.layoutTolerance)
        } else {
            _ = applyFocusedCooperativeFrameIfNeeded(correctionPlan.focusedFrame,
                                                     result: result,
                                                     layoutTolerance: plan.layoutTolerance)
            apply(correctionAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
            apply(correctionAdjustments,
                  kind: .adjacent,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance)
        }

        return focusedWindowElement.frame
    }

    private func applyFocusedCooperativeFrameIfNeeded(_ frame: CGRect,
                                                      result: ResultParameters,
                                                      layoutTolerance: CGFloat) -> CGRect {
        if CooperativeCornerResize.frameNeedsApplication(currentFrame: result.windowElement.frame.screenFlipped,
                                                         solvedFrame: frame,
                                                         screenFrame: result.visibleFrameOfScreen,
                                                         layoutTolerance: layoutTolerance) {
            var calcResult = result.calcResult
            calcResult.rect = frame
            let focusedResult = ResultParameters(windowId: result.windowId,
                                                 action: result.action,
                                                 windowElement: result.windowElement,
                                                 calcResult: calcResult,
                                                 usableScreens: result.usableScreens,
                                                 visibleFrameOfScreen: result.visibleFrameOfScreen,
                                                 source: result.source,
                                                 isFixedSize: result.isFixedSize)
            moveWindow(toRect: frame, result: focusedResult)
        } else {
            Logger.log("Cooperative resize focused no-op: current frame already matches solved frame")
        }
        return result.windowElement.frame
    }
}

struct CooperativeCornerWindowAdjustment {
    let element: AccessibilityElement
    let id: CGWindowID
    let newFrame: CGRect
    let kind: CooperativeCornerResize.Adjustment.Kind
}

struct CooperativeCornerApplicationPlan {
    let oldFocusedFrame: CGRect
    let requestedFocusedFrame: CGRect
    let focusedFrame: CGRect
    let screenFrame: CGRect
    let candidates: [CooperativeCornerResize.Candidate]
    let axis: CornerCycleExpansionAxis
    let detectionTolerance: CGFloat
    let captureTolerance: CGFloat
    let layoutTolerance: CGFloat
    let minimumSize: CGSize
    let focusedMinimumSize: CGSize?
    let gapSize: CGFloat
    let movedEdge: CooperativeCornerResize.MovedEdge
    let candidateDiscoveryFrame: CGRect
    let actionDescription: String
    let adjustments: [CooperativeCornerWindowAdjustment]
    let debugLog: [String]

    func needsApplication(focusedCurrentFrame: CGRect) -> Bool {
        if CooperativeCornerResize.frameNeedsApplication(currentFrame: focusedCurrentFrame,
                                                         solvedFrame: focusedFrame,
                                                         screenFrame: screenFrame,
                                                         layoutTolerance: layoutTolerance) {
            return true
        }

        return adjustments.contains { adjustment in
            CooperativeCornerResize.frameNeedsApplication(currentFrame: adjustment.element.frame.screenFlipped,
                                                         solvedFrame: adjustment.newFrame,
                                                         screenFrame: screenFrame,
                                                         layoutTolerance: layoutTolerance)
        }
    }

    func asGeometryPlan() -> CooperativeCornerResize.Plan {
        let geometryAdjustments = adjustments.map { adjustment in
            CooperativeCornerResize.Adjustment(id: adjustment.id,
                                               oldFrame: adjustment.element.frame.screenFlipped,
                                               newFrame: adjustment.newFrame,
                                               kind: adjustment.kind)
        }
        return CooperativeCornerResize.Plan(focusedFrame: focusedFrame,
                                            adjustments: geometryAdjustments,
                                            debugLog: debugLog)
    }

    func replacingGeometry(with geometryPlan: CooperativeCornerResize.Plan) -> CooperativeCornerApplicationPlan? {
        let elementsById = Dictionary(uniqueKeysWithValues: adjustments.map { ($0.id, $0.element) })
        let updatedAdjustments: [CooperativeCornerWindowAdjustment] = geometryPlan.adjustments.compactMap { adjustment in
            guard let element = elementsById[adjustment.id] else { return nil }
            return CooperativeCornerWindowAdjustment(element: element,
                                                    id: adjustment.id,
                                                    newFrame: adjustment.newFrame,
                                                    kind: adjustment.kind)
        }

        guard !updatedAdjustments.isEmpty else { return nil }

        return CooperativeCornerApplicationPlan(oldFocusedFrame: oldFocusedFrame,
                                                requestedFocusedFrame: requestedFocusedFrame,
                                                focusedFrame: geometryPlan.focusedFrame,
                                                screenFrame: screenFrame,
                                                candidates: candidates,
                                                axis: axis,
                                                detectionTolerance: detectionTolerance,
                                                captureTolerance: captureTolerance,
                                                layoutTolerance: layoutTolerance,
                                                minimumSize: minimumSize,
                                                focusedMinimumSize: focusedMinimumSize,
                                                gapSize: gapSize,
                                                movedEdge: movedEdge,
                                                candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                actionDescription: actionDescription,
                                                adjustments: updatedAdjustments,
                                                debugLog: geometryPlan.debugLog)
    }
}
