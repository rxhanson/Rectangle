import XCTest
@testable import Rectangle

final class WindowDividerWorkerSettlementTests: XCTestCase {
    func testStationaryReleaseLeavesTheHandleAvailableForDoubleClick() throws {
        let preview = try XCTUnwrap(WindowDividerResize(left: CGRect(x: 0, y: 0, width: 400, height: 600),
                                                       right: CGRect(x: 400, y: 0, width: 600, height: 600),
                                                       minimumLeft: 100, minimumRight: 100))
        preview.preview(to: preview.divider)
        XCTAssertNil(preview.takePreview(), "A click must not start placement and hide the handle before the second click")
        preview.preview(to: preview.divider + 40)
        XCTAssertEqual(preview.takePreview(), 440)
    }

    func testReportedMinimumStillWarnsWhenItBoundsTheRequestedDivider() throws {
        var frames = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 510, y: 0, width: 490, height: 800)]
        var time: TimeInterval = 0
        let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
            divider: 205, minimumLeft: 350, minimumRight: 100,
            write: { left, frame, _ in frames[left ? 0 : 1] = frame; return true }, read: { frames[$0 ? 0 : 1] }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
        XCTAssertEqual(result.left.width, 350)
        XCTAssertTrue(result.minimumSizeReached)
    }

    func testAlreadyAtAnUnreportedMinimumIsVerifiedBeforeWarning() throws {
        for axis in [WindowSplitAxis.horizontal, .vertical] {
            for shrinkingLeft in [true, false] {
                let originals = [axis.rect(CGRect(x: 0, y: 0, width: 500, height: 800)),
                                 axis.rect(CGRect(x: 500, y: 0, width: 500, height: 800))]
                var frames = originals
                var writes: [CGFloat] = []
                var time: TimeInterval = 0
                let placement = try XCTUnwrap(WindowDividerPlacement(left: originals[0], right: originals[1], axis: axis,
                    divider: shrinkingLeft ? 300 : 700, minimumLeft: 100, minimumRight: 100,
                    write: { left, target, _ in
                        XCTAssertEqual(left, shrinkingLeft, "The other window has no room to grow")
                        let index = left ? 0 : 1
                        var frame = axis.rect(target)
                        writes.append(frame.width)
                        frame.size.width = max(500, frame.width)
                        frames[index] = axis.rect(frame)
                        return true
                    }, read: { frames[$0 ? 0 : 1] }, acknowledged: { left, target in frames[left ? 0 : 1] == target }))
                let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
                XCTAssertEqual(result.left, originals[0])
                XCTAssertEqual(result.right, originals[1])
                XCTAssertTrue(result.minimumSizeReached)
                XCTAssertFalse(result.rolledBack)
                XCTAssertTrue(writes.contains(where: { $0 > 500 }), "The supposedly constrained dimension must have responded")
            }
        }
    }

    func testAnAppIgnoringSizeWritesCannotEstablishAnUnreportedMinimum() throws {
        let originals = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 500, y: 0, width: 500, height: 800)]
        for acceptsWrite in [false, true] {
            var time: TimeInterval = 0
            let placement = try XCTUnwrap(WindowDividerPlacement(left: originals[0], right: originals[1], axis: .horizontal,
                divider: 300, minimumLeft: 100, minimumRight: 100, write: { left, _, _ in
                    XCTAssertTrue(left)
                    return acceptsWrite
                }, read: { originals[$0 ? 0 : 1] }, acknowledged: { left, rect in originals[left ? 0 : 1] == rect }))
            let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
            XCTAssertTrue(result.rolledBack)
            XCTAssertFalse(result.minimumSizeReached)
        }
    }

    func testEscapeDuringAnAcceptedGrowthProbeRestoresTheOriginalPair() throws {
        let originals = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 500, y: 0, width: 500, height: 800)]
        var frames = originals
        var time: TimeInterval = 0
        var growth: (CGRect, TimeInterval)?
        var escape = false
        let placement = try XCTUnwrap(WindowDividerPlacement(left: originals[0], right: originals[1], axis: .horizontal,
            divider: 300, minimumLeft: 100, minimumRight: 100, write: { left, target, _ in
                XCTAssertTrue(left)
                if target.width > 500 {
                    growth = (target, time + 0.12)
                    escape = true
                } else {
                    frames[0].size.width = max(500, target.width)
                }
                return true
            }, read: { frames[$0 ? 0 : 1] }, acknowledged: { left, target in frames[left ? 0 : 1] == target }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, shouldRollback: { escape }, now: { time }, pause: {
            time += 0.025
            if let update = growth, time >= update.1 { frames[0] = update.0; growth = nil }
        }))
        XCTAssertTrue(escape)
        XCTAssertNil(growth)
        XCTAssertEqual(frames, originals)
        XCTAssertTrue(result.rolledBack)
        XCTAssertFalse(result.minimumSizeReached)
    }

    func testRoundedDownMemberKeepsGapAndBothOuterEdgesOnEitherAxis() throws {
        for axis in [WindowSplitAxis.horizontal, .vertical] {
            var frames = [axis.rect(CGRect(x: 0, y: 0, width: 510, height: 800)),
                          axis.rect(CGRect(x: 520, y: 0, width: 480, height: 800))]
            var time: TimeInterval = 0
            let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: axis,
                divider: 405, minimumLeft: 100, minimumRight: 100,
                write: { left, requested, attribute in
                    let i = left ? 0 : 1
                    if attribute == .size {
                        var size = axis.size(requested.size)
                        if left { size.width = floor(size.width / 17) * 17 }
                        frames[i].size = axis.size(size)
                    } else { frames[i].origin = requested.origin }
                    return true
                }, read: { frames[$0 ? 0 : 1] }))
            let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
            XCTAssertEqual(axis.rect(result.left).width, 391)
            XCTAssertEqual(axis.rect(result.left).minX, 0)
            XCTAssertEqual(axis.rect(result.right).minX, 401)
            XCTAssertEqual(axis.rect(result.right).maxX, 1000)
            XCTAssertFalse(result.minimumSizeReached)
            XCTAssertLessThan(time, 0.6)
        }
    }

    func testEscapeAfterFirstWriteRollsBothWindowsBack() throws {
        let originals = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 510, y: 0, width: 490, height: 800)]
        var frames = originals
        var time: TimeInterval = 0
        var writes = 0
        let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
            divider: 405, minimumLeft: 100, minimumRight: 100,
            write: { left, target, _ in writes += 1; frames[left ? 0 : 1] = target; return true },
            read: { frames[$0 ? 0 : 1] }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, shouldRollback: { writes > 0 },
            now: { time }, pause: { time += 0.025 }))
        XCTAssertGreaterThan(writes, 1)
        XCTAssertEqual(result.left, originals[0]); XCTAssertEqual(result.right, originals[1])
        XCTAssertEqual(frames, originals)
        XCTAssertTrue(result.rolledBack)
        XCTAssertFalse(result.minimumSizeReached)
    }

    func testDelayedAcknowledgementPreservesWriteOrderAndStableReveal() throws {
        var frames = [CGRect(x: 0, y: 0, width: 500, height: 800), CGRect(x: 510, y: 0, width: 490, height: 800)]
        var time: TimeInterval = 0
        var pending: (Int, CGRect, TimeInterval)?
        var writes: [Int] = []
        let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
            divider: 405, minimumLeft: 100, minimumRight: 100,
            write: { isLeft, target, _ in
                XCTAssertNil(pending, "A second property cannot replace an unacknowledged write")
                let index = isLeft ? 0 : 1
                writes.append(index); pending = (index, target, time + 0.12)
                return true
            }, read: { frames[$0 ? 0 : 1] }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: {
            time += 0.025
            if let update = pending, time >= update.2 { frames[update.0] = update.1; pending = nil }
        }))
        XCTAssertEqual(writes.first, 0, "Shrink the left window before expanding the right")
        XCTAssertEqual(result.left, CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(result.right, CGRect(x: 410, y: 0, width: 590, height: 800))
        XCTAssertFalse(result.minimumSizeReached)
        XCTAssertLessThan(time, 6)
    }

    func testNextDragCanShrinkBelowPreviousClampOnEitherAxis() throws {
        for axis in [WindowSplitAxis.horizontal, .vertical] {
            var frames = [axis.rect(CGRect(x: 0, y: 0, width: 700, height: 800)),
                          axis.rect(CGRect(x: 700, y: 0, width: 700, height: 800))]
            var appMinimum: CGFloat = 600
            var time: TimeInterval = 0
            func place() throws -> WindowDividerPlacement.Result {
                let minimum = WindowDividerGeometry.minimumExtent(reported: nil, current: frames[0].size, axis: axis)
                let preview = try XCTUnwrap(WindowDividerResize(left: frames[0], right: frames[1], axis: axis,
                    minimumLeft: minimum, minimumRight: 120))
                XCTAssertEqual(preview.preview(to: 250), 250, "A prior clamp cannot bound a new drag")
                let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: axis,
                    divider: 250, minimumLeft: minimum, minimumRight: 120,
                    write: { isLeft, target, attribute in
                        let index = isLeft ? 0 : 1
                        if attribute == .size {
                            var size = axis.size(target.size)
                            if isLeft { size.width = max(appMinimum, size.width) }
                            frames[index].size = axis.size(size)
                        } else { frames[index].origin = target.origin }
                        return true
                    }, read: { frames[$0 ? 0 : 1] }))
                return try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
            }
            let first = try place()
            XCTAssertEqual(axis.rect(first.left).width, 600)
            XCTAssertTrue(first.minimumSizeReached)
            appMinimum = 300
            let second = try place()
            XCTAssertEqual(axis.rect(second.left).width, 300)
            XCTAssertEqual(axis.rect(second.right).minX, 300)
            XCTAssertEqual(axis.rect(second.right).maxX, 1400)
        }
    }

    func testRollbackRestoresBothWindowsAfterAClampAndFailedExpansion() throws {
        var frames = [CGRect(x: 0, y: 0, width: 700, height: 800),
                      CGRect(x: 700, y: 0, width: 700, height: 800)]
        var time: TimeInterval = 0
        let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
            divider: 250, minimumLeft: 120, minimumRight: 120,
            write: { isLeft, target, attribute in
                let index = isLeft ? 0 : 1
                if !isLeft, target.width > 700 { return false }
                if attribute == .size { frames[index].size = CGSize(width: isLeft ? max(500, target.width) : target.width, height: target.height) }
                else { frames[index].origin = target.origin }
                return true
            }, read: { frames[$0 ? 0 : 1] }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
        XCTAssertEqual(result.left.width, 700)
        XCTAssertEqual(result.right.width, 700)
        XCTAssertFalse(result.minimumSizeReached)
    }

    func testAXClampRequiresMatchingFinalWindowServerFrames() throws {
        for serverDelay in [TimeInterval(0.3), 10] {
            var frames = [CGRect(x: 0, y: 0, width: 700, height: 800),
                          CGRect(x: 700, y: 0, width: 700, height: 800)]
            var time: TimeInterval = 0
            let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
                divider: 250, minimumLeft: 120, minimumRight: 120,
                write: { isLeft, target, attribute in
                    let index = isLeft ? 0 : 1
                    if attribute == .size { frames[index].size = CGSize(width: isLeft ? max(500, target.width) : target.width, height: target.height) }
                    else { frames[index].origin = target.origin }
                    return true
                }, read: { frames[$0 ? 0 : 1] },
                acknowledged: { _, _ in time >= serverDelay }))
            let result = placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 })
            if serverDelay < 1 {
                XCTAssertEqual(result?.left.width, 500)
                XCTAssertGreaterThanOrEqual(time, serverDelay + 0.05)
            } else { XCTAssertNil(result) }
        }
    }
}

final class WindowDividerSystemOverlayTests: XCTestCase {
    private let left = WindowInfo(id: 101, level: 0, frame: CGRect(x: 0, y: 0, width: 400, height: 300), pid: 11, processName: "Left")
    private let right = WindowInfo(id: 102, level: 0, frame: CGRect(x: 400, y: 0, width: 400, height: 300), pid: 12, processName: "Right")
    private let point = CGPoint(x: 400, y: 150)
    private let region = CGRect(x: 376, y: 96, width: 48, height: 108)

    func testSystemCursorDoesNotHideTheDividerButSystemPopupStillDoes() {
        let cursor = WindowInfo(id: 2, level: CGWindowLevelForKey(.cursorWindow),
            frame: CGRect(x: 386, y: 136, width: 28, height: 28), pid: 1, processName: "Window Server")
        XCTAssertTrue(WindowDividerGeometry.unobscured(left: left.id, right: right.id,
            in: [cursor, left, right], near: region))
        let popup = WindowInfo(id: 3, level: 24, frame: region, pid: 1, processName: "Window Server")
        XCTAssertFalse(WindowDividerGeometry.unobscured(left: left.id, right: right.id,
            in: [popup, left, right], near: region))
    }

    func testOrdinaryAppAtCursorLevelStillBlocksTheDivider() {
        let popup = WindowInfo(id: 3, level: CGWindowLevelForKey(.cursorWindow),
            frame: region, pid: 20, processName: "Other app")
        XCTAssertFalse(WindowDividerGeometry.unobscured(left: left.id, right: right.id,
            in: [popup, left, right], near: region))
    }

    func testCaptureOverlayIsPassiveOnlyWhenInputReachesThePair() {
        let overlay = WindowInfo(id: 3, level: 24, frame: left.frame.union(right.frame), pid: 20, processName: "Screenshot")
        let infos = [overlay, left, right]
        let passive = WindowDividerGeometry.passiveCaptureOverlayIDs(in: infos, at: point,
            hitPID: left.pid, ownedPIDs: [left.pid, right.pid], capturePIDs: [overlay.pid])
        XCTAssertTrue(WindowDividerGeometry.unobscured(left: left.id, right: right.id,
            in: infos, near: region, ignoring: passive))
        for hitPID in [Optional(overlay.pid), nil] {
            let blocking = WindowDividerGeometry.passiveCaptureOverlayIDs(in: infos, at: point,
                hitPID: hitPID, ownedPIDs: [left.pid, right.pid], capturePIDs: [overlay.pid])
            XCTAssertTrue(blocking.isEmpty)
            XCTAssertFalse(WindowDividerGeometry.unobscured(left: left.id, right: right.id,
                in: infos, near: region, ignoring: blocking))
        }
    }

    func testUnknownOrDistantCaptureWindowIsNotIgnored() {
        let overlay = WindowInfo(id: 3, level: 24, frame: region, pid: 20, processName: "Screenshot")
        XCTAssertTrue(WindowDividerGeometry.passiveCaptureOverlayIDs(in: [overlay], at: point,
            hitPID: left.pid, ownedPIDs: [left.pid], capturePIDs: []).isEmpty)
        XCTAssertTrue(WindowDividerGeometry.passiveCaptureOverlayIDs(in: [overlay], at: .zero,
            hitPID: left.pid, ownedPIDs: [left.pid], capturePIDs: [overlay.pid]).isEmpty)
    }
}

final class WindowDividerInterruptionRegressionTests: XCTestCase {
    func testOnlyClosedEntriesArePrunedAndIncompleteListsAreIgnored() {
        let hidden = WindowInfo(id: 1, level: 0, frame: CGRect(x: 0, y: 0, width: 500, height: 800), pid: 2, processName: nil, isOnScreen: false)
        let visible = WindowInfo(id: 3, level: 0, frame: hidden.frame, pid: 2, processName: nil)
        XCTAssertEqual(WindowDividerManager.retainedWindowIDs(recorded: [1, 3, 4], existing: [hidden, visible], recording: 3), [1, 3])
        XCTAssertEqual(WindowDividerManager.retainedWindowIDs(recorded: [1, 3], existing: [], recording: 3), [1, 3])
    }

    func testClickThroughOverlayUsesActualRecipientAndPreservesUnrelatedClicks() throws {
        let cg = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 99)
        for (recipient, expected) in [(Int64(1), WindowDividerManager.Interruption.cancel), (3, .ignore), (0, .cancel)] {
            cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: recipient)
            let event = try XCTUnwrap(NSEvent(cgEvent: cg))
            XCTAssertEqual(WindowDividerManager.interruption(event, placingMembers: [1, 2]), expected)
        }
    }

    func testEscapeRequestsRollbackOnlyWhilePlacing() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53))
        XCTAssertEqual(WindowDividerManager.interruption(event, placingMembers: [1, 2]), .rollback)
        XCTAssertEqual(WindowDividerManager.interruption(event, placingMembers: nil), .cancel)
    }
}

final class WindowDividerCrossAxisRegressionTests: XCTestCase {
    func testRoundingCannotCommitAnIneligiblePair() throws {
        let original = [CGRect(x: 0, y: 0, width: 510, height: 799), CGRect(x: 520, y: 0, width: 480, height: 800)]
        var frames = original
        var time: TimeInterval = 0
        let placement = try XCTUnwrap(WindowDividerPlacement(left: frames[0], right: frames[1], axis: .horizontal,
            divider: 405, minimumLeft: 100, minimumRight: 100,
            write: { left, requested, attribute in
                let i = left ? 0 : 1
                if attribute == .size {
                    frames[i].size = requested.size
                    if left, requested.width < 500 { frames[i].size = CGSize(width: 391, height: 797) }
                } else { frames[i].origin = requested.origin }
                return true
            }, read: { frames[$0 ? 0 : 1] }))
        let result = try XCTUnwrap(placement.settle(isCurrent: { true }, now: { time }, pause: { time += 0.025 }))
        XCTAssertEqual(result.left, original[0]); XCTAssertEqual(result.right, original[1])
        XCTAssertNotNil(WindowDividerGeometry(left: result.left, right: result.right))
    }
}


final class WindowDividerDiscoveryAndHistoryTests: XCTestCase {
    func testSettlementWaitsForTheOnscreenFrameAndReturnsItsInventory() throws {
        let target = CGRect(x: 0, y: 523, width: 1920, height: 493)
        let before = CGRect(x: 998, y: 313, width: 634, height: 400)
        var time = 0.0
        var inventories = 0
        let result = WindowDividerManager.settledInventory(id: 8, pid: 7, frame: target,
            isCurrent: { true }, eligible: { time >= 0.025 }, inventory: {
                inventories += 1
                return [WindowInfo(id: 8, level: 0, frame: inventories == 1 ? before : target, pid: 7, processName: nil)]
            }, now: { time }, pause: { time += 0.025 })
        XCTAssertEqual(try XCTUnwrap(result?.first).frame, target)
        XCTAssertEqual(inventories, 2)
    }

    func testSettlementRejectsAChangedFrameClosedWindowOrReusedIdentity() {
        let target = CGRect(x: 0, y: 30, width: 960, height: 986)
        let moved = WindowInfo(id: 8, level: 0, frame: target.offsetBy(dx: 40, dy: 20), pid: 7, processName: nil)
        let replacement = WindowInfo(id: 8, level: 0, frame: target, pid: 23, processName: nil)
        for list in [[moved], [], [replacement]] {
            var time = 0.0
            XCTAssertNil(WindowDividerManager.settledInventory(id: 8, pid: 7, frame: target,
                isCurrent: { true }, eligible: { true }, inventory: { list },
                now: { time }, pause: { time += 0.025 }))
            if list.first?.pid == 23 { XCTAssertEqual(time, 0) }
            XCTAssertLessThan(time, 0.3)
        }
        var current = true
        XCTAssertNil(WindowDividerManager.settledInventory(id: 8, pid: 7, frame: target,
            isCurrent: { current }, eligible: { true }, inventory: {
                current = false
                return [WindowInfo(id: 8, level: 0, frame: target, pid: 7, processName: nil)]
            }, now: { 0 }, pause: {}))
    }

    func testPairDiscoveryUsesTheEffectiveWorkAreaOnBothAxes() {
        for axis in [WindowSplitAxis.horizontal, .vertical] {
            let area = CGRect(x: 110, y: 60, width: 1010, height: 500)
            let left = CGRect(x: 110, y: 60, width: 650, height: 500)
            let right = CGRect(x: 770, y: 60, width: 350, height: 500)
            XCTAssertEqual(WindowDividerGeometry.axis(for: axis.rect(left), in: axis.rect(area)), axis)
            XCTAssertEqual(WindowDividerGeometry.axis(for: axis.rect(right), in: axis.rect(area)), axis)
            let expanded = CGRect(x: 0, y: 60, width: 1120, height: 500)
            XCTAssertNil(WindowDividerGeometry.axis(for: axis.rect(left), in: axis.rect(expanded)))
            XCTAssertNil(WindowDividerGeometry.axis(for: axis.rect(left.insetBy(dx: 0, dy: 10)), in: axis.rect(area)))
        }
    }

    func testIncompleteRollbackReconcilesEachOriginalMemberWithoutCountingAnAction() {
        let history = WindowHistory()
        let left = CGRect(x: 0, y: 0, width: 300, height: 400)
        let right = CGRect(x: 300, y: 0, width: 500, height: 400)
        history.recordAction(windowId: 8, resultingRect: left, action: .leftHalf, subAction: nil)
        history.recordAction(windowId: 9, resultingRect: right, action: .rightHalf, subAction: nil)
        history.restoreRects[9] = left
        WindowDividerManager.reconcileAfterFailure(id: 8, original: left, observed: left, history: history)
        WindowDividerManager.reconcileAfterFailure(id: 9, original: right, observed: right.offsetBy(dx: 60, dy: 0), history: history)
        XCTAssertEqual(history.lastRectangleActions[8]?.count, 1)
        XCTAssertEqual(history.lastRectangleActions[8]?.rect, left)
        XCTAssertNil(history.lastRectangleActions[9])
        XCTAssertEqual(history.restoreRects[9], left)
        history.recordAction(windowId: 9, resultingRect: left, action: .maximize, subAction: nil)
        WindowDividerManager.reconcileAfterFailure(id: 9, original: right, observed: nil, history: history)
        XCTAssertEqual(history.lastRectangleActions[9]?.action, .maximize)
    }
}

@MainActor
final class WindowDividerHandoffTests: XCTestCase {
    func testMemberClaimStopsOldRollbackAndWaitsForTheIssuedWrite() async {
        let fence = WindowWriteFence()
        let left = WindowWriteFence.Target(element: nil, windowID: 10)
        let right = WindowWriteFence.Target(element: nil, windowID: 11)
        let lease = fence.claim([left, right])
        let operation = WindowDividerOperation(lease: lease)
        let insideWrite = expectation(description: "The first member is resizing")
        let released = DispatchSemaphore(value: 0)
        let completed = expectation(description: "Old writer exits after its issued call returns")
        let newOwner = expectation(description: "The conflicting writer proceeds after the divider")
        let unrelatedOwner = expectation(description: "An unrelated writer proceeds during the resize")
        let originals = [CGRect(x: 0, y: 0, width: 500, height: 600), CGRect(x: 500, y: 0, width: 500, height: 600)]

        fence.whenReady(lease) {
            fence.perform(lease, work: {
                var frames = originals
                var writes = 0
                let placement = WindowDividerPlacement(left: originals[0], right: originals[1], axis: .horizontal,
                    divider: 400, minimumLeft: 100, minimumRight: 100, write: { isLeft, frame, _ in
                        writes += 1
                        if writes == 1 {
                            insideWrite.fulfill()
                            _ = released.wait(timeout: .now() + 3)
                        }
                        frames[isLeft ? 0 : 1] = frame
                        return true
                    }, read: { frames[$0 ? 0 : 1] })!
                let result = placement.settle(isCurrent: { lease.isCurrent }, shouldRollback: { operation.rollbackRequested })
                return (result, writes)
            }, completion: { result, writes in
                XCTAssertNil(result)
                XCTAssertEqual(writes, 1)
                fence.finish(lease)
                completed.fulfill()
            })
        }

        await fulfillment(of: [insideWrite], timeout: 2)
        operation.requestRollback()
        let replacement = fence.claim([right])
        fence.whenReady(replacement) { newOwner.fulfill(); fence.finish(replacement) }
        let unrelated = fence.claim([.init(element: nil, windowID: 99)])
        fence.whenReady(unrelated) { unrelatedOwner.fulfill(); fence.finish(unrelated) }
        XCTAssertFalse(lease.isCurrent)
        await fulfillment(of: [unrelatedOwner], timeout: 1)
        released.signal()
        await fulfillment(of: [newOwner, completed], timeout: 2)
    }
}
