/// FreeformSelectionControllerTests.swift

import AppKit
import Carbon
import XCTest
@testable import Rectangle

@MainActor
final class FreeformSelectionControllerTests: XCTestCase {
    /// Two side-by-side displays, each with a 25 point menu bar.
    private let firstFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let secondFrame = CGRect(x: 800, y: 0, width: 640, height: 480)
    private let firstID = UUID()
    private let secondID = UUID()

    private var displays: [FreeformSelectionDisplay] {
        [FreeformSelectionDisplay(frame: firstFrame, workArea: CGRect(x: 0, y: 0, width: 800, height: 575), id: firstID),
         FreeformSelectionDisplay(frame: secondFrame, workArea: CGRect(x: 800, y: 0, width: 640, height: 455), id: secondID)]
    }

    private func makeController() -> FreeformSelectionController {
        let displays = displays
        return FreeformSelectionController(displays: { displays })
    }

    private func overlay(_ controller: FreeformSelectionController, covering frame: CGRect) throws -> FreeformSelectionPanel {
        try XCTUnwrap(controller.panels.first { $0.frame == frame })
    }

    // MARK: - Starting

    func testCoversEveryDisplayAboveOtherWindows() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }

        controller.begin(from: settings, title: "Freeform 1") { _ in }

        XCTAssertTrue(controller.isSelecting)
        let overlays = FreeformTestWindows.visibleOverlays
        XCTAssertEqual(Set(overlays.map(\.frame)), [firstFrame, secondFrame])
        for overlay in overlays {
            XCTAssertGreaterThan(overlay.level.rawValue, NSWindow.Level.statusBar.rawValue)
            XCTAssertTrue(overlay.canBecomeKey)
            XCTAssertTrue(overlay.collectionBehavior.contains(.canJoinAllSpaces))
            XCTAssertTrue(overlay.contentView === overlay.selectionView)
        }
    }

    /// Ordering the settings window out would make its view controller disappear, and a selection
    /// cancelled when that happens would end as soon as it starts, so Select would do nothing.
    func testStartingDoesNotMakeTheSettingsDisappear() throws {
        let content = AppearanceRecordingViewController()
        let settings = FreeformTestWindows.make(contentViewController: content)
        settings.orderFront(nil)
        let controller = makeController()
        content.onDisappear = { controller.cancel() }
        defer { controller.cancel(); settings.close() }

        controller.begin(from: settings, title: "Freeform 1") { _ in }

        XCTAssertEqual(content.disappearCount, 0)
        XCTAssertTrue(controller.isSelecting)
        XCTAssertEqual(FreeformTestWindows.visibleOverlays.count, 2)
    }

    func testHidesTheSettingsWindowUntilTheSelectionEnds() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }

        controller.begin(from: settings, title: "Freeform 1") { _ in }
        XCTAssertEqual(settings.alphaValue, 0)
        XCTAssertTrue(settings.ignoresMouseEvents)
        XCTAssertTrue(settings.isVisible)

        controller.cancel()
        XCTAssertEqual(settings.alphaValue, 1)
        XCTAssertFalse(settings.ignoresMouseEvents)
        XCTAssertTrue(settings.isVisible)
    }

    func testStartingAgainWhileSelectingIsIgnored() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var first = 0, second = 0

        controller.begin(from: settings, title: "Freeform 1") { _ in first += 1 }
        controller.begin(from: settings, title: "Freeform 2") { _ in second += 1 }
        XCTAssertEqual(FreeformTestWindows.visibleOverlays.count, 2)

        controller.cancel()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
    }

    func testWithoutUsableDisplaysEndsAtOnceAndLeavesTheSettingsAlone() {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        defer { settings.close() }
        let controller = FreeformSelectionController(displays: {
            [FreeformSelectionDisplay(frame: CGRect(x: 0, y: 0, width: 800, height: 600), workArea: .zero, id: nil)]
        })
        var results: [FreeformRegion?] = []

        controller.begin(from: settings, title: "Freeform 1") { results.append($0) }

        XCTAssertFalse(controller.isSelecting)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, .some(nil))
        XCTAssertEqual(settings.alphaValue, 1)
        XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty)
    }

    // MARK: - Selecting

    func testDraggingSelectsTheAreaAndEndsTheSelection() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var results: [FreeformRegion?] = []
        controller.begin(from: settings, title: "Freeform 1") { results.append($0) }
        let panel = try overlay(controller, covering: firstFrame)

        try FreeformEvents.drag(in: panel, from: CGPoint(x: 600, y: 500),
                                through: [CGPoint(x: 400, y: 300), CGPoint(x: 150, y: 120)], to: CGPoint(x: 100, y: 100))

        XCTAssertEqual(results.count, 1)
        let region = try XCTUnwrap(results.first ?? nil)
        XCTAssertEqual(region.displayID, firstID)
        assertFreeformRect(region.rect(in: displays[0].workArea), equals: CGRect(x: 100, y: 100, width: 500, height: 400))
        XCTAssertFalse(controller.isSelecting)
        XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty)
        XCTAssertEqual(settings.alphaValue, 1)
        XCTAssertTrue(settings.isVisible)
    }

    func testSelectsOnTheDisplayWhereTheDragStarts() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var result: FreeformRegion?
        controller.begin(from: settings, title: "Freeform 1") { result = $0 }
        let panel = try overlay(controller, covering: secondFrame)

        // Dragging past the display's edges stops at its usable area.
        try FreeformEvents.drag(in: panel, from: CGPoint(x: 1000, y: 200), to: CGPoint(x: 2000, y: 900))

        let region = try XCTUnwrap(result)
        XCTAssertEqual(region.displayID, secondID)
        assertFreeformRect(region.rect(in: displays[1].workArea), equals: CGRect(x: 1000, y: 200, width: 440, height: 255))
    }

    func testAClickDoesNotSelectAndTheUserCanTryAgain() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var results: [FreeformRegion?] = []
        controller.begin(from: settings, title: "Freeform 1") { results.append($0) }
        let panel = try overlay(controller, covering: firstFrame)

        panel.sendEvent(try FreeformEvents.mouse(.leftMouseUp, at: CGPoint(x: 300, y: 300), in: panel))
        try FreeformEvents.drag(in: panel, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 303, y: 302))
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(controller.isSelecting)

        try FreeformEvents.drag(in: panel, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 500, y: 450))
        let region = try XCTUnwrap(results.first ?? nil)
        assertFreeformRect(region.rect(in: displays[0].workArea), equals: CGRect(x: 300, y: 300, width: 200, height: 150))
    }

    func testHoldingSpaceMovesTheSelection() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var result: FreeformRegion?
        controller.begin(from: settings, title: "Freeform 1") { result = $0 }
        let panel = try overlay(controller, covering: firstFrame)

        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100), in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 300, y: 200), in: panel))
        panel.sendEvent(try FreeformEvents.key(.keyDown, kVK_Space, characters: " ", in: panel))
        panel.sendEvent(try FreeformEvents.key(.keyDown, kVK_Space, characters: " ", in: panel, isARepeat: true))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 350, y: 260), in: panel))
        panel.sendEvent(try FreeformEvents.key(.keyUp, kVK_Space, characters: " ", in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 380, y: 280), in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseUp, at: CGPoint(x: 380, y: 280), in: panel))

        let region = try XCTUnwrap(result)
        assertFreeformRect(region.rect(in: displays[0].workArea), equals: CGRect(x: 150, y: 160, width: 230, height: 120))
    }

    func testOptionAndShiftChangeTheSelectionAsSoonAsTheyArePressed() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        controller.begin(from: settings, title: "Freeform 1") { _ in }
        let panel = try overlay(controller, covering: firstFrame)
        let view = panel.selectionView

        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDown, at: CGPoint(x: 400, y: 300), in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 500, y: 350), in: panel))
        assertFreeformRect(view.drag?.rect, equals: CGRect(x: 400, y: 300, width: 100, height: 50))

        panel.sendEvent(try FreeformEvents.flags(.option, keyCode: kVK_Option, in: panel))
        assertFreeformRect(view.drag?.rect, equals: CGRect(x: 300, y: 250, width: 200, height: 100))

        panel.sendEvent(try FreeformEvents.flags([], keyCode: kVK_Option, in: panel))
        panel.sendEvent(try FreeformEvents.flags(.shift, keyCode: kVK_Shift, in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 600, y: 370), in: panel, modifiers: .shift))
        assertFreeformRect(view.drag?.rect, equals: CGRect(x: 400, y: 300, width: 200, height: 50))
    }

    // MARK: - Cancelling

    func testEscapeCancelsEvenMidDragAndRestoresTheSettings() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var results: [FreeformRegion?] = []
        controller.begin(from: settings, title: "Freeform 1") { results.append($0) }
        let panel = try overlay(controller, covering: secondFrame)

        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDown, at: CGPoint(x: 900, y: 100), in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 1100, y: 300), in: panel))
        panel.sendEvent(try FreeformEvents.escape(in: panel))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, .some(nil))
        XCTAssertFalse(controller.isSelecting)
        XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty)
        XCTAssertEqual(settings.alphaValue, 1)
        XCTAssertTrue(settings.isVisible)

        // A release after cancelling doesn't select anything.
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseUp, at: CGPoint(x: 1200, y: 400), in: panel))
        XCTAssertEqual(results.count, 1)
    }

    func testEndsWhenTheAppOrDisplaysChange() throws {
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            let settings = FreeformTestWindows.make()
            settings.orderFront(nil)
            let controller = makeController()
            defer { controller.cancel(); settings.close() }
            var results: [FreeformRegion?] = []
            controller.begin(from: settings, title: "Freeform 1") { results.append($0) }

            NotificationCenter.default.post(name: name, object: NSApp)

            XCTAssertEqual(results.count, 1, name.rawValue)
            XCTAssertEqual(results.first, .some(nil), name.rawValue)
            XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty, name.rawValue)
            XCTAssertEqual(settings.alphaValue, 1, name.rawValue)
        }
    }

    func testEndsWhenTheSpaceChanges() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        var results: [FreeformRegion?] = []
        controller.begin(from: settings, title: "Freeform 1") { results.append($0) }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(controller.isSelecting)
    }

    func testClosingTheSettingsEndsTheSelectionWithoutReopeningThem() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel() }
        var results: [FreeformRegion?] = []
        controller.begin(from: settings, title: "Freeform 1") { results.append($0) }

        settings.close()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, .some(nil))
        XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty)
        XCTAssertFalse(settings.isVisible)
        XCTAssertEqual(settings.alphaValue, 1)
    }

    func testOtherKeysDoNotEndTheSelection() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        controller.begin(from: settings, title: "Freeform 1") { _ in }
        let panel = try overlay(controller, covering: firstFrame)

        panel.sendEvent(try FreeformEvents.key(.keyDown, kVK_ANSI_A, characters: "a", in: panel))
        panel.sendEvent(try FreeformEvents.key(.keyDown, kVK_Return, characters: "\r", in: panel))

        XCTAssertTrue(controller.isSelecting)
    }

    // MARK: - Drawing

    func testDrawsTheSelectionLikeTheScreenshotTool() throws {
        let display = FreeformSelectionDisplay(frame: CGRect(x: 0, y: 0, width: 300, height: 240),
                                               workArea: CGRect(x: 0, y: 0, width: 300, height: 215), id: nil)
        let view = FreeformSelectionView(display: display, title: "Freeform 1", currentArea: nil)
        let panel = FreeformSelectionPanel(display: display, view: view)
        panel.orderFront(nil)
        defer { panel.close() }

        // The menu bar can't be selected, so it is darker than the usable area.
        let idle = try Rendering(view)
        XCTAssertGreaterThan(idle.alpha(at: CGPoint(x: 150, y: 230)), idle.alpha(at: CGPoint(x: 150, y: 40)) + 0.1)
        XCTAssertGreaterThan(idle.alpha(at: CGPoint(x: 150, y: 40)), 0.15)

        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDown, at: CGPoint(x: 50, y: 40), in: panel))
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 200, y: 160), in: panel))
        let selecting = try Rendering(view)
        XCTAssertLessThan(selecting.alpha(at: CGPoint(x: 120, y: 60)), 0.15)
        XCTAssertGreaterThan(selecting.alpha(at: CGPoint(x: 250, y: 60)), 0.15)

        // Shrinking the selection shades the area it left.
        panel.sendEvent(try FreeformEvents.mouse(.leftMouseDragged, at: CGPoint(x: 100, y: 160), in: panel))
        let shrunk = try Rendering(view)
        XCTAssertGreaterThan(shrunk.alpha(at: CGPoint(x: 150, y: 60)), 0.15)
        XCTAssertLessThan(shrunk.alpha(at: CGPoint(x: 75, y: 60)), 0.15)
    }

    func testOutlinesThePresetsCurrentArea() throws {
        let display = FreeformSelectionDisplay(frame: CGRect(x: 0, y: 0, width: 300, height: 240),
                                               workArea: CGRect(x: 0, y: 0, width: 300, height: 215), id: nil)
        let view = FreeformSelectionView(display: display, title: "Freeform 1", currentArea: CGRect(x: 100, y: 50, width: 100, height: 80))
        let panel = FreeformSelectionPanel(display: display, view: view)
        defer { panel.close() }

        let rendering = try Rendering(view)

        // The dashed white line runs along the area's left edge.
        let edge = (55...125).map { rendering.brightness(at: CGPoint(x: 100, y: CGFloat($0))) }.max() ?? 0
        XCTAssertGreaterThan(edge, 0.9)
        XCTAssertLessThan(rendering.brightness(at: CGPoint(x: 150, y: 90)), 0.2)
    }

    func testOutlinesTheCurrentAreaOnlyOnItsDisplay() throws {
        let settings = FreeformTestWindows.make()
        settings.orderFront(nil)
        let controller = makeController()
        defer { controller.cancel(); settings.close() }
        let current = try XCTUnwrap(FreeformRegion(rect: CGRect(x: 900, y: 100, width: 300, height: 200),
                                                   in: displays[1].workArea, displayID: secondID))

        controller.begin(from: settings, title: "Freeform 1", current: current) { _ in }

        let first = try overlay(controller, covering: firstFrame)
        let second = try overlay(controller, covering: secondFrame)
        XCTAssertNil(first.selectionView.currentArea)
        XCTAssertEqual(second.selectionView.currentArea, CGRect(x: 900, y: 100, width: 300, height: 200))
    }

}

/// A view drawn into a bitmap, sampled at points in the view's coordinates.
@MainActor
private struct Rendering {
    private let bitmap: NSBitmapImageRep
    private let size: CGSize

    init(_ view: NSView) throws {
        bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }

    func color(at point: CGPoint) -> NSColor? {
        let scaleX = CGFloat(bitmap.pixelsWide) / size.width, scaleY = CGFloat(bitmap.pixelsHigh) / size.height
        let x = min(max(Int(point.x * scaleX), 0), bitmap.pixelsWide - 1)
        let y = min(max(Int((size.height - point.y) * scaleY), 0), bitmap.pixelsHigh - 1)
        return bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    func alpha(at point: CGPoint) -> CGFloat { color(at: point)?.alphaComponent ?? 0 }
    func brightness(at point: CGPoint) -> CGFloat { color(at: point)?.brightnessComponent ?? 0 }
}

private final class AppearanceRecordingViewController: NSViewController {
    var disappearCount = 0
    var onDisappear: (() -> Void)?

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 240))
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        disappearCount += 1
        onDisappear?()
    }
}
