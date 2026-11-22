import Cocoa
import XCTest
@testable import Rectangle

final class SnappedWindowFitProviderTests: XCTestCase {
    private let notifications = NotificationCenter()
    private let session = SnappedWindowFitSession(observeWorkspace: false)

    override func setUp() {
        super.setUp()
        let setting = Defaults.fitBesideSnappedWindows
        let savedValue = setting.enabled
        let savedObject = UserDefaults.standard.object(forKey: setting.key)
        addTeardownBlock {
            setting.enabled = savedValue
            UserDefaults.standard.set(savedObject, forKey: setting.key)
        }
        setting.enabled = true
    }

    func testRejectedCommandAllowsTheEarlierAcceptedSnapToEstablishAReference() throws {
        let provider = makeProvider { _, _ in .noRoom }
        let earlier = try request(.leftHalf, id: 1)
        let incoming = try request(.rightHalf, id: 2)
        XCTAssertNil(provider.delegate(for: earlier))
        stageAnchor()
        postIntent(incoming)
        XCTAssertEqual(provider.delegate(for: incoming)?.acceptsPlacement, false)
        XCTAssertFalse(session.hasPotentialAnchor)
        complete(earlier)
        XCTAssertTrue(session.hasPotentialAnchor)
    }

    func testMinimizeClearsStagedAndLiveAnchorsAndExcludesLateSettlement() throws {
        let provider = makeProvider { _, _ in XCTFail("Minimize consumed this anchor"); return .noRoom }
        let earlier = try request(.leftHalf, id: 1)
        let incoming = try request(.rightHalf, id: 2)
        XCTAssertNil(provider.delegate(for: earlier))
        stageAnchor()
        postIntent(incoming)
        session.record(anchor())

        Notification.Name.windowActionWillExecute.post(center: notifications)

        XCTAssertFalse(session.hasPotentialAnchor)
        complete(earlier)
        XCTAssertFalse(session.hasPotentialAnchor)
        _ = provider.delegate(for: incoming)
    }

    func testOnlyDragKeyboardAndMenuCanEstablishAnchors() throws {
        let provider = makeProvider { _, _ in XCTFail("No prior anchor"); return .unchanged }
        let sources: [(ExecutionSource, Bool)] = [
            (.dragToSnap, true), (.keyboardShortcut, true), (.menuItem, true),
            (.titleBar, false), (.url, false), (.newWindow, false)
        ]
        for (source, eligible) in sources {
            session.clear()
            let snap = try request(.leftHalf, id: 1, source: source)
            XCTAssertNil(provider.delegate(for: snap))
            complete(snap)
            XCTAssertEqual(session.hasPotentialAnchor, eligible, "Source \(source)")
        }
    }

    func testFittedPlacementCompletesTheReferenceOpportunity() throws {
        let provider = makeProvider { request, opportunity in
            .fit(SnappedWindowFit(target: request.calcResult.rect.screenFlipped, neighbor: opportunity))
        }
        for source: ExecutionSource in [.titleBar, .keyboardShortcut] {
            let incoming = try request(.rightHalf, id: 2, source: source)
            stageAnchor()
            let move = try XCTUnwrap(provider.delegate(for: incoming))
            complete(incoming, move: move)
            XCTAssertFalse(session.hasPotentialAnchor)
        }
    }

    func testAnAlreadyAchievedSnapCanEstablishAnAnchor() throws {
        let provider = makeProvider { _, _ in XCTFail("No prior anchor"); return .unchanged }
        let snap = try request(.leftHalf, id: 1, alreadyAchieved: true)

        XCTAssertNil(provider.delegate(for: snap))
        complete(snap)

        XCTAssertTrue(session.hasPotentialAnchor)
    }

    func testDeferredPlanningKeepsTheReferenceConsumedByItsOwnCommand() throws {
        var resolutions = 0
        let provider = makeProvider { _, reference in
            resolutions += 1
            XCTAssertEqual(reference.id, 3)
            return .unchanged
        }
        let waiting = try request(.rightHalf, id: 2)
        stageAnchor()
        postIntent(waiting)
        session.record(SnappedWindowFitOpportunity(id: 4, pid: getpid(), launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 600, height: 800), bounds: CGRect(x: 0, y: 0, width: 1200, height: 800)))
        postIntent(try request(.topHalf, id: 5))
        XCTAssertNil(provider.delegate(for: waiting))
        XCTAssertNil(provider.delegate(for: waiting))
        XCTAssertEqual(resolutions, 2)
    }

    func testLateFittedCompletionPreservesTheNewerReference() throws {
        let provider = makeProvider { request, reference in
            .fit(SnappedWindowFit(target: request.calcResult.rect.screenFlipped, neighbor: reference))
        }
        let fitted = try request(.rightHalf, id: 2)
        stageAnchor()
        postIntent(fitted)
        let move = try XCTUnwrap(provider.delegate(for: fitted))
        let newer = try request(.leftHalf, id: 6)
        postIntent(newer)
        XCTAssertNil(provider.delegate(for: newer))
        complete(newer)
        XCTAssertEqual(session.current?.id, 6)
        complete(fitted, move: move)
        XCTAssertEqual(session.current?.id, 6)
    }

    func testOlderSnapCompletionDoesNotRearmAfterRestoreIntent() throws {
        let provider = makeProvider { _, _ in .unchanged }
        let earlier = try request(.leftHalf, id: 1)
        postIntent(earlier)
        XCTAssertNil(provider.delegate(for: earlier))
        Notification.Name.windowActionWillExecute.post(center: notifications, object: ExecutionParameters(.restore))
        complete(earlier)
        XCTAssertNil(session.current)
    }

    private func makeProvider(resolve: @escaping (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution) -> SnappedWindowFitProvider {
        SnappedWindowFitProvider(enabled: { true }, session: { [session] in session }, resolve: resolve,
                                 notifications: notifications)
    }

    private func anchor() -> SnappedWindowFitOpportunity {
        SnappedWindowFitOpportunity(id: 3, pid: getpid(), launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 600, height: 800),
            bounds: CGRect(x: 0, y: 0, width: 1200, height: 800))
    }

    private func stageAnchor() {
        session.record(anchor())
        XCTAssertNotNil(session.current)
    }

    private func request(_ action: WindowAction, id: CGWindowID, source: ExecutionSource = .keyboardShortcut,
                         alreadyAchieved: Bool = false) throws -> WindowMoveRequest {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = CGRect(x: 200, y: 200, width: 350, height: 350)
        let calculation = try XCTUnwrap(WindowCalculationFactory.calculationsByAction[action])
        let rect = calculation.calculateRect(RectCalculationParameters(window: Window(id: id, rect: frame),
            visibleFrameOfScreen: bounds, action: action, lastAction: nil)).rect
        return WindowMoveRequest(calcResult: WindowCalculationResult(rect: rect, screen: screen, resultingAction: action),
            windowId: id, isFixedSize: false, windowElement: AccessibilityElement(getpid()), action: action, source: source,
            currentFrame: alreadyAchieved ? rect : frame, screenFrame: bounds, sourceScreens: UsableScreens(currentScreen: screen, numScreens: 1),
            destinationScreenIsCurrentScreen: true, lastRectangleAction: nil)
    }

    private func postIntent(_ request: WindowMoveRequest) {
        Notification.Name.windowActionWillExecute.post(center: notifications, object: ExecutionParameters(request.action,
            source: request.source, identity: request.identity))
    }

    private func complete(_ request: WindowMoveRequest, move: WindowManagerDelegate? = nil) {
        let result = ResultParameters(windowId: request.windowId, action: request.action,
            windowElement: request.windowElement, calcResult: move?.calcResult ?? request.calcResult,
            usableScreens: request.sourceScreens, visibleFrameOfScreen: request.screenFrame,
            source: request.source, isFixedSize: request.isFixedSize)
        Notification.Name.windowActionCompleted.post(center: notifications,
            object: WindowActionCompletion(result: result, achievedFrame: result.calcResult.rect.screenFlipped, identity: request.identity))
    }
}
