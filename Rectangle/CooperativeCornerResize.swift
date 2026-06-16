/// CooperativeCornerResize.swift

import Cocoa

struct CooperativeCornerResize {
    struct Candidate {
        let id: CGWindowID
        let frame: CGRect
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

    enum MovedEdge {
        case left, right, top, bottom
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
        guard let movedEdge = movedEdge(from: oldFocusedFrame, to: newFocusedFrame, axis: axis, tolerance: tolerance) else {
            return []
        }

        let matchingFocusedFrameAdjustments = candidates.compactMap { candidate -> Adjustment? in
            guard !candidate.frame.isNull,
                  screenFrame.intersects(candidate.frame),
                  approximatelyMatchesFrame(candidate.frame, oldFocusedFrame, tolerance: tolerance),
                  newFocusedFrame.width >= minimumSize.width,
                  newFocusedFrame.height >= minimumSize.height,
                  screenFrame.intersects(newFocusedFrame)
            else {
                return nil
            }

            return Adjustment(id: candidate.id,
                              oldFrame: candidate.frame,
                              newFrame: newFocusedFrame,
                              kind: .matchingFocusedFrame)
        }

        let matchingFocusedFrameIds = Set(matchingFocusedFrameAdjustments.map(\.id))

        let matchingMovingSpanAdjustments = candidates.compactMap { candidate -> Adjustment? in
            guard !matchingFocusedFrameIds.contains(candidate.id),
                  !candidate.frame.isNull,
                  screenFrame.intersects(candidate.frame),
                  matchesMovingSpan(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
                  isSupportedPerpendicularSpan(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance)
            else {
                return nil
            }

            var newFrame = candidate.frame
            switch movedEdge {
            case .left, .right:
                newFrame.origin.x = newFocusedFrame.minX
                newFrame.size.width = newFocusedFrame.width
            case .top, .bottom:
                newFrame.origin.y = newFocusedFrame.minY
                newFrame.size.height = newFocusedFrame.height
            }

            guard newFrame.width >= minimumSize.width,
                  newFrame.height >= minimumSize.height,
                  screenFrame.intersects(newFrame)
            else {
                return nil
            }

            return Adjustment(id: candidate.id,
                              oldFrame: candidate.frame,
                              newFrame: newFrame,
                              kind: .matchingFocusedFrame)
        }

        let matchingMovingSpanIds = Set(matchingMovingSpanAdjustments.map(\.id))

        let adjacentAdjustments = candidates.compactMap { candidate -> Adjustment? in
            guard !matchingFocusedFrameIds.contains(candidate.id),
                  !matchingMovingSpanIds.contains(candidate.id),
                  !candidate.frame.isNull,
                  screenFrame.intersects(candidate.frame),
                  isSupportedPerpendicularSpan(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance),
                  touchesOldMovingEdge(candidate.frame, oldFocusedFrame, movedEdge: movedEdge, tolerance: tolerance)
            else {
                return nil
            }

            var newFrame = candidate.frame
            switch movedEdge {
            case .left:
                newFrame.size.width = newFocusedFrame.minX - candidate.frame.minX
            case .right:
                newFrame.origin.x = newFocusedFrame.maxX
                newFrame.size.width = candidate.frame.maxX - newFocusedFrame.maxX
            case .bottom:
                newFrame.size.height = newFocusedFrame.minY - candidate.frame.minY
            case .top:
                newFrame.origin.y = newFocusedFrame.maxY
                newFrame.size.height = candidate.frame.maxY - newFocusedFrame.maxY
            }

            guard !candidate.frame.isNull,
                  newFrame.width >= minimumSize.width,
                  newFrame.height >= minimumSize.height,
                  screenFrame.intersects(newFrame)
            else {
                return nil
            }

            return Adjustment(id: candidate.id,
                              oldFrame: candidate.frame,
                              newFrame: newFrame,
                              kind: .adjacent)
        }

        return matchingFocusedFrameAdjustments + matchingMovingSpanAdjustments + adjacentAdjustments
    }

    static func focusedWindowIsExpanding(oldFrame: CGRect, newFrame: CGRect, axis: CornerCycleExpansionAxis) -> Bool {
        switch axis {
        case .horizontal:
            return newFrame.width > oldFrame.width
        case .vertical:
            return newFrame.height > oldFrame.height
        }
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
