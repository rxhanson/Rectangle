/// FreeformSettingsTests.swift

import AppKit
import XCTest
@testable import Rectangle

/// The Select buttons in Settings > Shortcuts > ⋯ > Extra, clicked in a real settings view.
@MainActor
final class FreeformSettingsTests: XCTestCase {
    private let displayID = UUID()
    private let workArea = CGRect(x: 0, y: 0, width: 1000, height: 675)

    private func makeSettings() -> (ShortcutsViewController, NSWindow) {
        let display = FreeformSelectionDisplay(frame: CGRect(x: 0, y: 0, width: 1000, height: 700),
                                               workArea: workArea, id: displayID)
        let shortcuts = ShortcutsViewController(freeformDisplays: { [display] })
        let window = FreeformTestWindows.make(frame: CGRect(x: 200, y: 50, width: 500, height: 610),
                                              contentViewController: shortcuts)
        window.orderFront(nil)
        return (shortcuts, window)
    }

    private func cells(in shortcuts: ShortcutsViewController) throws -> [WindowAction: ShortcutActionCellView] {
        let outline = try XCTUnwrap(Self.outlineView(in: shortcuts.view))
        outline.expandItem(nil, expandChildren: true)
        var cells: [WindowAction: ShortcutActionCellView] = [:]
        for row in 0..<outline.numberOfRows {
            guard let item = outline.item(atRow: row) as? ShortcutItem else { continue }
            cells[item.action] = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? ShortcutActionCellView
        }
        return cells
    }

    /// The row's cell once it is scrolled into view, as it is when the user clicks its Select button.
    private func visibleCell(for action: WindowAction, in shortcuts: ShortcutsViewController) throws -> ShortcutActionCellView {
        let outline = try XCTUnwrap(Self.outlineView(in: shortcuts.view))
        outline.expandItem(nil, expandChildren: true)
        let row = try XCTUnwrap((0..<outline.numberOfRows).first {
            (outline.item(atRow: $0) as? ShortcutItem)?.action == action
        })
        outline.scrollRowToVisible(row)
        shortcuts.view.window?.layoutIfNeeded()
        return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? ShortcutActionCellView)
    }

    private static func outlineView(in view: NSView) -> NSOutlineView? {
        (view as? NSOutlineView) ?? view.subviews.lazy.compactMap(outlineView).first
    }

    nonisolated static let presets: [WindowAction] = [.freeformOne, .freeformTwo, .freeformThree, .freeformFour]

    /// Keeps the user's saved presets out of the tests.
    private func withEmptyPreset(_ action: WindowAction, _ body: (JSONDefault<FreeformRegion>) throws -> Void) throws {
        try withEmptyPresets([action]) { try body($0[0]) }
    }

    private func withEmptyPresets(_ actions: [WindowAction] = presets,
                                  _ body: ([JSONDefault<FreeformRegion>]) throws -> Void) throws {
        let settings = try actions.map { try XCTUnwrap($0.freeformRegion) }
        let saved = settings.map(\.typedValue)
        defer { zip(settings, saved).forEach { $0.typedValue = $1 } }
        settings.forEach { $0.typedValue = nil }
        try body(settings)
    }

    func testOnlyTheFreeformRowsHaveASelectButton() throws {
        let (shortcuts, window) = makeSettings()
        defer { window.close() }

        let cells = try cells(in: shortcuts)

        let withButton = Set(cells.filter { !$0.value.selectButton.isHidden }.keys)
        XCTAssertEqual(withButton, Set(Self.presets))
        XCTAssertEqual(Self.presets.map { cells[$0]?.titleLabel.stringValue }, FreeformCalculationTests.titles)
    }

    func testTheFourPresetsAreTheLastRowsOfExtraInOrder() throws {
        let (shortcuts, window) = makeSettings()
        defer { window.close() }
        let outline = try XCTUnwrap(Self.outlineView(in: shortcuts.view))
        outline.expandItem(nil, expandChildren: true)

        let actions = (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? ShortcutItem)?.action }
        XCTAssertEqual(Array(actions.suffix(5)), [.topLeftSixteenth] + Self.presets)
    }

    func testClickingSelectOpensTheOverlayAndSavesTheDraggedArea() throws {
        for action in Self.presets {
            try XCTContext.runActivity(named: action.name) { _ in try clickSelectAndDrag(action) }
        }
    }

    private func clickSelectAndDrag(_ action: WindowAction) throws {
        try withEmptyPreset(action) { setting in
            let (shortcuts, window) = makeSettings()
            defer { shortcuts.freeformSelection.cancel(); window.close() }
            let button = try XCTUnwrap(try cells(in: shortcuts)[action]?.selectButton)

            button.performClick(nil)

            XCTAssertTrue(shortcuts.freeformSelection.isSelecting)
            let overlays = FreeformTestWindows.visibleOverlays
            XCTAssertEqual(overlays.count, 1)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.alphaValue, 0)
            let panel = try XCTUnwrap(overlays.first)

            try FreeformEvents.drag(in: panel, from: CGPoint(x: 100, y: 100),
                                    through: [CGPoint(x: 400, y: 300)], to: CGPoint(x: 600, y: 500))

            let region = try XCTUnwrap(setting.typedValue)
            XCTAssertEqual(region.displayID, displayID)
            assertFreeformRect(region.rect(in: workArea), equals: CGRect(x: 100, y: 100, width: 500, height: 400))
            XCTAssertFalse(shortcuts.freeformSelection.isSelecting)
            XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty)
            XCTAssertTrue(window.isVisible)
            XCTAssertEqual(window.alphaValue, 1)
        }
    }

    func testTheIconShowsTheAreaOnlyOnceItIsSelected() throws {
        for action in Self.presets {
            try XCTContext.runActivity(named: action.name) { _ in try showIconOnceSelected(action) }
        }
    }

    private func showIconOnceSelected(_ action: WindowAction) throws {
        try withEmptyPresets { _ in
            let setting = try XCTUnwrap(action.freeformRegion)
            let (shortcuts, window) = makeSettings()
            defer { shortcuts.freeformSelection.cancel(); window.close() }
            let cell = try visibleCell(for: action, in: shortcuts)
            XCTAssertEqual(cell.iconImageView.image?.size, .zero)

            // Cancelling leaves the preset without an area, so without an icon.
            cell.selectButton.performClick(nil)
            let cancelled = try XCTUnwrap(FreeformTestWindows.visibleOverlays.first)
            cancelled.sendEvent(try FreeformEvents.escape(in: cancelled))
            XCTAssertEqual(cell.iconImageView.image?.size, .zero)

            cell.selectButton.performClick(nil)
            let panel = try XCTUnwrap(FreeformTestWindows.visibleOverlays.first)
            try FreeformEvents.drag(in: panel, from: CGPoint(x: 0, y: 1), to: CGPoint(x: 500, y: 675))

            let icon = try XCTUnwrap(cell.iconImageView.image)
            XCTAssertTrue(icon.isTemplate)
            let pixels = try IconPixels(icon)
            XCTAssertEqual(pixels.opaqueRect(inside: FreeformPreview.screen), CGRect(x: 1, y: 1, width: 14, height: 18))
            XCTAssertEqual(pixels, try IconPixels(FreeformPreview.image(for: try XCTUnwrap(setting.typedValue))))
            // The other presets still have no area.
            for other in Self.presets where other != action {
                XCTAssertEqual(try visibleCell(for: other, in: shortcuts).iconImageView.image?.size, .zero, other.name)
            }
        }
    }

    func testASavedAreaIsShownWhenTheSettingsOpen() throws {
        for action in Self.presets {
            try withEmptyPreset(action) { setting in
                let area = CGRect(x: 500, y: 0, width: 500, height: 675)
                let region = try XCTUnwrap(FreeformRegion(rect: area, in: workArea, displayID: displayID))
                setting.typedValue = region
                let (shortcuts, window) = makeSettings()
                defer { window.close() }

                let icon = try XCTUnwrap(try cells(in: shortcuts)[action]?.iconImageView.image)
                XCTAssertEqual(try IconPixels(icon).opaqueRect(inside: FreeformPreview.screen),
                               CGRect(x: 15, y: 1, width: 14, height: 18), action.name)
            }
        }
    }

    func testEachPresetKeepsItsOwnArea() throws {
        try withEmptyPresets { settings in
            let (shortcuts, window) = makeSettings()
            defer { shortcuts.freeformSelection.cancel(); window.close() }
            // One quarter of the display each. The bottom pixel row is at y = 1 in AppKit
            // coordinates and the pointer can't reach x = 1000, so those edges snap to the display's.
            let drags: [(from: CGPoint, to: CGPoint, area: CGRect)] = [
                (CGPoint(x: 0, y: 338), CGPoint(x: 500, y: 675), CGRect(x: 0, y: 338, width: 500, height: 337)),
                (CGPoint(x: 500, y: 338), CGPoint(x: 999, y: 675), CGRect(x: 500, y: 338, width: 500, height: 337)),
                (CGPoint(x: 0, y: 1), CGPoint(x: 500, y: 338), CGRect(x: 0, y: 0, width: 500, height: 338)),
                (CGPoint(x: 500, y: 1), CGPoint(x: 999, y: 338), CGRect(x: 500, y: 0, width: 500, height: 338)),
            ]

            for (action, drag) in zip(Self.presets, drags) {
                try visibleCell(for: action, in: shortcuts).selectButton.performClick(nil)
                let panel = try XCTUnwrap(FreeformTestWindows.visibleOverlays.first)
                try FreeformEvents.drag(in: panel, from: drag.from, to: drag.to)
            }

            for (setting, drag) in zip(settings, drags) {
                assertFreeformRect(setting.typedValue?.rect(in: workArea), equals: drag.area)
            }
            let icons = try Self.presets.map {
                try IconPixels(try XCTUnwrap(try visibleCell(for: $0, in: shortcuts).iconImageView.image))
                    .opaqueRect(inside: FreeformPreview.screen)
            }
            XCTAssertEqual(icons, [CGRect(x: 1, y: 10, width: 14, height: 9), CGRect(x: 15, y: 10, width: 14, height: 9),
                                   CGRect(x: 1, y: 1, width: 14, height: 9), CGRect(x: 15, y: 1, width: 14, height: 9)])
        }
    }

    func testCancellingKeepsThePreviousArea() throws {
        try withEmptyPreset(.freeformOne) { setting in
            let previous = try XCTUnwrap(FreeformRegion(rect: CGRect(x: 10, y: 10, width: 300, height: 200),
                                                        in: workArea, displayID: displayID))
            setting.typedValue = previous
            let (shortcuts, window) = makeSettings()
            defer { shortcuts.freeformSelection.cancel(); window.close() }

            try cells(in: shortcuts)[.freeformOne]?.selectButton.performClick(nil)
            let panel = try XCTUnwrap(FreeformTestWindows.visibleOverlays.first)
            XCTAssertEqual(panel.selectionView.currentArea, CGRect(x: 10, y: 10, width: 300, height: 200))
            panel.sendEvent(try FreeformEvents.escape(in: panel))

            XCTAssertEqual(setting.typedValue, previous)
            XCTAssertFalse(shortcuts.freeformSelection.isSelecting)
            XCTAssertEqual(window.alphaValue, 1)
        }
    }

    func testShortcutsAreSuspendedWhileSelecting() throws {
        try withEmptyPreset(.freeformOne) { _ in
            let (shortcuts, window) = makeSettings()
            defer { shortcuts.freeformSelection.cancel(); window.close() }
            var suspensions: [Bool] = []
            let observer = NotificationCenter.default.addObserver(forName: .shortcutRecording, object: nil, queue: nil) {
                if let suspended = $0.object as? Bool { suspensions.append(suspended) }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            try cells(in: shortcuts)[.freeformOne]?.selectButton.performClick(nil)
            XCTAssertEqual(suspensions, [true])
            let panel = try XCTUnwrap(FreeformTestWindows.visibleOverlays.first)
            panel.sendEvent(try FreeformEvents.escape(in: panel))

            XCTAssertEqual(suspensions, [true, false])
        }
    }

    func testClosingTheSettingsWhileSelectingEndsTheSelection() throws {
        try withEmptyPreset(.freeformOne) { setting in
            let (shortcuts, window) = makeSettings()
            try cells(in: shortcuts)[.freeformOne]?.selectButton.performClick(nil)
            XCTAssertTrue(shortcuts.freeformSelection.isSelecting)

            window.close()

            XCTAssertFalse(shortcuts.freeformSelection.isSelecting)
            XCTAssertTrue(FreeformTestWindows.visibleOverlays.isEmpty)
            XCTAssertNil(setting.typedValue)
        }
    }
}
