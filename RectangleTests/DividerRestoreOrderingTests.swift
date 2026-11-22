import XCTest
@testable import Rectangle

final class DividerRestoreOrderingTests: XCTestCase {
    func testDeferredRestorePreservesUnrelatedSnap() throws {
        let priorAnimations = Defaults.experimentalWindowAnimations.enabled
        let priorCooperative = Defaults.cooperativeCornerResize.enabled
        let priorGap = Defaults.gapSize.value
        defer {
            Defaults.experimentalWindowAnimations.enabled = priorAnimations
            Defaults.cooperativeCornerResize.enabled = priorCooperative
            Defaults.gapSize.value = priorGap
        }
        Defaults.experimentalWindowAnimations.enabled = true
        Defaults.cooperativeCornerResize.enabled = false
        Defaults.gapSize.value = 0
        XCTAssertTrue(WindowAnimator.enabled, "This test requires window animations")

        let screen = try XCTUnwrap(NSScreen.main)
        let workArea = screen.adjustedVisibleFrame(true)
        let startingFrame = CGRect(x: workArea.minX + 80, y: workArea.minY + 80,
                                   width: 330, height: 260).screenFlipped
        let restoreFrame = startingFrame.offsetBy(dx: 40, dy: 40)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        try XCTUnwrap(WindowProcessIdentity.launchTime(for: process.processIdentifier))
        let a = TestWindow(id: 701, identity: 1, process: process.processIdentifier, frame: startingFrame)
        let b = TestWindow(id: 702, identity: 2, process: process.processIdentifier, frame: startingFrame)
        let c = TestWindow(id: 703, identity: 3, process: process.processIdentifier, frame: startingFrame)
        let history = WindowHistory()
        history.restoreRects[701] = restoreFrame

        let cLookupStarted = expectation(description: "C entered the animation worker")
        let releaseC = DispatchSemaphore(value: 0)
        let animator = WindowAnimator(lookupWindow: { _, id, _, _, _ in
            if id == 703 {
                cLookupStarted.fulfill()
                _ = releaseC.wait(timeout: .now() + 5)
            }
            return .unavailable
        })
        let fence = WindowWriteFence()
        let manager = WindowManager(screenDetection: FixedScreen(screen),
                                    windowAnimator: animator, windowHistory: history,
                                    delegateProviders: [], writeFence: fence)

        let dispatcher = WindowActionDispatcher(fence: fence)
        let aTarget = WindowWriteTarget(element: a, windowID: 701)
        let divider = fence.claim([aTarget, .init(element: b, windowID: 702)])
        let dividerEntered = expectation(description: "Divider issued a write on A")
        let dividerReturned = expectation(description: "Divider's issued write returned")
        let releaseDivider = DispatchSemaphore(value: 0)
        fence.perform(divider, work: {
            dividerEntered.fulfill()
            _ = releaseDivider.wait(timeout: .now() + 5)
            a.setFrame(startingFrame.offsetBy(dx: 60, dy: 0))
        }, completion: { _ in
            fence.finish(divider)
            dividerReturned.fulfill()
        })
        wait(for: [dividerEntered], timeout: 2)

        var aCompletions = 0
        let restoreFinished = expectation(description: "A restored")
        let restore = ExecutionParameters(.restore, windowElement: a, windowId: 701,
                                          source: .url, completion: {
            aCompletions += 1
            restoreFinished.fulfill()
        })
        dispatcher.prepare(restore, perform: manager.execute)
        XCTAssertEqual(aCompletions, 0)

        let cTerminated = expectation(description: "C delivered its terminal callback")
        var cCompletions = 0
        var cCancellations = 0
        dispatcher.prepare(ExecutionParameters(.topHalf, screen: screen, windowElement: c, windowId: 703,
                                            source: .url, completion: {
            cCompletions += 1
            cTerminated.fulfill()
        }, cancellation: {
            cCancellations += 1
            cTerminated.fulfill()
        }), perform: manager.execute)
        let cDestination = try XCTUnwrap(animator.destination(for: c))
        wait(for: [cLookupStarted], timeout: 2)
        XCTAssertEqual(a.frame, startingFrame)

        releaseDivider.signal()
        wait(for: [dividerReturned], timeout: 2)
        XCTAssertEqual(cCancellations, 0, "Resuming Restore must preserve C's active animation")
        XCTAssertEqual(a.frame, restoreFrame, "Restore can settle while C's animation is active")
        releaseC.signal()
        wait(for: [restoreFinished, cTerminated], timeout: 2)
        XCTAssertEqual(aCompletions, 1)
        XCTAssertEqual(cCompletions, 1)
        XCTAssertEqual(cCancellations, 0)
        XCTAssertEqual(a.frame, restoreFrame)
        XCTAssertEqual(c.frame, cDestination)
        XCTAssertEqual(history.lastRectangleActions[703]?.rect, cDestination)
    }

    private final class FixedScreen: ScreenDetection {
        let screen: NSScreen

        init(_ screen: NSScreen) { self.screen = screen }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            UsableScreens(currentScreen: screen, numScreens: 1)
        }
    }

    private final class TestWindow: AccessibilityElement {
        private let id: CGWindowID
        private let process: pid_t
        private let frameLock = NSLock()
        private var currentFrame: CGRect

        init(id: CGWindowID, identity: pid_t, process: pid_t, frame: CGRect) {
            self.id = id
            self.process = process
            currentFrame = frame
            super.init(AXUIElementCreateApplication(identity))
        }

        override var pid: pid_t? { process }
        override var windowId: CGWindowID? { id }
        override var frame: CGRect {
            frameLock.lock()
            defer { frameLock.unlock() }
            return currentFrame
        }
        override var isSheet: Bool? { false }
        override var isSystemDialog: Bool? { false }
        override var minimumSize: CGSize? { nil }
        override var bundleIdentifier: String? { nil }
        override func isResizable() -> Bool { true }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            frameLock.lock()
            defer { frameLock.unlock() }
            currentFrame = frame
        }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: ImmediateWindowPlacement? = nil) {
            setFrame(target)
        }
    }
}
