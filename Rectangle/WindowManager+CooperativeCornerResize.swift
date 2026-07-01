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
            ? CooperativeCornerResize.focusedFramePreservingOccupiedCell(requestedFocusedFrame: newFocusedFrame,
                                                                         screenFrame: screenFrame,
                                                                         candidates: candidates,
                                                                         axis: cooperativeAxis,
                                                                         movedEdge: movedEdge,
                                                                         tolerance: tolerance)
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
