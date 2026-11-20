/// SnappingTests.swift

import XCTest
@testable import Rectangle

final class AccessibilityWindowResolutionTests: XCTestCase {
    // These wrappers are identity tokens only; the resolver never contacts AX.
    private let element = AccessibilityElement(AXUIElementCreateApplication(42))
    private let parent = AccessibilityElement(AXUIElementCreateApplication(43))

    func testStandardWindowWithLegacyTextFieldRoleResolvesToItself() {
        // Emacs 28 reports AXTextField/AXStandardWindow and no AXWindow attribute.
        let resolved = AccessibilityElement.resolveWindowElement(element, isWindow: false,
            containingWindow: { nil }, subrole: { .standardWindow })
        XCTAssertEqual(resolved, element)
    }

    func testWindowRoleResolvesToItselfWithoutReadingOtherAttributes() {
        let resolved = AccessibilityElement.resolveWindowElement(element, isWindow: true,
            containingWindow: {
                XCTFail("AXWindow must not be read for a window element")
                return nil
            }, subrole: {
                XCTFail("AXSubrole must not be read for a window element")
                return nil
            })
        XCTAssertEqual(resolved, element)
    }

    func testTextFieldChildResolvesToItsContainingWindowBeforeUsingSubrole() {
        let resolved = AccessibilityElement.resolveWindowElement(element, isWindow: false,
            containingWindow: { self.parent }, subrole: {
                XCTFail("A child with AXWindow must use its containing window")
                return .standardWindow
            })
        XCTAssertEqual(resolved, parent)
        XCTAssertNotEqual(resolved, element)
    }

    func testOrdinaryTextFieldWithoutContainingWindowDoesNotBecomeAWindow() {
        for isWindow in [false, nil] as [Bool?] {
            XCTAssertNil(AccessibilityElement.resolveWindowElement(element, isWindow: isWindow,
                containingWindow: { nil }, subrole: { nil }))
        }
    }

    func testFallbackOnlyRecognizesTheStandardWindowSubrole() {
        for subrole in [NSAccessibility.Subrole.dialog, .systemDialog, .floatingWindow, .systemFloatingWindow] {
            XCTAssertNil(AccessibilityElement.resolveWindowElement(element, isWindow: false,
                containingWindow: { nil }, subrole: { subrole }), subrole.rawValue)
        }
    }
}

final class EarlySnapEdgeTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let margins = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)

    private func direction(_ x: CGFloat, _ y: CGFloat, earlyDistance: CGFloat = 20,
                           screens: [CGRect] = []) -> Directional? {
        SnapEdgeDetection.direction(at: CGPoint(x: x, y: y), in: frame,
                                    screens: [frame] + screens, margins: margins, cornerSize: 20, earlyDistance: earlyDistance)
    }

    func testDisabledKeepsExistingEdgeThresholds() {
        XCTAssertNil(direction(10, 450, earlyDistance: 0))
        XCTAssertNil(direction(1430, 450, earlyDistance: 0))
        XCTAssertNil(direction(720, 890, earlyDistance: 0))
        XCTAssertNil(direction(720, 10, earlyDistance: 0))
        XCTAssertEqual(direction(4, 450, earlyDistance: 0), .l)
        XCTAssertEqual(direction(1436, 450, earlyDistance: 0), .r)
        XCTAssertEqual(direction(720, 896, earlyDistance: 0), .t)
        XCTAssertEqual(direction(720, 4, earlyDistance: 0), .b)
    }

    func testEarlyEdgesAndWithdrawal() {
        XCTAssertEqual(direction(19, 450), .l)
        XCTAssertEqual(direction(1421, 450), .r)
        XCTAssertEqual(direction(720, 881), .t)
        XCTAssertEqual(direction(720, 19), .b)
        XCTAssertNil(direction(20, 450))
        XCTAssertNil(direction(1420, 450))
        XCTAssertNil(direction(720, 880))
        XCTAssertNil(direction(720, 20))
        XCTAssertNil(direction(-1, 450))
        XCTAssertNil(direction(1441, 450))
    }

    func testCornersKeepTheirOriginalSizeAndPriority() {
        for earlyDistance in [CGFloat(0), 20] {
            XCTAssertEqual(direction(24, 876, earlyDistance: earlyDistance), .tl)
            XCTAssertEqual(direction(1416, 876, earlyDistance: earlyDistance), .tr)
            XCTAssertEqual(direction(24, 24, earlyDistance: earlyDistance), .bl)
            XCTAssertEqual(direction(1416, 24, earlyDistance: earlyDistance), .br)
            XCTAssertNil(direction(30, 870, earlyDistance: earlyDistance))
        }
        XCTAssertEqual(direction(10, 870), .l)
        XCTAssertEqual(direction(30, 890), .t)
    }

    func testSharedEdgesStayNarrowInAllDirections() {
        let screens = [CGRect(x: -1440, y: 0, width: 1440, height: 900),
                       CGRect(x: 1440, y: 0, width: 1440, height: 900),
                       CGRect(x: 0, y: 900, width: 1440, height: 900),
                       CGRect(x: 0, y: -900, width: 1440, height: 900)]
        XCTAssertNil(direction(10, 450, screens: screens))
        XCTAssertNil(direction(1430, 450, screens: screens))
        XCTAssertNil(direction(720, 890, screens: screens))
        XCTAssertNil(direction(720, 10, screens: screens))
        XCTAssertEqual(direction(4, 450, screens: screens), .l)
        XCTAssertEqual(direction(1436, 450, screens: screens), .r)
        XCTAssertEqual(direction(720, 896, screens: screens), .t)
        XCTAssertEqual(direction(720, 4, screens: screens), .b)
    }

    func testPartialSharedEdgeAndNegativeDisplayCoordinates() {
        let shorter = CGRect(x: 1440, y: 200, width: 800, height: 500)
        XCTAssertNil(direction(1430, 450, screens: [shorter]))
        XCTAssertEqual(direction(1430, 100, screens: [shorter]), .r)
        XCTAssertEqual(direction(1430, 800, screens: [shorter]), .r)
        let portrait = CGRect(x: -900, y: -300, width: 900, height: 1440)
        XCTAssertEqual(SnapEdgeDetection.direction(at: CGPoint(x: -890, y: 450), in: portrait,
                       screens: [portrait, frame], margins: margins, cornerSize: 20, earlyDistance: 20), .l)
        XCTAssertNil(SnapEdgeDetection.direction(at: CGPoint(x: -10, y: 450), in: portrait,
                     screens: [portrait, frame], margins: margins, cornerSize: 20, earlyDistance: 20))
    }

    func testEarlyDistanceOverridesLargerOuterMarginsInAllDirections() {
        let custom = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        let points: [(CGPoint, Directional)] = [(CGPoint(x: 30, y: 450), .l),
                                               (CGPoint(x: 1410, y: 450), .r),
                                               (CGPoint(x: 720, y: 870), .t),
                                               (CGPoint(x: 720, y: 30), .b)]
        for (point, expected) in points {
            XCTAssertNil(SnapEdgeDetection.direction(at: point, in: frame, screens: [frame],
                         margins: custom, cornerSize: 20, earlyDistance: 20))
            XCTAssertEqual(SnapEdgeDetection.direction(at: point, in: frame, screens: [frame],
                           margins: custom, cornerSize: 20, earlyDistance: 0), expected)
        }
    }

    func testCustomFractionalDistanceCanExpandOrReduceOuterMargins() {
        XCTAssertEqual(direction(32, 450, earlyDistance: 32.5), .l)
        XCTAssertNil(direction(32.5, 450, earlyDistance: 32.5))
        XCTAssertEqual(direction(2, 450, earlyDistance: 2.5), .l)
        XCTAssertNil(direction(2.5, 450, earlyDistance: 2.5))
        XCTAssertEqual(direction(4, 450, earlyDistance: -1), .l)
        XCTAssertNil(direction(10, 450, earlyDistance: -1))
    }

    func testCustomMarginsRemainOnSharedPortionOnly() {
        let custom = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
        let neighbor = CGRect(x: 1440, y: 200, width: 800, height: 500)
        XCTAssertEqual(SnapEdgeDetection.direction(at: CGPoint(x: 1410, y: 450), in: frame,
                       screens: [frame, neighbor], margins: custom, cornerSize: 20, earlyDistance: 20), .r)
        XCTAssertNil(SnapEdgeDetection.direction(at: CGPoint(x: 1410, y: 100), in: frame,
                     screens: [frame, neighbor], margins: custom, cornerSize: 20, earlyDistance: 20))
    }

    func testDisplayTopologyIsOnlyReadForEarlyEdgeCandidates() {
        var topologyReads = 0
        func screens() -> [CGRect] {
            topologyReads += 1
            return [frame, CGRect(x: 1440, y: 200, width: 800, height: 500)]
        }
        func detect(_ point: CGPoint, earlyDistance: CGFloat = 20) -> Directional? {
            SnapEdgeDetection.direction(at: point, in: frame, screens: screens(),
                                        margins: margins, cornerSize: 20, earlyDistance: earlyDistance)
        }

        for _ in 0..<100 {
            XCTAssertEqual(detect(CGPoint(x: 1436, y: 450), earlyDistance: 0), .r)
            XCTAssertNil(detect(CGPoint(x: 720, y: 450)))
            XCTAssertNil(detect(CGPoint(x: 1450, y: 450)))
            XCTAssertEqual(detect(CGPoint(x: 24, y: 876)), .tl)
        }
        XCTAssertEqual(topologyReads, 0)

        // The shared portion still stays narrow; the exposed portion expands.
        XCTAssertNil(detect(CGPoint(x: 1430, y: 450)))
        XCTAssertEqual(topologyReads, 1)
        XCTAssertEqual(detect(CGPoint(x: 1430, y: 100)), .r)
        XCTAssertEqual(topologyReads, 2)
    }

    func testSettingsRoundTripAndLiveManagerUpdate() throws {
        let saved = Defaults.snapBeforeReachingEdges.value
        let snapping = Defaults.windowSnapping.enabled
        let edgeDefaults = [Defaults.snapEdgeMarginTop, Defaults.snapEdgeMarginLeft,
                            Defaults.snapEdgeMarginBottom, Defaults.snapEdgeMarginRight, Defaults.cornerSnapAreaSize]
        let savedEdges = edgeDefaults.map(\.value)
        defer {
            Defaults.snapBeforeReachingEdges.value = saved
            Defaults.windowSnapping.enabled = snapping
            zip(edgeDefaults, savedEdges).forEach { $0.value = $1 }
        }
        edgeDefaults.forEach { $0.value = 5 }
        Defaults.cornerSnapAreaSize.value = 20
        Defaults.windowSnapping.enabled = false
        Defaults.snapBeforeReachingEdges.value = 0
        let manager = SnappingManager()
        let model = SnapAreaViewModel()
        // The rightmost display has an exposed right edge regardless of which display is main.
        let screen = try XCTUnwrap(NSScreen.screens.max { $0.frame.maxX < $1.frame.maxX })
        let location = CGPoint(x: screen.frame.maxX - 10, y: screen.frame.midY)
        XCTAssertNil(manager.directionalLocationOfCursor(loc: location, screen: screen))
        model.snapBeforeReachingEdges = true
        XCTAssertEqual(manager.directionalLocationOfCursor(loc: location, screen: screen), .r)
        XCTAssertEqual(Defaults.array.first { $0.key == "snapBeforeReachingEdges" }?.toCodable().double, 20)
        Defaults.snapBeforeReachingEdges.load(from: CodableDefault(double: 0))
        model.syncDefaults()
        XCTAssertFalse(model.snapBeforeReachingEdges)
        XCTAssertNil(manager.directionalLocationOfCursor(loc: location, screen: screen))
    }
    func testCustomDistanceSurvivesSettingsCreationAndImportSync() throws {
        let saved = Defaults.snapBeforeReachingEdges.toCodable()
        defer { Defaults.snapBeforeReachingEdges.load(from: saved) }
        Defaults.snapBeforeReachingEdges.value = 32.5
        let model = SnapAreaViewModel()
        XCTAssertTrue(model.snapBeforeReachingEdges)
        XCTAssertEqual(Defaults.snapBeforeReachingEdges.value, 32.5)
        model.snapBeforeReachingEdges = false
        XCTAssertEqual(Defaults.snapBeforeReachingEdges.value, 0)
        Defaults.snapBeforeReachingEdges.load(from: CodableDefault(double: 47.5))
        model.syncDefaults()
        XCTAssertTrue(model.snapBeforeReachingEdges)
        XCTAssertEqual(Defaults.snapBeforeReachingEdges.value, 47.5)
        let exported = Defaults.snapBeforeReachingEdges.toCodable()
        XCTAssertEqual(exported.double, 47.5)
        model.snapBeforeReachingEdges = false
        model.snapBeforeReachingEdges = true
        XCTAssertEqual(Defaults.snapBeforeReachingEdges.value, 20)
        Defaults.snapBeforeReachingEdges.load(from: exported)
        model.syncDefaults()
        XCTAssertEqual(Defaults.snapBeforeReachingEdges.value, 47.5)
    }
    func testSizeChangeUnsnapRestoreToggleMatchesDefault() {
        let saved = Defaults.unsnapRestoreFromSizeChange.toCodable()
        defer { Defaults.unsnapRestoreFromSizeChange.load(from: saved) }
        Defaults.unsnapRestoreFromSizeChange.enabled = nil
        let model = SnapAreaViewModel()
        XCTAssertTrue(model.unsnapRestoreFromSizeChange)
        model.unsnapRestoreFromSizeChange = false
        XCTAssertTrue(Defaults.unsnapRestoreFromSizeChange.userDisabled)
        model.unsnapRestoreFromSizeChange = true
        XCTAssertFalse(Defaults.unsnapRestoreFromSizeChange.userDisabled)
        Defaults.unsnapRestoreFromSizeChange.enabled = false
        model.syncDefaults()
        XCTAssertFalse(model.unsnapRestoreFromSizeChange)
    }

}

final class WindowDragGeometryTests: XCTestCase {
    private let initial = CGRect(x: -1983, y: -964, width: 1920, height: 1016)

    func testDetectsMovementWhileAccessibilityStillReportsTheInitialFrame() throws {
        let moved = initial.offsetBy(dx: 0, dy: 2)
        var accessibilityReads = 0
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: initial,
                                                        serverFrame: moved, accessibilityFrame: {
            accessibilityReads += 1
            return self.initial
        }))
        XCTAssertTrue(geometry.isMoving)
        XCTAssertTrue(geometry.movedWithoutResizing)
        XCTAssertEqual(geometry.currentFrame, moved)
        XCTAssertEqual(accessibilityReads, 0)
    }

    func testDifferentCoordinateSourcesDoNotCreateFalseMovement() throws {
        let accessibility = initial.offsetBy(dx: 1, dy: 1)
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: accessibility, initialServerFrame: initial,
                                                        serverFrame: initial, accessibilityFrame: { accessibility }))
        XCTAssertFalse(geometry.isMoving)
        XCTAssertFalse(geometry.isResizing)
    }

    func testUnavailableServerFrameFallsBackToAccessibilityBaseline() throws {
        let accessibility = initial.offsetBy(dx: 1, dy: 1)
        for unavailable in [nil, CGRect.null, CGRect.zero] as [CGRect?] {
            let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: accessibility, initialServerFrame: initial,
                                                            serverFrame: unavailable, accessibilityFrame: { accessibility }))
            XCTAssertFalse(geometry.isMoving)
            XCTAssertEqual(geometry.currentFrame, accessibility)
        }
    }

    func testServerFrameWithoutServerBaselineUsesAccessibility() throws {
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: nil,
                                                        serverFrame: initial.offsetBy(dx: 20, dy: 20),
                                                        accessibilityFrame: { self.initial }))
        XCTAssertFalse(geometry.isMoving)
    }

    func testResizingFromEitherCornerDoesNotTriggerRestore() throws {
        let frames = [CGRect(x: initial.minX, y: initial.minY, width: 1800, height: 900),
                      CGRect(x: initial.minX + 120, y: initial.minY + 100, width: 1800, height: 916)]
        for frame in frames {
            let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: initial,
                                                            serverFrame: frame, accessibilityFrame: { nil }))
            XCTAssertTrue(geometry.isResizing)
            XCTAssertFalse(geometry.isMoving)
            XCTAssertFalse(geometry.movedWithoutResizing)
        }
    }

    func testMovingAndChangingSizeAcrossDisplaysStillCountsAsMovement() throws {
        let geometry = try XCTUnwrap(WindowDragGeometry(initialFrame: initial, initialServerFrame: initial,
                                                        serverFrame: CGRect(x: 20, y: 30, width: 1400, height: 800),
                                                        accessibilityFrame: { nil }))
        XCTAssertTrue(geometry.isMoving)
        XCTAssertFalse(geometry.movedWithoutResizing)
    }

    func testMissingGeometryDoesNotCreateADrag() {
        XCTAssertNil(WindowDragGeometry(initialFrame: initial, initialServerFrame: nil,
                                        serverFrame: nil, accessibilityFrame: { nil }))
        XCTAssertNil(WindowDragGeometry(initialFrame: initial, initialServerFrame: nil,
                                        serverFrame: nil, accessibilityFrame: { .null }))
    }
}

final class DragRestorePlacementTests: XCTestCase {
    private let current = CGRect(x: -1983, y: -950, width: 1920, height: 1016)
    private let size = CGSize(width: 1100, height: 650)

    func testDisplayedFrameUsesTheOriginalGrabOffsetInsteadOfANewerMouseSample() {
        let initial = CGRect(x: -1983, y: -964, width: 1920, height: 1016)
        let displayed = initial.offsetBy(dx: 0, dy: 38)
        let reference = DragRestorePlacement.referenceCursor(current: displayed, initial: initial,
                                                              mouseDown: CGPoint(x: -255, y: -934),
                                                              fallback: CGPoint(x: -255, y: -858))
        XCTAssertEqual(reference, CGPoint(x: -255, y: -896))
        XCTAssertEqual(reference.y - displayed.minY, 30)
    }

    func testMissingMouseDownUsesTheAvailableCursorSample() {
        let cursor = CGPoint(x: -561, y: -920)
        XCTAssertEqual(DragRestorePlacement.referenceCursor(current: current, initial: current,
                                                            mouseDown: nil, fallback: cursor), cursor)
    }

    func testLeftGrabKeepsNativePosition() {
        let restored = DragRestorePlacement.frame(from: current, size: size, cursor: CGPoint(x: -1600, y: -920))
        XCTAssertEqual(restored.origin, current.origin)
        XCTAssertEqual(restored.size, size)
    }

    func testRightGrabMovesOnlyEnoughToKeepThePointerInside() {
        let cursor = CGPoint(x: -561, y: -920)
        let restored = DragRestorePlacement.frame(from: current, size: size, cursor: cursor)
        XCTAssertEqual(restored.minX, -1629)
        XCTAssertEqual(restored.maxX - cursor.x, 32)
        XCTAssertTrue(restored.contains(cursor))
        XCTAssertLessThan(restored.maxX, current.maxX)
    }

    func testNearbyGrabPointsDoNotSwitchToTheFarRightEdge() {
        let cutoff = current.minX + size.width - 32
        let left = DragRestorePlacement.frame(from: current, size: size, cursor: CGPoint(x: cutoff - 1, y: -920))
        let right = DragRestorePlacement.frame(from: current, size: size, cursor: CGPoint(x: cutoff + 1, y: -920))
        XCTAssertEqual(left.minX, current.minX)
        XCTAssertEqual(right.minX - left.minX, 1)
    }

    func testGrabAtTheFarRightDoesNotPushPastTheOriginalEdge() {
        let restored = DragRestorePlacement.frame(from: current, size: size,
                                                  cursor: CGPoint(x: current.maxX - 1, y: -920))
        XCTAssertEqual(restored.maxX, current.maxX)
    }

    func testGrowingFromAHalfScreenDoesNotReposition() {
        let half = CGRect(x: 400, y: 100, width: 800, height: 900)
        let restored = DragRestorePlacement.frame(from: half, size: size, cursor: CGPoint(x: 1190, y: 130))
        XCTAssertEqual(restored.origin, half.origin)
    }

    func testPlacementIsTheSameRelativeToEitherDisplay() {
        let cursor = CGPoint(x: -561, y: -920)
        let external = DragRestorePlacement.frame(from: current, size: size, cursor: cursor)
        let local = DragRestorePlacement.frame(from: current.offsetBy(dx: 2000, dy: 1000), size: size,
                                               cursor: CGPoint(x: cursor.x + 2000, y: cursor.y + 1000))
        XCTAssertEqual(local, external.offsetBy(dx: 2000, dy: 1000))
        XCTAssertEqual(DragRestorePlacement.frame(from: current, size: size, cursor: nil).origin, current.origin)
    }
}

final class DragRestoreReleaseTests: XCTestCase {
    private final class WindowElement: WindowAnimationElement {
        var currentFrame = CGRect(x: 120, y: 120, width: 800, height: 600)
        var writes: [CGRect] = []
        override var frame: CGRect { currentFrame }
        override func beginAnimatedAdjustment() -> () -> Void { {} }
        override func setAnimationFrame(_ frame: CGRect, resizeOnly: Bool = false) -> Bool { true }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            currentFrame.size = frame.size
            if adjustPosition { currentFrame.origin = frame.origin }
            writes.append(currentFrame)
        }
    }

    private final class Manager: SnappingManager {
        var restores = 0
        override func unsnapRestore(windowId: CGWindowID, currentRect: CGRect, cursorLoc: CGPoint?) {
            restores += 1
        }
        override func snapAreaContainingCursor(priorSnapArea: SnapArea?, at loc: CGPoint) -> SnapArea? { nil }
    }

    private func release(dragAlreadyDetected: Bool) throws -> Manager {
        let saved = Defaults.windowSnapping.enabled
        Defaults.windowSnapping.enabled = false
        defer { Defaults.windowSnapping.enabled = saved }
        let manager = Manager()
        manager.windowElement = WindowElement(AXUIElementCreateSystemWide())
        manager.windowId = .max
        manager.initialWindowRect = CGRect(x: 100, y: 100, width: 800, height: 600)
        manager.windowMoving = dragAlreadyDetected
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [],
                                                   timestamp: 1, windowNumber: 0, context: nil,
                                                   eventNumber: 1, clickCount: 1, pressure: 0))
        manager.handle(event: event)
        return manager
    }

    func testMouseUpDoesNotRestoreAgainWhenDisplayedSizeHasNotCaughtUp() throws {
        let manager = try release(dragAlreadyDetected: true)
        XCTAssertEqual(manager.restores, 0)
        XCTAssertFalse(manager.windowMoving)
        XCTAssertNil(manager.windowId)
        XCTAssertNil(manager.windowElement)
    }

    func testMouseUpStillRestoresAQuickDragThatHadNotBeenDetected() throws {
        let manager = try release(dragAlreadyDetected: false)
        XCTAssertEqual(manager.restores, 1)
        XCTAssertFalse(manager.windowMoving)
        XCTAssertNil(manager.initialWindowRect)
    }

    func testDirectAnimationWithoutServerIdentityCompletesOnceAndMouseUpDoesNotRepeatIt() throws {
        let animator = DirectWindowAnimator(enabled: { true }, automaticallyAdvances: false, environmentIsSafe: { true })
        let saved = Defaults.experimentalWindowAnimations.enabled
        Defaults.experimentalWindowAnimations.enabled = true
        defer {
            animator.finish()
            Defaults.experimentalWindowAnimations.enabled = saved
        }
        try XCTSkipUnless(WindowAnimator.enabled, "Window animations are disabled by accessibility settings")
        let window = WindowElement(AXUIElementCreateSystemWide())
        XCTAssertNil(window.windowId, "Direct animation does not require a WindowServer identity")
        let destination = CGRect(x: 300, y: 120, width: 500, height: 400)
        var completedFrames: [CGRect] = []
        animator.animate(window, to: destination, duration: 0.18, resizeOnly: false, placement: nil, offset: { .zero }) { completedFrames.append($0) }

        XCTAssertTrue(completedFrames.isEmpty)
        XCTAssertEqual(animator.destination(for: window), destination)
        animator.finish()
        XCTAssertEqual(completedFrames, [destination])
        XCTAssertNil(animator.destination(for: window))

        let manager = try release(dragAlreadyDetected: true)

        XCTAssertEqual(completedFrames, [destination], "A later native release must not repeat the completed animation")
        XCTAssertEqual(manager.restores, 0)
        XCTAssertNil(animator.destination(for: window))
    }
}

class SnappingManagerSessionTests: XCTestCase {

    private var savedSnappingEnabled: Bool?

    override func setUp() {
        super.setUp()
        savedSnappingEnabled = Defaults.windowSnapping.enabled
        Defaults.windowSnapping.enabled = false
    }

    override func tearDown() {
        super.tearDown()
        Defaults.windowSnapping.enabled = savedSnappingEnabled
    }

    func testSessionDidBecomeActiveTriggersCheckFullScreen() {
        let sm = SnappingManager()
        sm.isFullScreen = true

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        XCTAssertFalse(sm.isFullScreen,
            "receiveSessionNote should call checkFullScreen, re-evaluating isFullScreen")
    }

    func testSessionDidBecomeActiveEventMonitorPreserved() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "toggleListening should be called but preserve event monitor state")
    }

    func testSessionDidBecomeActiveDoesNotEnableSnapping() {
        let sm = SnappingManager()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        XCTAssertNil(sm.eventMonitor,
            "snapping should remain disabled after session became active notification")
    }

    func testSessionDidBecomeActiveMultiplePostsNoCrash() {
        let sm = SnappingManager()

        for _ in 0..<5 {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil
            )
        }

        XCTAssertFalse(sm.isFullScreen)
    }

    func testSleepWakeMaintainsSnapping() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "activeSpaceDidChange (simulating wake) should preserve event monitor state")
    }

    func testSessionUnlockThenWakeMaintainsSnapping() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "session unlock followed by wake should restore event monitor state")
    }

    func testSessionUnlockWithDisabledSnapping() {
        let sm = SnappingManager()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        XCTAssertNil(sm.eventMonitor,
            "session unlock -> wake should not enable snapping when disabled")
    }

    func testFullScreenThenWakeThenLeaveFullScreen() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "session restore after full screen should preserve event monitor state")
    }

    func testSessionResignActiveDoesNotCrash() {
        let sm = SnappingManager()

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        XCTAssertFalse(sm.isFullScreen)
    }

    func testSessionResignActiveThenBecomeActive() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "session resign then become active should preserve event monitor state")
    }

    func testScreensDoNotSleepNotificationsBreakSnapping() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "screen sleep then wake should preserve event monitor state")
    }

    func testScreenSleepSessionResignThenWakeAndSessionActive() {
        Defaults.windowSnapping.enabled = true
        let sm = SnappingManager()
        let wasRunning = sm.eventMonitor?.running ?? false

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        let isRunning = sm.eventMonitor?.running ?? false
        XCTAssertEqual(isRunning, wasRunning,
            "screen sleep + session resign -> session active + wake should restore event monitor state")
    }
}

class SnappingManagerUnsnapRestoreTests: XCTestCase {

    private let windowId = CGWindowID(918_273)
    private var savedSnappingEnabled: Bool?
    private var savedUnsnapRestore: Bool?
    private var savedUnsnapRestoreFromSizeChange: Bool?
    private var savedRestoreRects = [CGWindowID: CGRect]()
    private var savedActions = [CGWindowID: RectangleAction]()

    override func setUp() {
        super.setUp()
        savedSnappingEnabled = Defaults.windowSnapping.enabled
        savedUnsnapRestore = Defaults.unsnapRestore.enabled
        savedUnsnapRestoreFromSizeChange = Defaults.unsnapRestoreFromSizeChange.enabled
        savedRestoreRects = AppDelegate.windowHistory.restoreRects
        savedActions = AppDelegate.windowHistory.lastRectangleActions
        Defaults.windowSnapping.enabled = false
        Defaults.unsnapRestore.enabled = true
        AppDelegate.windowHistory.restoreRects.removeValue(forKey: windowId)
        AppDelegate.windowHistory.lastRectangleActions.removeValue(forKey: windowId)
    }

    override func tearDown() {
        Defaults.windowSnapping.enabled = savedSnappingEnabled
        Defaults.unsnapRestore.enabled = savedUnsnapRestore
        Defaults.unsnapRestoreFromSizeChange.enabled = savedUnsnapRestoreFromSizeChange
        AppDelegate.windowHistory.restoreRects = savedRestoreRects
        AppDelegate.windowHistory.lastRectangleActions = savedActions
        super.tearDown()
    }

    func testSuppressedSizeChangeRestoreKeepsTheUserPositionedRect() {
        Defaults.unsnapRestoreFromSizeChange.enabled = false
        let userRect = CGRect(x: 164, y: 73, width: 1414, height: 861)
        let smallerRect = CGRect(x: 179, y: 88, width: 1354, height: 801)
        AppDelegate.windowHistory.restoreRects[windowId] = userRect
        AppDelegate.windowHistory.lastRectangleActions[windowId] = RectangleAction(action: .smaller,
                                                                                   subAction: nil,
                                                                                   rect: smallerRect,
                                                                                   count: 2)
        let snappingManager = SnappingManager()
        snappingManager.initialWindowRect = smallerRect

        snappingManager.unsnapRestore(windowId: windowId,
                                      currentRect: smallerRect.offsetBy(dx: 40, dy: 0),
                                      cursorLoc: nil)

        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[windowId], userRect)
    }

    func testDraggingAWindowRectangleDidNotPlaceRecordsTheRestoreRect() {
        let draggedFrom = CGRect(x: 100, y: 100, width: 800, height: 600)
        let snappingManager = SnappingManager()
        snappingManager.initialWindowRect = draggedFrom

        snappingManager.unsnapRestore(windowId: windowId,
                                      currentRect: draggedFrom.offsetBy(dx: 40, dy: 0),
                                      cursorLoc: nil)

        XCTAssertEqual(AppDelegate.windowHistory.restoreRects[windowId], draggedFrom)
    }
}

final class FullScreenSnapGateTests: XCTestCase {
    // Flipped frames: the built-in display is the primary one, the external display sits above it.
    private let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let external = CGRect(x: -416, y: -1440, width: 2560, height: 1440)

    func testNothingIsGatedWithoutAFullscreenWindow() {
        let gate = FullScreenSnapGate(isFullScreen: false, windowFrame: external, displayFrames: [builtIn, external])
        XCTAssertEqual(gate, .inactive)
        XCTAssertFalse(gate.suspendsListening)
        XCTAssertFalse(gate.ignoresGesture(at: CGPoint(x: 800, y: -700)))
        XCTAssertFalse(gate.ignoresGesture(at: nil))
    }

    func testAFullscreenWindowOnOneOfTwoDisplaysOnlyBlocksGesturesOnThatDisplay() {
        let gate = FullScreenSnapGate(isFullScreen: true, windowFrame: external, displayFrames: [builtIn, external])
        XCTAssertFalse(gate.suspendsListening)
        XCTAssertEqual(gate.displayFrame, external)
        XCTAssertTrue(gate.ignoresGesture(at: CGPoint(x: 800, y: -700)), "on the fullscreen display")
        XCTAssertFalse(gate.ignoresGesture(at: CGPoint(x: 800, y: 500)), "on the other display")
        XCTAssertTrue(gate.ignoresGesture(at: nil), "an unknown location counts as the fullscreen display")
    }

    func testAFullscreenWindowOnTheOnlyDisplayStillStopsListening() {
        let gate = FullScreenSnapGate(isFullScreen: true, windowFrame: builtIn, displayFrames: [builtIn])
        XCTAssertTrue(gate.suspendsListening)
        XCTAssertTrue(gate.ignoresGesture(at: CGPoint(x: 10, y: 10)))
    }

    func testAnUnknownWindowFrameStillStopsListening() {
        let frames: [CGRect?] = [nil, .null, .zero, CGRect(x: 9000, y: 9000, width: 10, height: 10)]
        for frame in frames {
            let gate = FullScreenSnapGate(isFullScreen: true, windowFrame: frame, displayFrames: [builtIn, external])
            XCTAssertNil(gate.displayFrame, String(describing: frame))
            XCTAssertTrue(gate.suspendsListening, String(describing: frame))
            XCTAssertTrue(gate.ignoresGesture(at: CGPoint(x: 800, y: 500)), String(describing: frame))
        }
    }

    func testTheDisplayShowingMostOfTheWindowIsChosen() {
        // 300 points of the window are on the external display, 700 on the built-in one.
        let straddling = CGRect(x: 200, y: -300, width: 1000, height: 1000)
        let gate = FullScreenSnapGate(isFullScreen: true, windowFrame: straddling, displayFrames: [builtIn, external])
        XCTAssertEqual(gate.displayFrame, builtIn)
    }
}

final class SnappingManagerFullScreenTests: XCTestCase {
    private final class Manager: SnappingManager {
        var begunDrags = 0
        @discardableResult
        override func beginNativeDrag() -> UUID {
            begunDrags += 1
            return super.beginNativeDrag()
        }
    }

    private let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let external = CGRect(x: -416, y: -1440, width: 2560, height: 1440)
    private let onExternal = CGPoint(x: 800, y: -700)
    private let onBuiltIn = CGPoint(x: 800, y: 500)
    private var savedSnapping: Bool?
    private var savedObtainOnClick: Bool?

    override func setUp() {
        super.setUp()
        savedSnapping = Defaults.windowSnapping.enabled
        savedObtainOnClick = Defaults.obtainWindowOnClick.enabled
        Defaults.windowSnapping.enabled = false
        // Keeps a tracked mouse-down away from the accessibility hit-test under the cursor.
        Defaults.obtainWindowOnClick.enabled = false
    }

    override func tearDown() {
        Defaults.windowSnapping.enabled = savedSnapping
        Defaults.obtainWindowOnClick.enabled = savedObtainOnClick
        super.tearDown()
    }

    private func fullScreenOnExternal() -> FullScreenSnapGate {
        FullScreenSnapGate(isFullScreen: true, windowFrame: external, displayFrames: [builtIn, external])
    }

    private func mouse(_ type: CGEventType, at point: CGPoint) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                            mouseCursorPosition: point, mouseButton: .left))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    func testAGestureOnTheFullscreenDisplayIsLeftAlone() throws {
        let manager = Manager()
        manager.fullScreenGate = fullScreenOnExternal()
        manager.handle(event: try mouse(.leftMouseDown, at: onExternal))
        XCTAssertEqual(manager.begunDrags, 0)
        manager.handle(event: try mouse(.leftMouseDragged, at: CGPoint(x: 850, y: -650)))
        XCTAssertEqual(manager.windowIdAttempt, 0, "no window lookup during the gesture")
        XCTAssertNil(manager.windowElement)
        XCTAssertFalse(manager.windowMoving)
        manager.handle(event: try mouse(.leftMouseUp, at: CGPoint(x: 850, y: -650)))
        XCTAssertEqual(manager.begunDrags, 0)
    }

    func testAGestureOnTheOtherDisplayIsTracked() throws {
        let manager = Manager()
        manager.fullScreenGate = fullScreenOnExternal()
        manager.handle(event: try mouse(.leftMouseDown, at: onBuiltIn))
        XCTAssertEqual(manager.begunDrags, 1)
        manager.handle(event: try mouse(.leftMouseUp, at: onBuiltIn))
    }

    func testEachGestureIsJudgedOnItsOwn() throws {
        let manager = Manager()
        manager.fullScreenGate = fullScreenOnExternal()
        manager.handle(event: try mouse(.leftMouseDown, at: onExternal))
        manager.handle(event: try mouse(.leftMouseUp, at: onExternal))
        manager.handle(event: try mouse(.leftMouseDown, at: onBuiltIn))
        XCTAssertEqual(manager.begunDrags, 1, "the ignored gesture does not carry over")
        manager.handle(event: try mouse(.leftMouseUp, at: onBuiltIn))
        manager.fullScreenGate = .inactive
        manager.handle(event: try mouse(.leftMouseDown, at: onExternal))
        XCTAssertEqual(manager.begunDrags, 2, "nothing is ignored once the window left fullscreen")
        manager.handle(event: try mouse(.leftMouseUp, at: onExternal))
    }

    func testAGestureIsForgottenWhenListeningStops() throws {
        let manager = Manager()
        manager.fullScreenGate = fullScreenOnExternal()
        manager.handle(event: try mouse(.leftMouseDown, at: onExternal))
        // Listening stops before the release arrives, as it does when an ignored app comes to the front.
        manager.toggleListening()
        // The restarted monitor picks up the next drag part-way, as it did before this change.
        manager.handle(event: try mouse(.leftMouseDragged, at: onBuiltIn))
        XCTAssertEqual(manager.windowIdAttempt, 1, "the drag is looked at rather than swallowed")
        manager.handle(event: try mouse(.leftMouseUp, at: onBuiltIn))
    }

    func testAnIgnoredPressFinishesAGestureWhoseReleaseWasLost() throws {
        let manager = Manager()
        manager.fullScreenGate = fullScreenOnExternal()
        manager.handle(event: try mouse(.leftMouseDown, at: onBuiltIn))
        XCTAssertEqual(manager.begunDrags, 1)
        manager.windowId = 42
        manager.initialWindowRect = CGRect(x: 100, y: 100, width: 800, height: 600)
        manager.currentSnapArea = SnapArea(screen: try XCTUnwrap(NSScreen.screens.first), directional: .l, action: .leftHalf)

        manager.handle(event: try mouse(.leftMouseDown, at: onExternal))
        XCTAssertEqual(manager.begunDrags, 1, "the press on the fullscreen display is still ignored")
        XCTAssertNil(manager.windowId)
        XCTAssertNil(manager.initialWindowRect)
        XCTAssertNil(manager.currentSnapArea)
        manager.handle(event: try mouse(.leftMouseUp, at: onExternal))
    }

    func testListeningContinuesForAFullscreenWindowOnOneOfTwoDisplays() {
        Defaults.windowSnapping.enabled = true
        let manager = SnappingManager()
        defer {
            manager.allowListening = false
            manager.toggleListening()
        }
        // A baseline that does not depend on the test host's own front window.
        manager.fullScreenGate = .inactive
        manager.toggleListening()
        let wasRunning = manager.eventMonitor?.running ?? false

        manager.fullScreenGate = fullScreenOnExternal()
        manager.toggleListening()
        XCTAssertNotNil(manager.eventMonitor, "gestures on the fullscreen display are ignored instead")
        XCTAssertEqual(manager.eventMonitor?.running ?? false, wasRunning)

        manager.fullScreenGate = FullScreenSnapGate(isFullScreen: true, windowFrame: builtIn, displayFrames: [builtIn])
        manager.toggleListening()
        XCTAssertNil(manager.eventMonitor, "a fullscreen window on the only display stops listening as before")

        manager.isFullScreen = true
        manager.toggleListening()
        XCTAssertNil(manager.eventMonitor, "so does a fullscreen window whose display is unknown")

        manager.fullScreenGate = .inactive
        manager.toggleListening()
        XCTAssertNotNil(manager.eventMonitor)
    }

    func testDisplayChangesReevaluateTheGate() {
        let manager = SnappingManager()
        manager.fullScreenGate = fullScreenOnExternal()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertFalse(manager.isFullScreen, "the test host's front window is not fullscreen")
        XCTAssertEqual(manager.fullScreenGate, .inactive)
    }
}
