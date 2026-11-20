/// FreeformCalculationTests.swift

import AppKit
import XCTest
@testable import Rectangle

/// What a Freeform preset's shortcut does to the focused window.
@MainActor
final class FreeformCalculationTests: XCTestCase {
    nonisolated static let presets: [WindowAction] = [.freeformOne, .freeformTwo, .freeformThree, .freeformFour]
    /// The presets' names in the language the tests run in.
    nonisolated static let titles = [String(localized: "Freeform 1"), String(localized: "Freeform 2"),
                                     String(localized: "Freeform 3"), String(localized: "Freeform 4")]

    private final class TestScreen: NSScreen {
        override var frame: NSRect { CGRect(x: 0, y: 0, width: 1600, height: 1000) }
        override var visibleFrame: NSRect { CGRect(x: 0, y: 0, width: 1600, height: 975) }
        override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    private lazy var screen = TestScreen()

    private func calculate(_ action: WindowAction) throws -> WindowCalculationResult? {
        let calculation = try XCTUnwrap(WindowCalculationFactory.calculationsByAction[action])
        return calculation.calculate(WindowCalculationParameters(
            window: Window(id: 1, rect: CGRect(x: 10, y: 10, width: 300, height: 200)),
            usableScreens: UsableScreens(currentScreen: screen, numScreens: 1),
            action: action, lastAction: nil, ignoreTodo: false))
    }

    /// Keeps the user's saved presets out of the tests.
    private func withPresets(_ regions: [FreeformRegion?], _ body: () throws -> Void) throws {
        let settings = try Self.presets.map { try XCTUnwrap($0.freeformRegion) }
        let saved = settings.map(\.typedValue)
        defer { zip(settings, saved).forEach { $0.typedValue = $1 } }
        zip(settings, regions).forEach { $0.typedValue = $1 }
        try body()
    }

    func testThereAreFourPresetsEachWithItsOwnSetting() throws {
        let settings = try Self.presets.map { try XCTUnwrap($0.freeformRegion) }
        XCTAssertEqual(Set(settings.map(\.key)).count, 4)
        XCTAssertEqual(Set(Self.presets.map(\.name)).count, 4)
        XCTAssertEqual(Self.presets.map(\.displayName), FreeformCalculationTests.titles)
        XCTAssertTrue(Self.presets.allSatisfy { $0.excludedFromMenu && !$0.isDragSnappable && !$0.positionCycles })
        XCTAssertTrue(Self.presets.allSatisfy { WindowAction.active.contains($0) })
    }

    func testEachPresetMovesTheWindowToItsOwnArea() throws {
        let workArea = screen.freeformWorkArea()
        let quarter = CGSize(width: (workArea.width / 2).rounded(.down), height: (workArea.height / 2).rounded(.down))
        let areas = [
            CGRect(origin: CGPoint(x: workArea.minX, y: workArea.midY), size: quarter),
            CGRect(origin: CGPoint(x: workArea.midX, y: workArea.midY), size: quarter),
            CGRect(origin: CGPoint(x: workArea.minX, y: workArea.minY), size: quarter),
            CGRect(origin: CGPoint(x: workArea.midX, y: workArea.minY), size: quarter),
        ].map { $0.integral.intersection(workArea) }
        let regions = try areas.map { try XCTUnwrap(FreeformRegion(rect: $0, in: workArea, displayID: nil)) }

        try withPresets(regions) {
            for (action, region) in zip(Self.presets, regions) {
                let result = try XCTUnwrap(try calculate(action))
                XCTAssertEqual(result.rect, region.rect(in: workArea))
                XCTAssertEqual(result.resultingAction, action)
            }
        }
    }

    func testAPresetWithoutAnAreaLeavesTheWindowAlone() throws {
        try withPresets([nil, nil, nil, nil]) {
            for action in Self.presets {
                XCTAssertNil(try calculate(action), action.name)
            }
        }
    }
}

/// Which display a Freeform preset's shortcut moves the window to.
@MainActor
final class FreeformScreenSelectionTests: XCTestCase {
    private final class TestScreen: NSScreen {
        private let testFrame: CGRect

        init(frame: CGRect) {
            testFrame = frame
            super.init()
        }

        override var frame: NSRect { testFrame }
        override var visibleFrame: NSRect { testFrame }
        override var hash: Int { ObjectIdentifier(self).hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
    }

    /// The window is on `windowScreen` and the cursor on `cursorScreen`.
    private final class TestScreenDetection: ScreenDetection {
        let screens: [NSScreen]
        let windowScreen: NSScreen
        let cursorScreen: NSScreen

        init(screens: [NSScreen], windowScreen: NSScreen, cursorScreen: NSScreen) {
            self.screens = screens
            self.windowScreen = windowScreen
            self.cursorScreen = cursorScreen
        }

        override func detectScreens(using frontmostWindowElement: AccessibilityElement?) -> UsableScreens? {
            detectScreens(at: windowScreen)
        }

        override func detectScreensAtCursor() -> UsableScreens? {
            detectScreens(at: cursorScreen)
        }

        override func detectScreens(at screen: NSScreen) -> UsableScreens? {
            UsableScreens(currentScreen: screen, numScreens: screens.count, screensOrdered: screens)
        }
    }

    private lazy var left = TestScreen(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000))
    private lazy var right = TestScreen(frame: CGRect(x: 1600, y: 0, width: 1200, height: 800))
    private let leftID = UUID()
    private let rightID = UUID()

    /// The screens the action is calculated against, with the window on the left display.
    private func selection(for action: WindowAction = .freeformOne, areaOn displayID: UUID??,
                           cursorOn cursorScreen: NSScreen? = nil, cursorDetection: Bool = false) throws -> ScreenSelection? {
        let setting = try XCTUnwrap(action.freeformRegion)
        let saved = (setting.typedValue, Defaults.useCursorScreenDetection.enabled)
        defer {
            setting.typedValue = saved.0
            Defaults.useCursorScreenDetection.enabled = saved.1
        }
        setting.typedValue = try displayID.map {
            try XCTUnwrap(FreeformRegion(rect: CGRect(x: 0, y: 0, width: 400, height: 300),
                                         in: CGRect(x: 0, y: 0, width: 800, height: 600), displayID: $0))
        }
        Defaults.useCursorScreenDetection.enabled = cursorDetection

        let detection = TestScreenDetection(screens: [left, right], windowScreen: left, cursorScreen: cursorScreen ?? left)
        var selector = ScreenSelector(screenDetection: detection, history: CursorScreenHistory())
        let ids = [ObjectIdentifier(left): leftID, ObjectIdentifier(right): rightID]
        selector.displayID = { ids[ObjectIdentifier($0)] }
        return selector.screens(for: AccessibilityElement(AXUIElementCreateSystemWide()), windowId: 987_020,
                                parameters: ExecutionParameters(action))
    }

    func testMovesTheWindowToTheDisplayTheAreaWasSelectedOn() throws {
        for action in FreeformCalculationTests.presets {
            let selection = try XCTUnwrap(try selection(for: action, areaOn: rightID), action.name)
            XCTAssertTrue(selection.usable.currentScreen === right, action.name)
            XCTAssertTrue(selection.source.currentScreen === left, action.name)
        }
    }

    func testUsesTheWindowsDisplayWhenTheAreasDisplayIsDisconnected() throws {
        let selection = try XCTUnwrap(try selection(areaOn: UUID()))
        XCTAssertTrue(selection.usable.currentScreen === left)
    }

    func testUsesTheWindowsDisplayWhenTheAreasDisplayIsUnknown() throws {
        let selection = try XCTUnwrap(try selection(areaOn: .some(nil)))
        XCTAssertTrue(selection.usable.currentScreen === left)
    }

    func testIgnoresTheDisplayUnderTheCursor() throws {
        let selection = try XCTUnwrap(try selection(areaOn: leftID, cursorOn: right, cursorDetection: true))
        XCTAssertTrue(selection.usable.currentScreen === left)
    }

    func testDoesNothingUntilAnAreaIsSelected() throws {
        XCTAssertNil(try selection(areaOn: nil))
    }
}
