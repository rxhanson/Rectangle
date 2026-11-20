/// WindowAnimationTests.swift

import XCTest
@testable import Rectangle

class WindowAnimationPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 29, width: 1403, height: 869)

    private func placement(for zone: CGRect, screen: CGRect? = nil) -> WindowAnimationPlacement {
        let screen = screen ?? self.screen
        return WindowAnimationPlacement(screenFrame: screen, sharedEdges: zone.sharedEdges(withRect: screen),
                                        constrainToScreen: true, gap: 0)
    }

    func testMinimumSizeKeepsEverySelectedEdgeAndCorner() {
        let cases: [(CGRect, CGSize, CGPoint)] = [
            (CGRect(x: 702, y: 29, width: 701, height: 869), CGSize(width: 913, height: 869), CGPoint(x: 490, y: 29)),
            (CGRect(x: 0, y: 29, width: 701, height: 869), CGSize(width: 913, height: 869), CGPoint(x: 0, y: 29)),
            (CGRect(x: 0, y: 29, width: 1403, height: 434), CGSize(width: 1403, height: 600), CGPoint(x: 0, y: 29)),
            (CGRect(x: 0, y: 464, width: 1403, height: 434), CGSize(width: 1403, height: 600), CGPoint(x: 0, y: 298)),
            (CGRect(x: 0, y: 29, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 0, y: 29)),
            (CGRect(x: 702, y: 29, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 490, y: 29)),
            (CGRect(x: 0, y: 464, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 0, y: 298)),
            (CGRect(x: 702, y: 464, width: 701, height: 434), CGSize(width: 913, height: 600), CGPoint(x: 490, y: 298))
        ]
        for (zone, size, expected) in cases {
            let result = placement(for: zone).frame(for: zone, actualSize: size, origin: screen, progress: 1)
            XCTAssertEqual(result.origin, expected)
            XCTAssertEqual(result.size, size)
        }
    }

    func testWidthLimitDoesNotReverseMotionOrJumpAtTheEnd() {
        let origin = CGRect(x: 100, y: 100, width: 1100, height: 650)
        let target = CGRect(x: 702, y: 29, width: 701, height: 869)
        let placement = placement(for: target)
        var previous = origin
        for step in 1...100 {
            let t = CGFloat(step) / 100
            let requested = CGRect(x: origin.minX + (target.minX - origin.minX) * t,
                                   y: origin.minY + (target.minY - origin.minY) * t,
                                   width: origin.width + (target.width - origin.width) * t,
                                   height: origin.height + (target.height - origin.height) * t)
            let result = placement.frame(for: requested, actualSize: CGSize(width: max(913, requested.width), height: requested.height),
                                         origin: origin, progress: t)
            XCTAssertGreaterThanOrEqual(result.minX, previous.minX - 0.001)
            XCTAssertLessThan(abs(result.minX - previous.minX), 7)
            previous = result
        }
        XCTAssertEqual(previous.minX, 490, accuracy: 0.001)
    }

    func testMaximumAndAspectRatioSizesKeepTheRightEdgeAndVerticalCenter() {
        let target = CGRect(x: 702, y: 29, width: 701, height: 869)
        for size in [CGSize(width: 600, height: 400), CGSize(width: 600, height: 450)] {
            let result = placement(for: target).frame(for: target, actualSize: size, origin: screen, progress: 1)
            XCTAssertEqual(result.maxX, screen.maxX)
            XCTAssertEqual(result.midY, screen.midY, accuracy: 0.5)
            XCTAssertEqual(result.size, size)
        }
    }

    func testCenteredLayoutCentersBothConstrainedDimensions() {
        let target = CGRect(x: 351, y: 129, width: 702, height: 669)
        let result = placement(for: target).frame(for: target, actualSize: CGSize(width: 913, height: 400), origin: screen, progress: 1)
        XCTAssertEqual(result.midX, target.midX, accuracy: 0.5)
        XCTAssertEqual(result.midY, target.midY, accuracy: 0.5)
    }

    func testDockInsetsAndNegativeDisplayCoordinatesUseTheProvidedWorkArea() {
        let screens = [CGRect(x: 45, y: 29, width: 1395, height: 869), screen,
                       CGRect(x: 0, y: 29, width: 1440, height: 831),
                       CGRect(x: -1600, y: -870, width: 1600, height: 900)]
        for screen in screens {
            let target = CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)
            let result = placement(for: target, screen: screen).frame(for: target, actualSize: CGSize(width: 913, height: 600), origin: screen, progress: 1)
            XCTAssertEqual(result.maxX, screen.maxX)
            XCTAssertEqual(result.midY, screen.midY, accuracy: 0.5)
        }
    }

    func testInitiallyOutOfBoundsWindowIsNotClippedOnItsFirstFrame() {
        let origin = CGRect(x: 600, y: 29, width: 913, height: 700)
        let target = CGRect(x: 702, y: 29, width: 701, height: 869)
        let placement = placement(for: target)
        XCTAssertEqual(placement.frame(for: origin, actualSize: origin.size, origin: origin, progress: 0), origin)
        let final = placement.frame(for: target, actualSize: CGSize(width: 913, height: 869), origin: origin, progress: 1)
        XCTAssertEqual(final.maxX, screen.maxX)
    }

    func testGapCorrectionMatchesNormalWindowBounds() {
        let result = WindowFrameBounds.constrained(CGRect(x: 1000, y: 0, width: 600, height: 500), to: screen, gap: 10)
        XCTAssertEqual(result.origin, CGPoint(x: 793, y: 39))
        XCTAssertTrue(WindowFrameBounds.constrained(.null, to: screen, gap: 10).isNull)
    }

    func testFinalFrameIsAppliedBeforeCleanupAndOnlyOnce() {
        var events: [String] = []
        let destination = CGRect(x: 700, y: 29, width: 700, height: 869)
        let animation = WindowFrameAnimation(from: .zero, to: destination, startTime: 0, duration: 0.34,
                                             write: { _, _ in events.append("tick"); return true },
                                             finalize: { frame in XCTAssertEqual(frame, destination); events.append("final") },
                                             cleanup: { events.append("cleanup") },
                                             completion: { _ in events.append("completion") })
        animation.tick(at: 0.1)
        animation.tick(at: 0.5)
        animation.finish()
        XCTAssertEqual(events, ["tick", "final", "cleanup", "completion"])
    }

    func testCancellationDoesNotWriteTheDestination() {
        var events: [String] = []
        let animation = WindowFrameAnimation(from: .zero, to: screen, startTime: 0, duration: 0.34,
                                             write: { _, _ in true },
                                             finalize: { _ in events.append("final") },
                                             cleanup: { events.append("cleanup") },
                                             completion: { _ in events.append("completion") })
        animation.cancel()
        animation.finish()
        XCTAssertEqual(events, ["cleanup"])
    }
}

final class WindowAnimationSettlementRoundingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func target(gap: Float = 7) -> CGRect {
        GapCalculation.applyGaps(CGRect(x: 500, y: 0, width: 500, height: 800),
                                 sharedEdges: .left, gapSize: gap)
    }

    private func placement(gap: CGFloat = 7) -> WindowAnimationPlacement {
        WindowAnimationPlacement(screenFrame: screen, sharedEdges: .right,
                                 constrainToScreen: true, gap: gap)
    }

    func testOddGapCompletesAfterOneRoundedPositionWrite() {
        let target = target()
        let actual = CGRect(x: 504, y: 7, width: 490, height: 786)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        let first = settlement.observe(ax: actual, server: actual, destination: target,
                                       placement: placement(), origin: actual, at: 1.0 / 60)
        guard case .align(let requested) = first else { return XCTFail("Expected an exact final position write") }
        XCTAssertEqual(requested.origin, target.origin)
        let second = settlement.observe(ax: actual, server: actual, destination: target,
                                        placement: placement(), origin: actual, at: 2.0 / 60)
        guard case .complete(let achieved) = second else { return XCTFail("Rounded placement must not enter a retry loop") }
        XCTAssertEqual(achieved, actual)
    }

    func testFractionalGapAcceptsHalfPointQuantizationAfterExactWrite() {
        let target = target(gap: 7.5)
        let actual = CGRect(x: 504, y: 7.5, width: 489, height: 785)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        _ = settlement.observe(ax: actual, server: actual, destination: target,
                               placement: placement(gap: 7.5), origin: actual, at: 1.0 / 60)
        let result = settlement.observe(ax: actual, server: actual, destination: target,
                                        placement: placement(gap: 7.5), origin: actual, at: 2.0 / 60)
        guard case .complete(let achieved) = result else { return XCTFail("Expected a verified rounded placement") }
        XCTAssertEqual(achieved, actual)
    }

    func testExactFractionalPositionIsUsedWhenAppAcceptsIt() {
        let target = target()
        let before = CGRect(x: 504, y: 7, width: 490, height: 786)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        let first = settlement.observe(ax: before, server: before, destination: target,
                                       placement: placement(), origin: before, at: 1.0 / 60)
        guard case .align(let requested) = first else { return XCTFail("Expected exact alignment") }
        let result = settlement.observe(ax: requested, server: requested, destination: target,
                                        placement: placement(), origin: before, at: 2.0 / 60)
        guard case .complete(let achieved) = result else { return XCTFail("Expected the accepted exact position") }
        XCTAssertEqual(achieved.origin, target.origin)
    }

    func testDisagreeingServerGeometryDoesNotEstablishRounding() {
        let target = target()
        let actual = CGRect(x: 504, y: 7, width: 490, height: 786)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        let first = settlement.observe(ax: actual, server: actual, destination: target,
                                       placement: placement(), origin: actual, at: 1.0 / 60)
        guard case .align(let requested) = first else { return XCTFail("Expected exact alignment") }
        let result = settlement.observe(ax: actual, server: requested, destination: target,
                                        placement: placement(), origin: actual, at: 2.0 / 60)
        if case .complete = result { XCTFail("Different AX and server positions can still be in flight") }
    }

    func testIntegerTargetStillRequiresExactPosition() {
        let target = CGRect(x: 503, y: 7, width: 490, height: 786)
        let actual = target.offsetBy(dx: 1, dy: 0)
        var settlement = WindowAnimationSettlement(startedAt: 0, alignmentTolerance: 0.001)
        for step in 1...3 {
            let result = settlement.observe(ax: actual, server: actual, destination: target,
                                            placement: placement(), origin: actual, at: Double(step) / 60)
            if case .complete = result { XCTFail("A full-point residual must still be corrected") }
        }
    }
}

final class WindowAnimationRequestCancellationTests: XCTestCase {
    private final class QueuedWindow: AccessibilityElement {
        private(set) var minimumSizeReads = 0

        init() { super.init(AXUIElementCreateApplication(getpid())) }
        override var windowId: CGWindowID? { .max }
        override var pid: pid_t? { getpid() }
        override var bundleIdentifier: String? { nil }
        override var minimumSize: CGSize? {
            minimumSizeReads += 1
            return nil
        }
    }

    func testTimedOutLookupCancelsWithoutMainThreadPlacementFallback() throws {
        try assertLookupCompletion(.timedOut, cancels: true)
    }

    func testObsoleteLookupCancelsWithoutMainThreadPlacementFallback() throws {
        try assertLookupCompletion(.cancelled, cancels: true)
    }

    func testUnavailableLookupPreservesOrdinaryPlacementFallback() throws {
        try assertLookupCompletion(.unavailable, cancels: false)
    }

    private func assertLookupCompletion(_ result: WindowAccessibilityLookup.Result, cancels: Bool) throws {
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer { Defaults.experimentalWindowAnimations.enabled = saved }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by accessibility settings")
        let finished = expectation(description: "Lookup delivered its terminal callback")
        let executor = WindowAnimator(lookupWindow: { _, _, _, _, _ in
            XCTAssertFalse(Thread.isMainThread)
            return result
        })
        let window = QueuedWindow()
        var cancellations = 0
        var completions = 0
        executor.animate(window, to: CGRect(x: 100, y: 100, width: 500, height: 400),
                         duration: 0.18, resizeOnly: false, releasedSnap: false, placement: nil,
                         profile: .standard, offset: { .zero }, curve: WindowAnimationCurve.value,
                         cancellation: {
                             XCTAssertTrue(Thread.isMainThread)
                             cancellations += 1
                             finished.fulfill()
                         }) { frame in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(frame.isNull)
            completions += 1
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(cancellations, cancels ? 1 : 0)
        XCTAssertEqual(completions, cancels ? 0 : 1)
        XCTAssertNil(executor.destination(for: window))
        XCTAssertEqual(window.minimumSizeReads, 0)
    }

    func testQueuedAnimationDoesNotReadMinimumSizeBeforeWorkerCanStart() throws {
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer { Defaults.experimentalWindowAnimations.enabled = saved }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by accessibility settings")

        let queue = DispatchQueue(label: "RectangleTests.Animation")
        let executor = WindowAnimator(queue: queue)
        let workerStarted = expectation(description: "Worker is occupied")
        let workerDrained = expectation(description: "Cancelled preparation drained")
        let release = DispatchSemaphore(value: 0)
        queue.async {
            workerStarted.fulfill()
            _ = release.wait(timeout: .now() + 2)
        }
        wait(for: [workerStarted], timeout: 1)
        let window = QueuedWindow()
        let destination = CGRect(x: 100, y: 100, width: 500, height: 400)
        var cancellations = 0
        var completions = 0
        executor.animate(window, to: destination, duration: 0.18, resizeOnly: false, releasedSnap: false,
                         placement: nil, profile: .standard, offset: { .zero }, curve: WindowAnimationCurve.value,
                         cancellation: { cancellations += 1 }) { _ in completions += 1 }
        XCTAssertEqual(executor.destination(for: window), destination)
        XCTAssertEqual(window.minimumSizeReads, 0, "Optional AX metadata must never be queried through the main-thread handle")
        executor.cancel()
        queue.async { workerDrained.fulfill() }
        release.signal()
        wait(for: [workerDrained], timeout: 1)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(window.minimumSizeReads, 0)
    }

    func testCancellationRunsCleanupOnceAfterInvalidatingWrites() {
        var cancellations = 0
        var request: WindowAnimationRequest!
        request = WindowAnimationRequest(cancellation: {
            XCTAssertFalse(request.isCurrent)
            cancellations += 1
        })
        XCTAssertTrue(request.isCurrent)
        request.cancel()
        request.cancel()
        request.complete()
        XCTAssertEqual(cancellations, 1)
    }

    func testCompletedRequestDoesNotRunCancellationCleanup() {
        var cancellations = 0
        let request = WindowAnimationRequest(cancellation: { cancellations += 1 })
        request.complete()
        request.cancel()
        XCTAssertFalse(request.isCurrent)
        XCTAssertEqual(cancellations, 0)
    }

    func testSupersededPendingWriteRunsOnlyCancellationCleanup() throws {
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer { Defaults.experimentalWindowAnimations.enabled = saved }
        try XCTSkipUnless(WindowAnimator.enabled, "Animations disabled by accessibility settings")
        let queue = DispatchQueue(label: "RectangleTests.Animation")
        let executor = WindowAnimator(queue: queue)
        let workerStarted = expectation(description: "Worker is occupied")
        let cancelled = expectation(description: "Pending placement was cancelled")
        let release = DispatchSemaphore(value: 0)
        queue.async {
            workerStarted.fulfill()
            _ = release.wait(timeout: .now() + 2)
        }
        wait(for: [workerStarted], timeout: 1)
        var completions = 0
        executor.animate(QueuedWindow(), to: CGRect(x: 20, y: 20, width: 600, height: 400)) { _ in
            XCTFail("A superseded animation must not complete")
        }
        executor.afterPendingWrites(cancellation: { cancelled.fulfill() }) { completions += 1 }
        executor.cancel()
        release.signal()
        wait(for: [cancelled], timeout: 1)
        XCTAssertEqual(completions, 0)
    }
}

@MainActor
final class FootprintGeometrySynchronizationTests: XCTestCase {
    func testColdAndRepeatedPreviewKeepsMaterialInsideSurface() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let blur = Defaults.footprintBlur.toCodable()
        let alpha = Defaults.footprintAlpha.value
        // A round trip through toCodable() would save an unset alpha as an explicit 0.
        let storedAlpha = UserDefaults.standard.object(forKey: Defaults.footprintAlpha.key)
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintBlur.load(from: blur)
            Defaults.footprintAlpha.value = alpha
            UserDefaults.standard.set(storedAlpha, forKey: Defaults.footprintAlpha.key)
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.footprintAlpha.value = 0.3
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        for blurred in [true, false] {
            Defaults.footprintBlur.enabled = blurred
            let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
            defer { window.close() }
            let surface = try XCTUnwrap(window.contentView?.subviews.last)
            let material = try XCTUnwrap(surface.subviews.first)
            for _ in 0..<2 {
                window.showPreview(in: target, from: CGPoint(x: target.minX + 4, y: target.midY), duration: 0.24)
                let until = CACurrentMediaTime() + 0.32
                while CACurrentMediaTime() < until {
                    try await Task.sleep(nanoseconds: 8_000_000)
                    let bounds = surface.layer?.presentation()?.bounds ?? surface.bounds
                    let inner = material.layer?.presentation()?.frame ?? material.frame
                    XCTAssertEqual(inner.width, bounds.width, accuracy: 1)
                    XCTAssertEqual(inner.height, bounds.height, accuracy: 1)
                }
                let settlementDeadline = CACurrentMediaTime() + 2
                while window.isAnimating && CACurrentMediaTime() < settlementDeadline {
                    try await Task.sleep(nanoseconds: 8_000_000)
                }
                XCTAssertEqual(surface.frame.width, target.width, accuracy: 1)
                XCTAssertEqual(surface.frame.height, target.height, accuracy: 1)
                XCTAssertFalse(window.isAnimating)
                window.orderOut(nil)
                try await Task.sleep(nanoseconds: 30_000_000)
            }
        }
    }

    func testRetargetAndCloseDoNotLeavePreviewGeometryRunning() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let left = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        window.showPreview(in: left, from: CGPoint(x: left.minX + 4, y: left.midY), duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        window.movePreview(to: left.offsetBy(dx: left.width, dy: 0), duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        window.close()
        let surface = try XCTUnwrap(window.contentView?.subviews.last)
        let closedFrame = surface.frame
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(surface.frame, closedFrame)
        XCTAssertFalse(window.realIsVisible)
        XCTAssertFalse(window.isAnimating)
    }
}

final class WindowMoveAnimationOwnProcessTests: XCTestCase {
    private final class TestWindow: AccessibilityElement {
        private let processIdentifier: pid_t
        init(pid: pid_t) {
            processIdentifier = pid
            super.init(AXUIElementCreateApplication(pid))
        }
        override var pid: pid_t? { processIdentifier }
        override var windowId: CGWindowID? { 1 }
        override func isResizable() -> Bool { true }
    }

    func testRectangleOwnWindowsMoveWithoutAnimating() throws {
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer { Defaults.experimentalWindowAnimations.enabled = saved }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by settings or accessibility")
        let screen = try XCTUnwrap(NSScreen.main, "Requires a screen")

        let own = TestWindow(pid: getpid())
        let other = TestWindow(pid: 1)
        let target = CGRect(x: 100, y: 100, width: 400, height: 300)
        let calcResult = WindowCalculationResult(rect: target, screen: screen, resultingAction: .leftHalf)
        func move(_ window: AccessibilityElement) -> WindowMoveAnimation? {
            WindowMoveAnimation.forMove(of: window, action: .leftHalf, calcResult: calcResult,
                                        screenFrame: screen.visibleFrame, isFixedSize: false,
                                        isMovedAcrossDisplays: false, source: .keyboardShortcut)
        }

        XCTAssertNil(move(own))
        XCTAssertNil(WindowMoveAnimation.forRestore(to: target, of: own, source: .keyboardShortcut))
        XCTAssertNotNil(move(other))
        XCTAssertNotNil(WindowMoveAnimation.forRestore(to: target, of: other, source: .keyboardShortcut))
    }
}
