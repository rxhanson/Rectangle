/// CooperativeResizeCoordinator.swift

import Cocoa

/// Applies CooperativeCornerResize's geometry to real windows: finding the windows
/// involved, writing their frames, and cleaning up after a window leaves a layout.
struct CooperativeResizeCoordinator {
    private let windowElements: () -> [AccessibilityElement]
    private let windowHistory: WindowHistory

    init(windowHistory: WindowHistory,
         windowElements: @escaping () -> [AccessibilityElement] = { AccessibilityElement.getAllWindowElements() }) {
        self.windowHistory = windowHistory
        self.windowElements = windowElements
    }

    /// The coordinator to use for window moves, or nil while the setting is off.
    static func ifEnabled(windowHistory: WindowHistory,
                          windowElements: @escaping () -> [AccessibilityElement] = { AccessibilityElement.getAllWindowElements() }) -> CooperativeResizeCoordinator? {
        guard Defaults.cooperativeCornerResize.enabled else { return nil }
        return CooperativeResizeCoordinator(windowHistory: windowHistory, windowElements: windowElements)
    }

    private enum Side {
        case left, right, top, bottom
    }

    static func axis(for action: WindowAction) -> CornerCycleExpansionAxis? {
        switch action {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return Defaults.cornerCycleExpansionAxis.value
        case .leftHalf, .rightHalf:
            return .horizontal
        case .topHalf, .bottomHalf:
            return .vertical
        default:
            return nil
        }
    }

    static func movedEdge(for action: WindowAction) -> CooperativeCornerResize.MovedEdge? {
        switch side(for: action) {
        case .left:
            return .right
        case .right:
            return .left
        case .top:
            return .bottom
        case .bottom:
            return .top
        case .none:
            return nil
        }
    }

    static func isCornerAction(_ action: WindowAction) -> Bool {
        switch action {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return true
        default:
            return false
        }
    }

    static func allowsResize(from source: ExecutionSource) -> Bool {
        switch source {
        case .keyboardShortcut, .dragToSnap:
            return true
        case .menuItem, .url, .titleBar, .newWindow:
            return false
        }
    }

    private static func side(for action: WindowAction) -> Side? {
        switch action {
        case .leftHalf:
            return .left
        case .rightHalf:
            return .right
        case .topHalf:
            return .top
        case .bottomHalf:
            return .bottom
        case .topLeft:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .left : .top
        case .topRight:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .right : .top
        case .bottomLeft:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .left : .bottom
        case .bottomRight:
            return Defaults.cornerCycleExpansionAxis.value == .horizontal ? .right : .bottom
        default:
            return nil
        }
    }

    /// Starts a move, planning for other windows to cooperate in it where they can.
    /// When the window moves alone, the target's side split ratio is recorded instead.
    func beginMove(_ request: WindowMoveRequest) -> CooperativeMove {
        var calcResult = request.calcResult
        guard let plan = cooperativeCornerResizePlan(focusedWindowId: request.windowId,
                                                     focusedWindowIsFixedSize: request.isFixedSize,
                                                     focusedWindowMinimumSize: request.minimumSize,
                                                     action: request.action,
                                                     source: request.source,
                                                     oldFocusedFrame: request.currentFrame,
                                                     newFocusedFrame: calcResult.rect,
                                                     screenFrame: request.screenFrame,
                                                     destinationScreenIsCurrentScreen: request.destinationScreenIsCurrentScreen,
                                                     lastRectangleAction: request.lastRectangleAction)
        else {
            ActiveSideSplitRatios.shared.recordSideAction(calcResult.resultingAction,
                                                          targetFrame: calcResult.initialRect,
                                                          screenFrame: request.screenFrame)
            return CooperativeMove(calcResult: calcResult, placement: nil, request: request, coordinator: self)
        }

        calcResult.rect = plan.focusedFrame
        if let sideSplitRecordingFrame = plan.sideSplitRecordingFrame {
            calcResult.initialRect = sideSplitRecordingFrame
        }
        let placement = CooperativePlacement(currentFrame: request.currentFrame, plan: plan, coordinator: self)
        return CooperativeMove(calcResult: calcResult, placement: placement, request: request, coordinator: self)
    }

    fileprivate func cleanUpAfterMove(_ request: WindowMoveRequest, resultingRect: CGRect, screenFrame: CGRect) {
        applyCooperativeCornerCleanupIfNeeded(focusedWindowId: request.windowId,
                                              source: request.source,
                                              oldFocusedFrame: request.currentFrame,
                                              newFocusedFrame: resultingRect.screenFlipped,
                                              screenFrame: screenFrame,
                                              currentAction: request.action,
                                              lastRectangleAction: request.lastRectangleAction)
    }

    fileprivate func recordAchievedRatio(_ plan: CooperativeCornerApplicationPlan, achievedFrame: CGRect) {
        ActiveSideSplitRatios.shared.recordAchievedCooperativeAction(plan.action,
                                                                    achievedFrame: achievedFrame,
                                                                    screenFrame: plan.screenFrame,
                                                                    gapSize: plan.gapSize)
    }

    fileprivate func applyCooperativeCornerResize(result: ResultParameters,
                                                  plan: CooperativeCornerApplicationPlan,
                                                  moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect {
        var activePlan = plan
        let focusedWindowIsExpanding = CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: result.windowElement.frame.screenFlipped,
                                                                                        newFrame: activePlan.focusedFrame,
                                                                                        axis: activePlan.axis)

        if focusedWindowIsExpanding {
            apply(activePlan.adjustments,
                  kind: .adjacent,
                  screenFrame: activePlan.screenFrame,
                  layoutTolerance: activePlan.layoutTolerance,
                  sourceAction: activePlan.action,
                  movedEdge: activePlan.movedEdge,
                  historyUpdate: .advance)
            apply(activePlan.adjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: activePlan.screenFrame,
                  layoutTolerance: activePlan.layoutTolerance,
                  sourceAction: activePlan.action,
                  movedEdge: activePlan.movedEdge,
                  historyUpdate: .advance)

            if let correctedPlan = correctionPlanAfterApplyingCooperatingWindows(activePlan) {
                activePlan = correctedPlan
                apply(activePlan.adjustments,
                      kind: .adjacent,
                      screenFrame: activePlan.screenFrame,
                      layoutTolerance: activePlan.layoutTolerance,
                      sourceAction: activePlan.action,
                      movedEdge: activePlan.movedEdge,
                      historyUpdate: .preserve)
                apply(activePlan.adjustments,
                      kind: .matchingFocusedFrame,
                      screenFrame: activePlan.screenFrame,
                      layoutTolerance: activePlan.layoutTolerance,
                      sourceAction: activePlan.action,
                      movedEdge: activePlan.movedEdge,
                      historyUpdate: .preserve)
            }

            var resultingRect = applyFocusedCooperativeFrameIfNeeded(activePlan.focusedFrame,
                                                                     result: result,
                                                                     layoutTolerance: activePlan.layoutTolerance,
                                                                     moveWindow: moveWindow)
            if let settledRect = settleCooperativeCornerResizeIfNeeded(plan: activePlan,
                                                                       focusedWindowElement: result.windowElement,
                                                                       result: result,
                                                                       moveWindow: moveWindow) {
                resultingRect = settledRect
            }
            return resultingRect
        }

        var resultingRect = applyFocusedCooperativeFrameIfNeeded(activePlan.focusedFrame,
                                                                 result: result,
                                                                 layoutTolerance: activePlan.layoutTolerance,
                                                                 moveWindow: moveWindow)
        apply(activePlan.adjustments,
              kind: .matchingFocusedFrame,
              screenFrame: activePlan.screenFrame,
              layoutTolerance: activePlan.layoutTolerance,
              sourceAction: activePlan.action,
              movedEdge: activePlan.movedEdge,
              historyUpdate: .advance)
        apply(activePlan.adjustments,
              kind: .adjacent,
              screenFrame: activePlan.screenFrame,
              layoutTolerance: activePlan.layoutTolerance,
              sourceAction: activePlan.action,
              movedEdge: activePlan.movedEdge,
              historyUpdate: .advance)

        if let settledRect = settleCooperativeCornerResizeIfNeeded(plan: activePlan,
                                                                   focusedWindowElement: result.windowElement,
                                                                   result: result,
                                                                   moveWindow: moveWindow) {
            resultingRect = settledRect
        }
        return resultingRect
    }

    private func cooperativeCornerResizePlan(focusedWindowId: CGWindowID?,
                                             focusedWindowIsFixedSize: Bool,
                                             focusedWindowMinimumSize: CGSize?,
                                             action: WindowAction,
                                             source: ExecutionSource,
                                             oldFocusedFrame: CGRect,
                                             newFocusedFrame: CGRect,
                                             screenFrame: CGRect,
                                             destinationScreenIsCurrentScreen: Bool,
                                             lastRectangleAction: RectangleAction?) -> CooperativeCornerApplicationPlan? {
        guard Self.allowsResize(from: source),
              let focusedWindowId,
              !focusedWindowIsFixedSize,
              destinationScreenIsCurrentScreen,
              let cooperativeAxis = Self.axis(for: action),
              let movedEdge = Self.movedEdge(for: action)
        else {
            return nil
        }

        let gapSize = max(0, CGFloat(Defaults.gapSize.value))
        let tolerance = CooperativeCornerResize.detectionTolerance(screenFrame: screenFrame, configuredGap: gapSize)
        let captureTolerance = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: cooperativeAxis)
        let isRepeatedCooperativeAction = action == lastRectangleAction?.action
        if isRepeatedCooperativeAction, !Self.isCornerAction(action),
           Defaults.subsequentExecutionMode.value == .switchSides,
           CooperativeCornerResize.isSideSwitch(oldFocusedFrame: oldFocusedFrame, newFocusedFrame: newFocusedFrame,
                                                axis: cooperativeAxis, tolerance: tolerance) {
            // A repeated half action that switched sides is a move, not a resize of the shared edge:
            // planned as one, the action's moved edge would be pushed across the screen, squeezing the
            // neighbor and recording a wrong split ratio. Corners cycle quadrant positions through their
            // own cooperative path and keep it.
            return nil
        }
        let actionDescription = isRepeatedCooperativeAction ? "repeated cooperative resize" : "initial corner/side cooperative placement"
        let screenFrameAX = screenFrame.screenFlipped
        let elementsById = windowElements().reduce(into: [CGWindowID: AccessibilityElement]()) { elements, element in
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
        var sideSplitRecordingFrame: CGRect?
        var requestedFocusedFrame = (!isRepeatedCooperativeAction && Self.isCornerAction(action))
            ? CooperativeCornerResize.focusedFrameResolvingRealizedCornerBoundary(requestedFocusedFrame: newFocusedFrame,
                                                                                  screenFrame: screenFrame,
                                                                                  candidates: candidates,
                                                                                  axis: cooperativeAxis,
                                                                                  movedEdge: movedEdge,
                                                                                  tolerance: tolerance,
                                                                                  gapSize: gapSize)
            : newFocusedFrame
        if isRepeatedCooperativeAction,
           let lookAheadTarget = cycleLookAheadTargetForMinimumRestrictedAdjacent(action: action,
                                                                                  oldFocusedFrame: oldFocusedFrame,
                                                                                  requestedFocusedFrame: requestedFocusedFrame,
                                                                                  screenFrame: screenFrame,
                                                                                  candidates: candidates,
                                                                                  axis: cooperativeAxis,
                                                                                  movedEdge: movedEdge,
                                                                                  tolerance: tolerance,
                                                                                  gapSize: gapSize) {
            Logger.log("Cooperative resize skipped cyclic target \(lookAheadTarget.skippedCycleSize.title) for \(lookAheadTarget.targetCycleSize.title): adjacent window \(lookAheadTarget.restrictedAdjacentId) is already in the minimum cycle band")
            requestedFocusedFrame = lookAheadTarget.gappedFrame
            sideSplitRecordingFrame = lookAheadTarget.rawFrame
        }
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
                                                action: action,
                                                candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                actionDescription: actionDescription,
                                                adjustments: adjustments,
                                                sideSplitRecordingFrame: sideSplitRecordingFrame,
                                                debugLog: plan.debugLog)
    }

    private func applyCooperativeCornerCleanupIfNeeded(focusedWindowId: CGWindowID?,
                                                       source: ExecutionSource,
                                                       oldFocusedFrame: CGRect,
                                                       newFocusedFrame: CGRect,
                                                       screenFrame: CGRect,
                                                       currentAction: WindowAction,
                                                       lastRectangleAction: RectangleAction?) {
        guard Self.allowsResize(from: source),
              let previousAction = lastRectangleAction?.action,
              currentAction != previousAction,
              let cooperativeAxis = Self.axis(for: previousAction),
              let movedEdge = Self.movedEdge(for: previousAction),
              !oldFocusedFrame.isNull,
              !newFocusedFrame.isNull,
              !screenFrame.isNull,
              screenFrame.intersects(oldFocusedFrame),
              let focusedWindowId
        else {
            return
        }

        let gapSize = max(0, CGFloat(Defaults.gapSize.value))
        let tolerance = CooperativeCornerResize.detectionTolerance(screenFrame: screenFrame, configuredGap: gapSize)
        let captureTolerance = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: cooperativeAxis)
        let layoutTolerance: CGFloat = 4
        let screenFrameAX = screenFrame.screenFlipped
        let allElementsById = windowElements().reduce(into: [CGWindowID: AccessibilityElement]()) { elements, element in
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
        guard let observedSourceFrame = cleanupSourceFrame(action: previousAction,
                                                           oldFocusedFrame: oldFocusedFrame,
                                                           candidates: candidates,
                                                           screenFrame: screenFrame,
                                                           axis: cooperativeAxis,
                                                           movedEdge: movedEdge,
                                                           tolerance: tolerance,
                                                           captureTolerance: captureTolerance,
                                                           gapSize: gapSize)
        else {
            return
        }

        var targetCandidates = candidates
        let focusedElement = allElementsById[focusedWindowId]
        if let focusedElement {
            targetCandidates.append(CooperativeCornerResize.Candidate(id: focusedWindowId,
                                                                      frame: focusedElement.frame.screenFlipped,
                                                                      minimumSize: focusedElement.minimumSize))
        }

        guard let targetFrame = cleanupTargetFrame(action: previousAction,
                                                   observedFrame: observedSourceFrame,
                                                   screenFrame: screenFrame,
                                                   axis: cooperativeAxis,
                                                   movedEdge: movedEdge,
                                                   tolerance: tolerance,
                                                   includeCycleTargets: (lastRectangleAction?.count ?? 0) > 1,
                                                   candidates: targetCandidates,
                                                   gapSize: gapSize)
        else {
            return
        }

        let focusedDestinationFrame = focusedElement?.frame.screenFlipped ?? newFocusedFrame
        guard cleanupDestinationAllowsSourceResize(action: previousAction,
                                                   observedFrame: observedSourceFrame,
                                                   targetFrame: targetFrame,
                                                   focusedDestinationFrame: focusedDestinationFrame,
                                                   screenFrame: screenFrame,
                                                   axis: cooperativeAxis,
                                                   movedEdge: movedEdge,
                                                   tolerance: tolerance,
                                                   gapSize: gapSize)
        else {
            return
        }

        let minimumSize = CGSize(width: max(1, CGFloat(Defaults.minimumWindowWidth.value)),
                                 height: max(1, CGFloat(Defaults.minimumWindowHeight.value)))
        let syntheticFocusedMinimumSize = CGSize(width: 1, height: 1)
        if let focusedElement {
            elementsById[focusedWindowId] = focusedElement
        }

        let cleanupCandidates = elementsById.map { id, element in
            CooperativeCornerResize.Candidate(id: id,
                                              frame: element.frame.screenFlipped,
                                              minimumSize: element.minimumSize)
        }
        guard let cleanupPlan = CooperativeCornerResize.plan(oldFocusedFrame: observedSourceFrame,
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
                                                             candidateDiscoveryFrame: observedSourceFrame,
                                                             actionDescription: "cooperative resize cleanup after focused window left source")
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
                                oldFocusedFrame: observedSourceFrame,
                                solvedFocusedFrame: cleanupPlan.focusedFrame,
                                sourceAction: previousAction,
                                movedEdge: movedEdge,
                                axis: cooperativeAxis,
                                screenFrame: screenFrame,
                                layoutTolerance: layoutTolerance)

        let actualCandidateFramesById = Dictionary(uniqueKeysWithValues: cleanupAdjustments.map { adjustment in
            (adjustment.id, adjustment.element.frame.screenFlipped)
        })
        guard let correctionPlan = CooperativeCornerResize.correctionPlan(oldFocusedFrame: observedSourceFrame,
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
                                                                          candidateDiscoveryFrame: observedSourceFrame,
                                                                          actionDescription: "cooperative resize cleanup settling pass")
        else {
            return
        }

        correctionPlan.debugLog.forEach(Logger.log)
        applyCleanupAdjustments(applicationAdjustments(for: correctionPlan.adjustments, elementsById: elementsById),
                                oldFocusedFrame: observedSourceFrame,
                                solvedFocusedFrame: correctionPlan.focusedFrame,
                                sourceAction: previousAction,
                                movedEdge: movedEdge,
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
                                         sourceAction: WindowAction,
                                         movedEdge: CooperativeCornerResize.MovedEdge,
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
                  layoutTolerance: layoutTolerance,
                  sourceAction: sourceAction,
                  movedEdge: movedEdge,
                  historyUpdate: .preserve)
            apply(adjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance,
                  sourceAction: sourceAction,
                  movedEdge: movedEdge,
                  historyUpdate: .preserve)
        } else {
            apply(adjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance,
                  sourceAction: sourceAction,
                  movedEdge: movedEdge,
                  historyUpdate: .preserve)
            apply(adjustments,
                  kind: .adjacent,
                  screenFrame: screenFrame,
                  layoutTolerance: layoutTolerance,
                  sourceAction: sourceAction,
                  movedEdge: movedEdge,
                  historyUpdate: .preserve)
        }
    }

    func observedCooperativeSourceFrame(action: WindowAction,
                                        oldFocusedFrame: CGRect,
                                        candidates: [CooperativeCornerResize.Candidate],
                                        screenFrame: CGRect,
                                        axis: CornerCycleExpansionAxis,
                                        movedEdge: CooperativeCornerResize.MovedEdge,
                                        tolerance: CGFloat,
                                        captureTolerance: CGFloat,
                                        gapSize: CGFloat) -> CGRect? {
        let sourceCandidates = candidates.filter { candidate in
            let frame = candidate.frame
            guard abs(axisSize(frame, axis) - axisSize(oldFocusedFrame, axis)) <= max(tolerance, captureTolerance),
                  self.frame(frame,
                             occupiesSourceFor: action,
                             screenFrame: screenFrame,
                             tolerance: tolerance,
                             gapSize: gapSize)
            else {
                return false
            }

            return Self.isCornerAction(action)
                || matchesPerpendicularSpan(frame,
                                            sourceFrame: oldFocusedFrame,
                                            movedEdge: movedEdge,
                                            tolerance: max(tolerance, captureTolerance))
        }

        return sourceCandidates.max { lhs, rhs in
            let lhsSize = axisSize(lhs.frame, axis)
            let rhsSize = axisSize(rhs.frame, axis)
            if abs(lhsSize - rhsSize) > tolerance {
                return lhsSize < rhsSize
            }
            return lhs.id > rhs.id
        }?.frame
    }

    func cleanupSourceFrame(action: WindowAction,
                            oldFocusedFrame: CGRect,
                            candidates: [CooperativeCornerResize.Candidate],
                            screenFrame: CGRect,
                            axis: CornerCycleExpansionAxis,
                            movedEdge: CooperativeCornerResize.MovedEdge,
                            tolerance: CGFloat,
                            captureTolerance: CGFloat,
                            gapSize: CGFloat) -> CGRect? {
        if let observedSourceFrame = observedCooperativeSourceFrame(action: action,
                                                                    oldFocusedFrame: oldFocusedFrame,
                                                                    candidates: candidates,
                                                                    screenFrame: screenFrame,
                                                                    axis: axis,
                                                                    movedEdge: movedEdge,
                                                                    tolerance: tolerance,
                                                                    captureTolerance: captureTolerance,
                                                                    gapSize: gapSize) {
            return observedSourceFrame
        }

        return departedMinimumRestrictedCleanupSourceFrame(action: action,
                                                           oldFocusedFrame: oldFocusedFrame,
                                                           screenFrame: screenFrame,
                                                           axis: axis,
                                                           movedEdge: movedEdge,
                                                           tolerance: tolerance,
                                                           gapSize: gapSize)
    }

    private func departedMinimumRestrictedCleanupSourceFrame(action: WindowAction,
                                                             oldFocusedFrame: CGRect,
                                                             screenFrame: CGRect,
                                                             axis: CornerCycleExpansionAxis,
                                                             movedEdge: CooperativeCornerResize.MovedEdge,
                                                             tolerance: CGFloat,
                                                             gapSize: CGFloat) -> CGRect? {
        guard Self.isCornerAction(action),
              minimumRestrictedCleanupTargetFrame(action: action,
                                                  observedFrame: oldFocusedFrame,
                                                  screenFrame: screenFrame,
                                                  axis: axis,
                                                  movedEdge: movedEdge,
                                                  tolerance: tolerance,
                                                  gapSize: gapSize) != nil
        else {
            return nil
        }

        return oldFocusedFrame
    }

    func cleanupTargetFrame(action: WindowAction,
                            observedFrame: CGRect,
                            screenFrame: CGRect,
                            axis: CornerCycleExpansionAxis,
                            movedEdge: CooperativeCornerResize.MovedEdge,
                            tolerance: CGFloat,
                            includeCycleTargets: Bool,
                            candidates: [CooperativeCornerResize.Candidate] = [],
                            gapSize: CGFloat = 0) -> CGRect? {
        let observedSize = axisSize(observedFrame, axis)
        let targetFrames = intendedCleanupTargetFrames(action: action,
                                                       screenFrame: screenFrame,
                                                       axis: axis,
                                                       includeCycleTargets: includeCycleTargets,
                                                       gapSize: gapSize)
        if let configuredFrame = configuredActionFrame(action: action, screenFrame: screenFrame) {
            let configuredSize = axisSize(gappedFrame(configuredFrame, action: action, gapSize: gapSize), axis)
            if observedSize > configuredSize + tolerance {
                if observedFrameMatchesNonConfiguredCycleTarget(action: action,
                                                                observedFrame: observedFrame,
                                                                screenFrame: screenFrame,
                                                                axis: axis,
                                                                configuredSize: configuredSize,
                                                                tolerance: tolerance,
                                                                gapSize: gapSize) {
                    return nil
                }
                if adjacentSmallerCycleTargetContainsWindow(candidates,
                                                            adjacentTo: observedFrame,
                                                            action: action,
                                                            screenFrame: screenFrame,
                                                            axis: axis,
                                                            movedEdge: movedEdge,
                                                            configuredSize: configuredSize,
                                                            tolerance: tolerance,
                                                            gapSize: gapSize) {
                    return nil
                }

                if let targetSize = nearestTargetSize(to: observedSize, frames: targetFrames, axis: axis, tolerance: tolerance) {
                    return frame(observedFrame,
                                 axis: axis,
                                 movedEdge: movedEdge,
                                 size: targetSize,
                                 screenFrame: screenFrame)
                }
            }
        }

        if includeCycleTargets,
           observedFrameMatchesCycleTarget(action: action,
                                           observedFrame: observedFrame,
                                           screenFrame: screenFrame,
                                           axis: axis,
                                           tolerance: tolerance,
                                           gapSize: gapSize) {
            return nil
        }

        return minimumRestrictedCleanupTargetFrame(action: action,
                                                   observedFrame: observedFrame,
                                                   screenFrame: screenFrame,
                                                   axis: axis,
                                                   movedEdge: movedEdge,
                                                   tolerance: tolerance,
                                                   gapSize: gapSize)
    }

    func cleanupDestinationAllowsSourceResize(action: WindowAction,
                                              observedFrame: CGRect,
                                              targetFrame: CGRect,
                                              focusedDestinationFrame: CGRect,
                                              screenFrame: CGRect,
                                              axis: CornerCycleExpansionAxis,
                                              movedEdge: CooperativeCornerResize.MovedEdge,
                                              tolerance: CGFloat,
                                              gapSize: CGFloat) -> Bool {
        if frameIsAdjacentToCleanupSource(focusedDestinationFrame,
                                          sourceFrame: observedFrame,
                                          movedEdge: movedEdge,
                                          axis: axis,
                                          tolerance: tolerance,
                                          gapSize: gapSize) {
            return true
        }

        guard let minimumRestrictedTarget = minimumRestrictedCleanupTargetFrame(action: action,
                                                                               observedFrame: observedFrame,
                                                                               screenFrame: screenFrame,
                                                                               axis: axis,
                                                                               movedEdge: movedEdge,
                                                                               tolerance: tolerance,
                                                                               gapSize: gapSize)
        else {
            return false
        }

        return framesMatch(minimumRestrictedTarget, targetFrame, tolerance: max(CGFloat(4), tolerance))
    }

    private func observedFrameMatchesNonConfiguredCycleTarget(action: WindowAction,
                                                              observedFrame: CGRect,
                                                              screenFrame: CGRect,
                                                              axis: CornerCycleExpansionAxis,
                                                              configuredSize: CGFloat,
                                                              tolerance: CGFloat,
                                                              gapSize: CGFloat) -> Bool {
        let observedSize = axisSize(observedFrame, axis)
        return cycleTargetFrames(action: action,
                                 screenFrame: screenFrame,
                                 axis: axis,
                                 gapSize: gapSize)
            .contains { targetFrame in
                let targetSize = axisSize(targetFrame.gappedFrame, axis)
                return abs(targetSize - observedSize) <= tolerance
                    && abs(targetSize - configuredSize) > tolerance
            }
    }

    private func observedFrameMatchesCycleTarget(action: WindowAction,
                                                 observedFrame: CGRect,
                                                 screenFrame: CGRect,
                                                 axis: CornerCycleExpansionAxis,
                                                 tolerance: CGFloat,
                                                 gapSize: CGFloat) -> Bool {
        let observedSize = axisSize(observedFrame, axis)
        return cycleTargetFrames(action: action,
                                 screenFrame: screenFrame,
                                 axis: axis,
                                 gapSize: gapSize)
            .contains { targetFrame in
                abs(axisSize(targetFrame.gappedFrame, axis) - observedSize) <= tolerance
            }
    }

    private func adjacentSmallerCycleTargetContainsWindow(_ candidates: [CooperativeCornerResize.Candidate],
                                                          adjacentTo observedFrame: CGRect,
                                                          action: WindowAction,
                                                          screenFrame: CGRect,
                                                          axis: CornerCycleExpansionAxis,
                                                          movedEdge: CooperativeCornerResize.MovedEdge,
                                                          configuredSize: CGFloat,
                                                          tolerance: CGFloat,
                                                          gapSize: CGFloat) -> Bool {
        guard let adjacentAction = adjacentCycleAction(for: action, movedEdge: movedEdge) else {
            return false
        }

        let adjacentCycleSizes = cycleTargetFrames(action: adjacentAction,
                                                   screenFrame: screenFrame,
                                                   axis: axis,
                                                   gapSize: gapSize)
            .map { axisSize($0.gappedFrame, axis) }
        let sizeTolerance = max(CGFloat(4), tolerance)

        return candidates.contains { candidate in
            let frame = candidate.frame
            guard frameIsAdjacentToCleanupSource(frame,
                                                 sourceFrame: observedFrame,
                                                 movedEdge: movedEdge,
                                                 axis: axis,
                                                 tolerance: tolerance,
                                                 gapSize: gapSize)
            else {
                return false
            }

            let currentSize = axisSize(frame, axis)
            return currentSize < configuredSize - sizeTolerance
                && adjacentCycleSizes.contains { abs($0 - currentSize) <= sizeTolerance }
        }
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

    func cycleLookAheadTargetForMinimumRestrictedAdjacent(action: WindowAction,
                                                          oldFocusedFrame: CGRect,
                                                          requestedFocusedFrame: CGRect,
                                                          screenFrame: CGRect,
                                                          candidates: [CooperativeCornerResize.Candidate],
                                                          axis: CornerCycleExpansionAxis,
                                                          movedEdge: CooperativeCornerResize.MovedEdge,
                                                          tolerance: CGFloat,
                                                          gapSize: CGFloat) -> CooperativeCycleLookAheadTarget? {
        // A neighbor between the smallest and second-smallest cycle sizes is often already
        // minimum-constrained, so expanding into that band would consume a press as a no-op.
        guard CooperativeCornerResize.focusedWindowIsExpanding(oldFrame: oldFocusedFrame,
                                                               newFrame: requestedFocusedFrame,
                                                               axis: axis),
              let adjacentAction = adjacentCycleAction(for: action, movedEdge: movedEdge)
        else {
            return nil
        }

        let targetFrames = cycleTargetFrames(action: action,
                                             screenFrame: screenFrame,
                                             axis: axis,
                                             gapSize: gapSize)
        guard targetFrames.count > 1,
              let requestedIndex = targetFrames.firstIndex(where: { framesMatch($0.gappedFrame, requestedFocusedFrame, tolerance: 1) })
        else {
            return nil
        }

        let adjacentCycleSizes = uniqueSortedSizes(cycleTargetFrames(action: adjacentAction,
                                                                     screenFrame: screenFrame,
                                                                     axis: axis,
                                                                     gapSize: gapSize)
            .map { axisSize($0.gappedFrame, axis) })
        guard adjacentCycleSizes.count >= 2 else {
            return nil
        }

        let minimumCycleSize = adjacentCycleSizes[0]
        let secondMinimumCycleSize = adjacentCycleSizes[1]
        let sizeTolerance = max(CGFloat(4), tolerance)
        // Detection tolerance finds neighbors; only layout tolerance means a size is on a cycle boundary.
        let cycleBoundaryTolerance: CGFloat = 4

        guard let restrictedAdjacent = candidates.first(where: { candidate in
            let frame = candidate.frame
            guard frameIsAdjacentToCleanupSource(frame,
                                                 sourceFrame: oldFocusedFrame,
                                                 movedEdge: movedEdge,
                                                 axis: axis,
                                                 tolerance: tolerance,
                                                 gapSize: gapSize)
            else {
                return false
            }

            let currentSize = axisSize(frame, axis)
            let proposedSize = adjacentAxisSize(frame,
                                                afterFocusedFrame: requestedFocusedFrame,
                                                movedEdge: movedEdge,
                                                gapSize: gapSize)
            return currentSize > minimumCycleSize + cycleBoundaryTolerance
                && currentSize < secondMinimumCycleSize - cycleBoundaryTolerance
                && proposedSize < currentSize - sizeTolerance
        }) else {
            return nil
        }

        var nextIndex = (requestedIndex + 1) % targetFrames.count
        for _ in targetFrames.indices {
            let targetFrame = targetFrames[nextIndex]
            if !framesMatch(targetFrame.gappedFrame, oldFocusedFrame, tolerance: sizeTolerance) {
                return CooperativeCycleLookAheadTarget(rawFrame: targetFrame.rawFrame,
                                                       gappedFrame: targetFrame.gappedFrame,
                                                       skippedCycleSize: targetFrames[requestedIndex].cycleSize,
                                                       targetCycleSize: targetFrame.cycleSize,
                                                       restrictedAdjacentId: restrictedAdjacent.id)
            }
            nextIndex = (nextIndex + 1) % targetFrames.count
        }

        return nil
    }

    private func minimumRestrictedCleanupTargetFrame(action: WindowAction,
                                                     observedFrame: CGRect,
                                                     screenFrame: CGRect,
                                                     axis: CornerCycleExpansionAxis,
                                                     movedEdge: CooperativeCornerResize.MovedEdge,
                                                     tolerance: CGFloat,
                                                     gapSize: CGFloat) -> CGRect? {
        let cycleSizes = uniqueSortedSizes(cycleTargetFrames(action: action,
                                                             screenFrame: screenFrame,
                                                             axis: axis,
                                                             gapSize: gapSize)
            .map { axisSize($0.gappedFrame, axis) })
        guard cycleSizes.count >= 2 else {
            return nil
        }

        let minimumCycleSize = cycleSizes[0]
        let secondMinimumCycleSize = cycleSizes[1]
        let observedSize = axisSize(observedFrame, axis)
        // Keep a near-boundary constrained size distinct from the exact cycle size it could not reach.
        let cycleBoundaryTolerance: CGFloat = 4

        guard observedSize > minimumCycleSize + cycleBoundaryTolerance,
              observedSize < secondMinimumCycleSize - cycleBoundaryTolerance
        else {
            return nil
        }

        return frame(observedFrame,
                     axis: axis,
                     movedEdge: movedEdge,
                     size: minimumCycleSize,
                     screenFrame: screenFrame)
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

    private func intendedCleanupTargetFrames(action: WindowAction,
                                             screenFrame: CGRect,
                                             axis: CornerCycleExpansionAxis,
                                             includeCycleTargets: Bool,
                                             gapSize: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        func appendUnique(_ frame: CGRect) {
            guard !frame.isNull,
                  !frames.contains(where: { !CooperativeCornerResize.framesDiffer($0, frame, tolerance: 0.001) })
            else {
                return
            }
            frames.append(frame)
        }

        if let configuredFrame = configuredActionFrame(action: action, screenFrame: screenFrame) {
            appendUnique(gappedFrame(configuredFrame, action: action, gapSize: gapSize))
        }

        guard includeCycleTargets,
              Defaults.subsequentExecutionMode.resizes else {
            return frames
        }

        cycleTargetFrames(action: action,
                          screenFrame: screenFrame,
                          axis: axis,
                          gapSize: gapSize)
            .forEach { appendUnique($0.gappedFrame) }
        return frames
    }

    private func nearestTargetSize(to observedSize: CGFloat,
                                   frames: [CGRect],
                                   axis: CornerCycleExpansionAxis,
                                   tolerance: CGFloat) -> CGFloat? {
        guard let targetSize = frames.map({ axisSize($0, axis) }).min(by: { lhs, rhs in
            abs(lhs - observedSize) < abs(rhs - observedSize)
        }),
              abs(targetSize - observedSize) > tolerance
        else {
            return nil
        }

        return targetSize
    }

    private func sortedCooperativeCycleSizes() -> [CycleSize] {
        let useDefaultPositions = !Defaults.cycleSizesIsChanged.enabled
        let positions = useDefaultPositions ? CycleSize.defaultSizes : Defaults.selectedCycleSizes.value
        return CycleSize.sortedSizes.filter { positions.contains($0) }
    }

    private func cycleTargetFrames(action: WindowAction,
                                   screenFrame: CGRect,
                                   axis: CornerCycleExpansionAxis,
                                   gapSize: CGFloat) -> [CooperativeCycleTargetFrame] {
        sortedCooperativeCycleSizes().compactMap { cycleSize in
            guard let rawFrame = rawCycleFrame(action: action,
                                               cycleSize: cycleSize,
                                               screenFrame: screenFrame,
                                               axis: axis)
            else {
                return nil
            }

            return CooperativeCycleTargetFrame(cycleSize: cycleSize,
                                               rawFrame: rawFrame,
                                               gappedFrame: gappedFrame(rawFrame,
                                                                        action: action,
                                                                        gapSize: gapSize))
        }
    }

    private func rawCycleFrame(action: WindowAction,
                               cycleSize: CycleSize,
                               screenFrame: CGRect,
                               axis: CornerCycleExpansionAxis) -> CGRect? {
        let fraction = cycleSize.fraction

        switch action {
        case .leftHalf:
            return HalfSplitFrameCalculation.horizontalRect(in: screenFrame, side: .leading, fraction: fraction)
        case .rightHalf:
            return HalfSplitFrameCalculation.horizontalRect(in: screenFrame, side: .trailing, fraction: fraction)
        case .topHalf:
            return HalfSplitFrameCalculation.verticalRect(in: screenFrame, side: .leading, fraction: fraction)
        case .bottomHalf:
            return HalfSplitFrameCalculation.verticalRect(in: screenFrame, side: .trailing, fraction: fraction)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return rawCornerCycleFrame(action: action,
                                       cycleFraction: fraction,
                                       screenFrame: screenFrame,
                                       axis: axis)
        default:
            return nil
        }
    }

    private func rawCornerCycleFrame(action: WindowAction,
                                     cycleFraction: Float,
                                     screenFrame: CGRect,
                                     axis: CornerCycleExpansionAxis) -> CGRect? {
        let horizontalRatio = ActiveSideSplitRatios.shared.horizontalRatio(for: screenFrame)
        let verticalRatio = ActiveSideSplitRatios.shared.verticalRatio(for: screenFrame)
        let horizontalSide: HalfSplitSide
        let verticalSide: HalfSplitSide

        switch action {
        case .topLeft:
            horizontalSide = .leading
            verticalSide = .leading
        case .topRight:
            horizontalSide = .trailing
            verticalSide = .leading
        case .bottomLeft:
            horizontalSide = .leading
            verticalSide = .trailing
        case .bottomRight:
            horizontalSide = .trailing
            verticalSide = .trailing
        default:
            return nil
        }

        let horizontalFraction = axis == .horizontal
            ? cycleFraction
            : (horizontalSide == .trailing ? 1.0 - horizontalRatio : horizontalRatio)
        let verticalFraction = axis == .vertical
            ? cycleFraction
            : (verticalSide == .trailing ? 1.0 - verticalRatio : verticalRatio)

        return HalfSplitFrameCalculation.cornerRect(in: screenFrame,
                                                    horizontalSide: horizontalSide,
                                                    verticalSide: verticalSide,
                                                    horizontalFraction: horizontalFraction,
                                                    verticalFraction: verticalFraction)
    }

    private func gappedFrame(_ frame: CGRect,
                             action: WindowAction,
                             gapSize: CGFloat) -> CGRect {
        let gapsApplicable = action.gapsApplicable
        guard gapSize > 0,
              gapsApplicable != .none
        else {
            return frame
        }

        return GapCalculation.applyGaps(frame,
                                        dimension: gapsApplicable,
                                        sharedEdges: action.gapSharedEdge,
                                        gapSize: Float(gapSize),
                                        skipTopGap: Defaults.skipGapTopEdge.enabled)
    }

    private func adjacentCycleAction(for action: WindowAction,
                                     movedEdge: CooperativeCornerResize.MovedEdge) -> WindowAction? {
        switch (action, movedEdge) {
        case (.leftHalf, .right):
            return .rightHalf
        case (.rightHalf, .left):
            return .leftHalf
        case (.topHalf, .bottom):
            return .bottomHalf
        case (.bottomHalf, .top):
            return .topHalf
        case (.topLeft, .right):
            return .topRight
        case (.topLeft, .bottom):
            return .bottomLeft
        case (.topRight, .left):
            return .topLeft
        case (.topRight, .bottom):
            return .bottomRight
        case (.bottomLeft, .right):
            return .bottomRight
        case (.bottomLeft, .top):
            return .topLeft
        case (.bottomRight, .left):
            return .bottomLeft
        case (.bottomRight, .top):
            return .topRight
        default:
            return nil
        }
    }

    private func uniqueSortedSizes(_ sizes: [CGFloat]) -> [CGFloat] {
        sizes.sorted().reduce(into: [CGFloat]()) { uniqueSizes, size in
            guard !uniqueSizes.contains(where: { abs($0 - size) <= 0.001 }) else {
                return
            }
            uniqueSizes.append(size)
        }
    }

    private func adjacentAxisSize(_ frame: CGRect,
                                  afterFocusedFrame focusedFrame: CGRect,
                                  movedEdge: CooperativeCornerResize.MovedEdge,
                                  gapSize: CGFloat) -> CGFloat {
        switch movedEdge {
        case .right:
            return max(0, frame.maxX - (focusedFrame.maxX + gapSize))
        case .left:
            return max(0, (focusedFrame.minX - gapSize) - frame.minX)
        case .top:
            return max(0, frame.maxY - (focusedFrame.maxY + gapSize))
        case .bottom:
            return max(0, (focusedFrame.minY - gapSize) - frame.minY)
        }
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        !CooperativeCornerResize.framesDiffer(lhs, rhs, tolerance: tolerance)
    }

    private func configuredActionFrame(action: WindowAction, screenFrame: CGRect) -> CGRect? {
        let horizontalRatio = ActiveSideSplitRatios.shared.horizontalRatio(for: screenFrame)
        let verticalRatio = ActiveSideSplitRatios.shared.verticalRatio(for: screenFrame)
        let horizontalSide: HalfSplitSide
        let verticalSide: HalfSplitSide
        let horizontalFraction: Float
        let verticalFraction: Float

        switch action {
        case .leftHalf:
            return HalfSplitFrameCalculation.horizontalRect(in: screenFrame,
                                                            side: .leading,
                                                            fraction: horizontalRatio)
        case .rightHalf:
            return HalfSplitFrameCalculation.horizontalRect(in: screenFrame,
                                                            side: .trailing,
                                                            fraction: 1.0 - horizontalRatio)
        case .topHalf:
            return HalfSplitFrameCalculation.verticalRect(in: screenFrame,
                                                          side: .leading,
                                                          fraction: verticalRatio)
        case .bottomHalf:
            return HalfSplitFrameCalculation.verticalRect(in: screenFrame,
                                                          side: .trailing,
                                                          fraction: 1.0 - verticalRatio)
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
                       occupiesSourceFor action: WindowAction,
                       screenFrame: CGRect,
                       tolerance: CGFloat,
                       gapSize: CGFloat) -> Bool {
        guard !frame.isNull,
              screenFrame.intersects(frame)
        else {
            return false
        }

        switch action {
        case .leftHalf:
            return matchesOuterMin(frame.minX, screenFrame: screenFrame, axis: .horizontal, tolerance: tolerance, gapSize: gapSize)
        case .rightHalf:
            return matchesOuterMax(frame.maxX, screenFrame: screenFrame, axis: .horizontal, tolerance: tolerance, gapSize: gapSize)
        case .topHalf:
            return matchesOuterMax(frame.maxY, screenFrame: screenFrame, axis: .vertical, tolerance: tolerance, gapSize: gapSize)
        case .bottomHalf:
            return matchesOuterMin(frame.minY, screenFrame: screenFrame, axis: .vertical, tolerance: tolerance, gapSize: gapSize)
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
                       layoutTolerance: CGFloat,
                       sourceAction: WindowAction,
                       movedEdge: CooperativeCornerResize.MovedEdge,
                       historyUpdate: CooperativeHistoryUpdate) {
        adjustments.filter { $0.kind == kind }.forEach { adjustment in
            if CooperativeCornerResize.frameNeedsApplication(currentFrame: adjustment.element.frame.screenFlipped,
                                                             solvedFrame: adjustment.newFrame,
                                                             screenFrame: screenFrame,
                                                             layoutTolerance: layoutTolerance) {
                adjustment.element.setFrame(adjustment.newFrame.screenFlipped)
            } else {
                Logger.log("Cooperative resize no-op for \(adjustment.id): current frame already matches solved frame")
            }
            recordCooperativeHistory(for: adjustment,
                                     sourceAction: sourceAction,
                                     movedEdge: movedEdge,
                                     historyUpdate: historyUpdate)
        }
    }

    func cooperativeHistoryAction(for kind: CooperativeCornerResize.Adjustment.Kind,
                                  sourceAction: WindowAction,
                                  movedEdge: CooperativeCornerResize.MovedEdge) -> WindowAction? {
        switch kind {
        case .matchingFocusedFrame:
            return sourceAction
        case .adjacent:
            return adjacentCycleAction(for: sourceAction, movedEdge: movedEdge)
        }
    }

    private func recordCooperativeHistory(for adjustment: CooperativeCornerWindowAdjustment,
                                          sourceAction: WindowAction,
                                          movedEdge: CooperativeCornerResize.MovedEdge,
                                          historyUpdate: CooperativeHistoryUpdate) {
        guard historyUpdate != .none,
              let action = cooperativeHistoryAction(for: adjustment.kind,
                                                    sourceAction: sourceAction,
                                                    movedEdge: movedEdge)
        else {
            return
        }

        let resultingRect = adjustment.element.frame
        guard !resultingRect.isNull else {
            return
        }

        windowHistory.recordAction(windowId: adjustment.id,
                                   resultingRect: resultingRect,
                                   action: action,
                                   subAction: nil,
                                   incrementCount: historyUpdate == .advance)
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
                                                       result: ResultParameters,
                                                       moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect? {
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
                  layoutTolerance: plan.layoutTolerance,
                  sourceAction: plan.action,
                  movedEdge: plan.movedEdge,
                  historyUpdate: .preserve)
            apply(correctionAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance,
                  sourceAction: plan.action,
                  movedEdge: plan.movedEdge,
                  historyUpdate: .preserve)
            _ = applyFocusedCooperativeFrameIfNeeded(correctionPlan.focusedFrame,
                                                     result: result,
                                                     layoutTolerance: plan.layoutTolerance,
                                                     moveWindow: moveWindow)
        } else {
            _ = applyFocusedCooperativeFrameIfNeeded(correctionPlan.focusedFrame,
                                                     result: result,
                                                     layoutTolerance: plan.layoutTolerance,
                                                     moveWindow: moveWindow)
            apply(correctionAdjustments,
                  kind: .matchingFocusedFrame,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance,
                  sourceAction: plan.action,
                  movedEdge: plan.movedEdge,
                  historyUpdate: .preserve)
            apply(correctionAdjustments,
                  kind: .adjacent,
                  screenFrame: plan.screenFrame,
                  layoutTolerance: plan.layoutTolerance,
                  sourceAction: plan.action,
                  movedEdge: plan.movedEdge,
                  historyUpdate: .preserve)
        }

        return focusedWindowElement.frame
    }

    private func applyFocusedCooperativeFrameIfNeeded(_ frame: CGRect,
                                                      result: ResultParameters,
                                                      layoutTolerance: CGFloat,
                                                      moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect {
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
            moveWindow(frame, focusedResult)
        } else {
            Logger.log("Cooperative resize focused no-op: current frame already matches solved frame")
        }
        return result.windowElement.frame
    }
}

/// What a window action wants to do, for CooperativeResizeCoordinator to plan.
struct WindowMoveRequest {
    let calcResult: WindowCalculationResult
    let windowId: CGWindowID?
    let isFixedSize: Bool
    let minimumSize: CGSize?
    let action: WindowAction
    let source: ExecutionSource
    let currentFrame: CGRect
    let screenFrame: CGRect
    let destinationScreenIsCurrentScreen: Bool
    let lastRectangleAction: RectangleAction?
}

/// A window move in progress while cooperative resize is on.
struct CooperativeMove {
    /// The calculation result, revised to the frame this move will aim for.
    let calcResult: WindowCalculationResult
    /// How other windows cooperate in this move, or nil when the window moves alone.
    let placement: CooperativePlacement?
    fileprivate let request: WindowMoveRequest
    fileprivate let coordinator: CooperativeResizeCoordinator

    /// Tidies the layout the focused window just left, once it has settled on the same screen.
    /// This applies to any move, whether or not other windows cooperated in it.
    func cleanUp(resultingRect: CGRect, screenFrame: CGRect) {
        coordinator.cleanUpAfterMove(request, resultingRect: resultingRect, screenFrame: screenFrame)
    }
}

/// The part of a move that other windows cooperate in, ready to be carried out.
struct CooperativePlacement {
    fileprivate let currentFrame: CGRect
    fileprivate let plan: CooperativeCornerApplicationPlan
    fileprivate let coordinator: CooperativeResizeCoordinator

    /// Returns true when no window needs to move, recording the split ratio already achieved.
    func isAlreadyAchieved() -> Bool {
        guard !plan.needsApplication(focusedCurrentFrame: currentFrame) else { return false }

        coordinator.recordAchievedRatio(plan, achievedFrame: currentFrame)
        Logger.log("Cooperative resize no-op: solved frames already match current frames")
        return true
    }

    /// Writes the plan's frames and records the split ratio that was achieved.
    /// - Returns: The rect of the focused window after placing it
    func place(result: ResultParameters, moveWindow: (CGRect, ResultParameters) -> Void) -> CGRect {
        let resultingRect = coordinator.applyCooperativeCornerResize(result: result, plan: plan, moveWindow: moveWindow)
        // AX can enforce a minimum size that was not reported before the settling pass.
        coordinator.recordAchievedRatio(plan, achievedFrame: resultingRect.screenFlipped)
        return resultingRect
    }
}

struct CooperativeCornerWindowAdjustment {
    let element: AccessibilityElement
    let id: CGWindowID
    let newFrame: CGRect
    let kind: CooperativeCornerResize.Adjustment.Kind
}

private struct CooperativeCycleTargetFrame {
    let cycleSize: CycleSize
    let rawFrame: CGRect
    let gappedFrame: CGRect
}

struct CooperativeCycleLookAheadTarget {
    let rawFrame: CGRect
    let gappedFrame: CGRect
    let skippedCycleSize: CycleSize
    let targetCycleSize: CycleSize
    let restrictedAdjacentId: CGWindowID
}

enum CooperativeHistoryUpdate {
    case advance
    case preserve
    case none
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
    let action: WindowAction
    let candidateDiscoveryFrame: CGRect
    let actionDescription: String
    let adjustments: [CooperativeCornerWindowAdjustment]
    let sideSplitRecordingFrame: CGRect?
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
                                                action: action,
                                                candidateDiscoveryFrame: candidateDiscoveryFrame,
                                                actionDescription: actionDescription,
                                                adjustments: updatedAdjustments,
                                                sideSplitRecordingFrame: sideSplitRecordingFrame,
                                                debugLog: geometryPlan.debugLog)
    }
}
