import Cocoa
import XCTest
@testable import Rectangle

final class SnappedWindowFitProviderTests: XCTestCase {
    private let notifications = NotificationCenter()
    private let session = SnappedWindowFitSession(observeWorkspace: false, verify: { _, _ in true })

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

    func testRejectedRequestPreservesEarlierAcceptedPlacementAsAnAnchor() throws {
        let provider = makeProvider { _, _ in .noRoom }
        let earlier = try request(.leftHalf, id: 1)
        let incoming = try request(.rightHalf, id: 2)
        XCTAssertNil(provider.delegate(for: earlier))
        accept(earlier)
        stageVerifiedAnchor()
        postIntent(incoming)
        XCTAssertEqual(provider.delegate(for: incoming)?.acceptsPlacement, false)
        XCTAssertFalse(session.hasPotentialAnchor)
        settle(earlier)
        XCTAssertTrue(session.hasPotentialAnchor)
    }

    func testMinimizeClearsStagedAndLiveAnchorsAndExcludesLateSettlement() throws {
        let provider = makeProvider { _, _ in XCTFail("Minimize consumed this anchor"); return .noRoom }
        let earlier = try request(.leftHalf, id: 1)
        let incoming = try request(.rightHalf, id: 2)
        _ = provider.delegate(for: earlier)
        accept(earlier)
        stageVerifiedAnchor()
        postIntent(incoming)
        session.record(anchor())

        Notification.Name.windowActionWillExecute.post(center: notifications)

        XCTAssertFalse(session.hasPotentialAnchor)
        settle(earlier)
        XCTAssertFalse(session.hasPotentialAnchor)
        XCTAssertNil(provider.delegate(for: incoming))
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
            _ = provider.delegate(for: snap)
            accept(snap)
            settle(snap)
            XCTAssertEqual(session.hasPotentialAnchor, eligible, "Source \(source)")
        }
    }

    func testTitleBarAndKeyboardCanConsumeAnAnchorWithoutRearmingIt() throws {
        let provider = makeProvider { request, opportunity in
            .fit(SnappedWindowFit(target: request.calcResult.rect.screenFlipped, neighbor: opportunity))
        }
        for source: ExecutionSource in [.titleBar, .keyboardShortcut] {
            let incoming = try request(.rightHalf, id: 2, source: source)
            stageVerifiedAnchor()
            XCTAssertNotNil(provider.delegate(for: incoming))
            accept(incoming)
            settle(incoming)
            XCTAssertFalse(session.hasPotentialAnchor)
        }
    }

    func testNeighborChangeCanEscalateToDisplayChangeWhileCancellationDrains() throws {
        var neighborIsCurrent = true
        let condition = try placementCondition { neighborIsCurrent }
        let anchorChanged = expectation(description: "Detected moved or closed neighbor")
        var reasons: [WindowPlacementInvalidation] = []
        condition.whilePending { reason in
            reasons.append(reason)
            if reason == .anchorChanged { anchorChanged.fulfill() }
        }
        neighborIsCurrent = false
        wait(for: [anchorChanged], timeout: 2)
        XCTAssertEqual(condition.invalidation, .anchorChanged)
        Notification.Name.configImported.post(center: notifications)
        NSApplication.didChangeScreenParametersNotification.post(center: notifications)
        NSApplication.willTerminateNotification.post(center: notifications)
        Notification.Name.fitBesideSnappedWindowsChanged.post(center: notifications)
        XCTAssertEqual(reasons, [.anchorChanged, .environmentChanged])
        condition.stopMonitoring()
        XCTAssertEqual(condition.invalidation, .environmentChanged)
        XCTAssertFalse(condition.isValid())
    }

    func testTerminationPreventsPreferenceRollbackAndStopRemovesObservers() throws {
        let condition = try placementCondition { true }
        var reasons: [WindowPlacementInvalidation] = []
        condition.whilePending { reasons.append($0) }
        NSApplication.willTerminateNotification.post(center: notifications)
        Notification.Name.fitBesideSnappedWindowsChanged.post(center: notifications)
        XCTAssertEqual(reasons, [.environmentChanged])
        condition.stopMonitoring()
        let second = try placementCondition { true }
        second.whilePending { reasons.append($0) }
        Notification.Name.fitBesideSnappedWindowsChanged.post(center: notifications)
        second.stopMonitoring()
        NSApplication.didChangeScreenParametersNotification.post(center: notifications)
        XCTAssertEqual(second.invalidation, .anchorChanged)
        XCTAssertEqual(reasons, [.environmentChanged, .anchorChanged])
    }

    private func placementCondition(neighborIsCurrent: @escaping () -> Bool) throws -> WindowPlacementCondition {
        let provider = makeProvider(validateNeighbor: { _ in neighborIsCurrent() }) { request, opportunity in
            .fit(SnappedWindowFit(target: request.calcResult.rect.screenFlipped, neighbor: opportunity))
        }
        stageVerifiedAnchor()
        let incoming = try request(.rightHalf, id: 2)
        let condition = provider.delegate(for: incoming)?.placementCondition
        return try XCTUnwrap(condition, "Expected Fit to claim the incoming window")
    }

    private func makeProvider(validateNeighbor: @escaping (SnappedWindowFit) -> Bool = { _ in true },
                              resolve: @escaping (WindowMoveRequest, SnappedWindowFitOpportunity) -> SnappedWindowFit.Resolution) -> SnappedWindowFitProvider {
        SnappedWindowFitProvider(enabled: { true }, session: { [session] in session }, resolve: resolve,
                                 validateNeighbor: validateNeighbor, notifications: notifications)
    }

    private func anchor() -> SnappedWindowFitOpportunity {
        SnappedWindowFitOpportunity(id: 3, pid: getpid(), launch: 1, action: .leftHalf,
            frame: CGRect(x: 0, y: 0, width: 600, height: 800),
            bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), createdAt: ProcessInfo.processInfo.systemUptime)
    }

    private func stageVerifiedAnchor() {
        session.record(anchor())
        let verified = XCTNSPredicateExpectation(predicate: NSPredicate { [session] _, _ in session.current != nil }, object: nil)
        wait(for: [verified], timeout: 2)
    }

    private func request(_ action: WindowAction, id: CGWindowID, source: ExecutionSource = .keyboardShortcut) throws -> WindowMoveRequest {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = CGRect(x: 200, y: 200, width: 350, height: 350)
        let calculation = try XCTUnwrap(WindowCalculationFactory.calculationsByAction[action])
        let rect = calculation.calculateRect(RectCalculationParameters(window: Window(id: id, rect: frame),
            visibleFrameOfScreen: bounds, action: action, lastAction: nil)).rect
        return WindowMoveRequest(calcResult: WindowCalculationResult(rect: rect, screen: screen, resultingAction: action),
            windowId: id, isFixedSize: false, windowElement: AccessibilityElement(getpid()), action: action, source: source,
            currentFrame: frame, screenFrame: bounds, sourceScreens: UsableScreens(currentScreen: screen, numScreens: 1),
            destinationScreenIsCurrentScreen: true, lastRectangleAction: nil)
    }

    private func result(_ request: WindowMoveRequest) -> ResultParameters {
        ResultParameters(windowId: request.windowId, action: request.action, windowElement: request.windowElement,
            calcResult: request.calcResult, usableScreens: request.sourceScreens, visibleFrameOfScreen: request.screenFrame,
            source: request.source, isFixedSize: request.isFixedSize)
    }

    private func postIntent(_ request: WindowMoveRequest) {
        Notification.Name.windowActionWillExecute.post(center: notifications, object: ExecutionParameters(request.action,
            source: request.source, requestID: request.requestID))
    }

    private func accept(_ request: WindowMoveRequest) {
        Notification.Name.windowPlacementAccepted.post(center: notifications, object: WindowPlacementAcceptance(
            requestID: request.requestID, result: result(request)))
    }

    private func settle(_ request: WindowMoveRequest) {
        Notification.Name.windowPlacementSettled.post(center: notifications, object: WindowPlacementSettlement(
            requestID: request.requestID, result: result(request),
            achievedFrame: request.calcResult.rect.screenFlipped, alreadyAchieved: false))
    }
}
