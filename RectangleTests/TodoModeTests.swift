/// TodoModeTests.swift

import MASShortcut
import XCTest
@testable import Rectangle

final class TodoWindowPlacementTests: XCTestCase {
    private var savedDefaults: [(Default, CodableDefault)] = []

    override func setUp() {
        super.setUp()
        let settings: [(Default, CodableDefault)] = [
            (Defaults.todoSidebarWidth, CodableDefault(float: 1024)),
            (Defaults.todoSidebarWidthUnit, CodableDefault(int: TodoSidebarWidthUnit.pixels.rawValue)),
            (Defaults.todoSidebarSide, CodableDefault(int: TodoSidebarSide.right.rawValue)),
            (Defaults.gapSize, CodableDefault(float: 0))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        super.tearDown()
    }

    func testPrimaryDisplayUsesVisibleTopEdge() {
        assertPlacement(visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
                        expected: CGRect(x: 1536, y: 25, width: 1024, height: 1415))
    }

    func testDisplayAbovePrimaryKeepsNegativeAccessibilityY() {
        // Issue #535: this window must stay on the upper display, rather than move to y = 1440.
        assertPlacement(visibleFrame: CGRect(x: 0, y: 1440, width: 2560, height: 1415),
                        expected: CGRect(x: 1536, y: -1415, width: 1024, height: 1415))
    }

    func testDisplayBelowPrimaryKeepsVerticalOffset() {
        assertPlacement(visibleFrame: CGRect(x: 0, y: -1440, width: 2560, height: 1415),
                        expected: CGRect(x: 1536, y: 1465, width: 1024, height: 1415))
    }

    func testHorizontalDisplaysKeepPositiveAndNegativeVerticalOffsetsOnBothSides() {
        for side in TodoSidebarSide.allCases {
            let sidebarX: CGFloat = side == .left ? -2560 : -1024
            assertPlacement(visibleFrame: CGRect(x: -2560, y: 320, width: 2560, height: 1415),
                            expected: CGRect(x: sidebarX, y: -295, width: 1024, height: 1415),
                            side: side)
            assertPlacement(visibleFrame: CGRect(x: -2560, y: -320, width: 2560, height: 1415),
                            expected: CGRect(x: sidebarX, y: 345, width: 1024, height: 1415),
                            side: side)
        }
    }

    func testAdjustedVisibleFramePreservesDockAndMenuInsetsOnBothSides() {
        let visibleFrame = CGRect(x: 70, y: 1510, width: 2490, height: 1345)
        assertPlacement(visibleFrame: visibleFrame,
                        expected: CGRect(x: 70, y: -1415, width: 1024, height: 1345),
                        side: .left)
        assertPlacement(visibleFrame: visibleFrame,
                        expected: CGRect(x: 1536, y: -1415, width: 1024, height: 1345))
    }

    func testGapsPreserveUpperDisplayAndUseHalfGapAtSharedEdge() {
        Defaults.gapSize.value = 20
        let visibleFrame = CGRect(x: 0, y: 1440, width: 2560, height: 1415)
        assertPlacement(visibleFrame: visibleFrame,
                        expected: CGRect(x: 20, y: -1395, width: 994, height: 1375),
                        side: .left)
        assertPlacement(visibleFrame: visibleFrame,
                        expected: CGRect(x: 1546, y: -1395, width: 994, height: 1375))
    }

    func testPercentageWidthUsesDestinationVisibleFrameWidth() {
        Defaults.todoSidebarWidth.value = 40
        Defaults.todoSidebarWidthUnit.value = .pct
        assertPlacement(visibleFrame: CGRect(x: 70, y: 1510, width: 2490, height: 1345),
                        expected: CGRect(x: 1564, y: -1415, width: 996, height: 1345))
    }

    private func assertPlacement(visibleFrame: CGRect, expected: CGRect, side: TodoSidebarSide = .right,
                                 file: StaticString = #filePath, line: UInt = #line) {
        Defaults.todoSidebarSide.value = side
        let window = CapturingWindow()

        TodoManager.moveTodoWindow(window, screenVisibleFrame: visibleFrame, primaryScreenMaxY: 1440)

        XCTAssertEqual(window.requestedFrames, [expected], file: file, line: line)
    }

    private final class CapturingWindow: AccessibilityElement {
        private(set) var requestedFrames: [CGRect] = []

        init() {
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { CGRect(x: 100, y: 1000, width: 500, height: 400) }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            requestedFrames.append(frame)
        }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: ImmediateWindowPlacement? = nil) {
            requestedFrames.append(target)
        }
    }
}

final class TodoWindowMinimumSizeTests: XCTestCase {
    private var savedDefaults: [(Default, CodableDefault)] = []

    override func setUp() {
        super.setUp()
        let settings: [(Default, CodableDefault)] = [
            (Defaults.todoSidebarWidth, CodableDefault(float: 400)),
            (Defaults.todoSidebarWidthUnit, CodableDefault(int: TodoSidebarWidthUnit.pixels.rawValue)),
            (Defaults.todoSidebarSide, CodableDefault(int: TodoSidebarSide.right.rawValue)),
            (Defaults.gapSize, CodableDefault(float: 0))
        ]
        savedDefaults = settings.map { ($0.0, $0.0.toCodable()) }
        settings.forEach { $0.0.load(from: $0.1) }
    }

    override func tearDown() {
        savedDefaults.forEach { $0.0.load(from: $0.1) }
        super.tearDown()
    }

    // The primary display's visible frame; accessibility y of its top edge is 25.
    private let visibleFrame = CGRect(x: 0, y: 0, width: 2560, height: 1415)

    private func place(_ window: MinimumSizeWindow, side: TodoSidebarSide = .right) {
        Defaults.todoSidebarSide.value = side
        TodoManager.moveTodoWindow(window, screenVisibleFrame: visibleFrame, primaryScreenMaxY: 1440)
    }

    func testAWindowThatAcceptsTheSidebarWidthIsPlacedOnce() {
        let window = MinimumSizeWindow(minimumWidth: 300)
        place(window)
        XCTAssertEqual(window.frame, CGRect(x: 2160, y: 25, width: 400, height: 1415))
        XCTAssertEqual(window.sizeWrites, 1)
        XCTAssertEqual(window.moves, [])
    }

    func testAWiderMinimumWidthKeepsTheRightSidebarOnScreen() {
        // Issue #1307: the window kept 600 points and used to extend 200 points past the screen edge.
        let window = MinimumSizeWindow(minimumWidth: 600)
        place(window)
        XCTAssertEqual(window.frame, CGRect(x: 1960, y: 25, width: 600, height: 1415))
        XCTAssertEqual(window.frame.maxX, visibleFrame.maxX)
        XCTAssertEqual(window.sizeWrites, 1, "the accepted size is kept; only the position is written again")
        XCTAssertEqual(window.moves, [CGPoint(x: 1960, y: 25)])
    }

    func testGapsStayInFrontOfTheOuterEdge() {
        Defaults.gapSize.value = 20
        let window = MinimumSizeWindow(minimumWidth: 600)
        place(window)
        // The zone ends 20 points before the screen edge; the window ends with the zone.
        XCTAssertEqual(window.frame, CGRect(x: 1940, y: 45, width: 600, height: 1375))
    }

    func testALeftSidebarAlreadyStartsAtItsEdge() {
        let window = MinimumSizeWindow(minimumWidth: 600)
        place(window, side: .left)
        XCTAssertEqual(window.frame, CGRect(x: 0, y: 25, width: 600, height: 1415))
        XCTAssertEqual(window.moves, [])
    }

    func testAWindowWiderThanTheScreenKeepsItsLeadingEdgeOnScreen() {
        for side in TodoSidebarSide.allCases {
            let window = MinimumSizeWindow(minimumWidth: 3000)
            place(window, side: side)
            XCTAssertEqual(window.frame, CGRect(x: 0, y: 25, width: 3000, height: 1415), "\(side)")
        }
    }

    func testALeftSidebarThatOnlyFitsWithoutItsGapMovesToTheScreenEdge() {
        Defaults.gapSize.value = 20
        let window = MinimumSizeWindow(minimumWidth: 2550)
        place(window, side: .left)
        XCTAssertEqual(window.frame, CGRect(x: 0, y: 45, width: 2550, height: 1375))
        XCTAssertEqual(window.moves, [CGPoint(x: 0, y: 45)])
    }

    func testATallerMinimumHeightEndsWithTheVisibleFrame() {
        Defaults.gapSize.value = 20
        let window = MinimumSizeWindow(minimumWidth: 300, minimumHeight: 1400)
        place(window)
        // The zone is 1375 tall; the window keeps 1400 and moves up to end with the visible frame.
        XCTAssertEqual(window.frame, CGRect(x: 2170, y: 40, width: 370, height: 1400))
        XCTAssertEqual(window.moves, [CGPoint(x: 2170, y: 40)])
    }

    func testAWindowTallerThanTheScreenKeepsItsTopOnScreen() {
        let window = MinimumSizeWindow(minimumWidth: 300, minimumHeight: 1500)
        place(window)
        XCTAssertEqual(window.frame, CGRect(x: 2160, y: 25, width: 400, height: 1500))
        XCTAssertEqual(window.moves, [])
    }

    func testAnUnreadableFrameIsLeftAlone() {
        let window = MinimumSizeWindow(minimumWidth: 600, reportsFrame: false)
        place(window)
        XCTAssertEqual(window.sizeWrites, 1)
        XCTAssertEqual(window.moves, [])
    }

    /// Applies a requested frame the way an app with a minimum size does, and
    /// records the position-only moves of the correction.
    private final class MinimumSizeWindow: AccessibilityElement {
        private var currentFrame = CGRect(x: 100, y: 1000, width: 500, height: 400)
        private let minimumWidth: CGFloat
        private let minimumHeight: CGFloat
        private let reportsFrame: Bool
        private(set) var sizeWrites = 0
        private(set) var moves: [CGPoint] = []

        init(minimumWidth: CGFloat, minimumHeight: CGFloat = 0, reportsFrame: Bool = true) {
            self.minimumWidth = minimumWidth
            self.minimumHeight = minimumHeight
            self.reportsFrame = reportsFrame
            super.init(AXUIElementCreateSystemWide())
        }

        override var frame: CGRect { reportsFrame ? currentFrame : .null }

        override func setFrame(_ frame: CGRect, adjustSizeFirst: Bool = true, adjustPosition: Bool = true) {
            sizeWrites += 1
            currentFrame = CGRect(origin: frame.origin,
                                  size: CGSize(width: max(frame.width, minimumWidth),
                                               height: max(frame.height, minimumHeight)))
        }

        override func setImmediateFrame(_ target: CGRect, from before: CGRect, sizeFirst: Bool,
                                        placement: ImmediateWindowPlacement? = nil) {
            XCTAssertEqual(target.size, before.size, "the correction must not ask for a new size")
            moves.append(target.origin)
            currentFrame.origin = target.origin
        }
    }
}

final class TodoSideLocalizationTests: XCTestCase {

    // "Left" and "Right" name the Left/Right Half actions, so the Todo side needs its own keys.
    func testTodoSideTitlesKeepTheirEnglishText() throws {
        try XCTSkipUnless(Bundle.main.preferredLocalizations.first == "en", "Needs the test host in English (#1958)")
        XCTAssertEqual(TodoSidebarSide.left.title, "Left")
        XCTAssertEqual(TodoSidebarSide.right.title, "Right")
    }

    func testTodoSideKeysAreSeparateFromTheHalfActionNames() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let zhHans = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(zhHans.localizedString(forKey: "Todo Side Left", value: nil, table: "Localizable"), "左侧")
        XCTAssertEqual(zhHans.localizedString(forKey: "Todo Side Right", value: nil, table: "Localizable"), "右侧")
        XCTAssertEqual(zhHans.localizedString(forKey: "Left", value: nil, table: "Localizable"), "左半屏")
        XCTAssertEqual(zhHans.localizedString(forKey: "Right", value: nil, table: "Localizable"), "右半屏")
    }

    func testTodoSideJapaneseTranslations() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ja", ofType: "lproj"))
        let ja = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(ja.localizedString(forKey: "Todo Side Left", value: nil, table: "Localizable"), "左")
        XCTAssertEqual(ja.localizedString(forKey: "Todo Side Right", value: nil, table: "Localizable"), "右")
    }
}

class TodoShortcutValidatorTests: XCTestCase {

    private func shortcut(_ keyCode: Int, _ flags: NSEvent.ModifierFlags) -> MASShortcut {
        MASShortcut(keyCode: keyCode, modifierFlags: flags)
    }

    private func save(_ shortcut: MASShortcut, forKey key: String, in userDefaults: UserDefaults) {
        let dictTransformer = ValueTransformer(forName: NSValueTransformerName(rawValue: MASDictionaryTransformerName))!
        let shortcutDict = dictTransformer.reverseTransformedValue(shortcut)
        userDefaults.set(shortcutDict, forKey: key)
    }

    private func userDefaultsSuite() -> (String, UserDefaults) {
        let suiteName = "TodoShortcutValidatorTests.\(UUID().uuidString)"
        return (suiteName, UserDefaults(suiteName: suiteName)!)
    }

    func testInvalidatesShortcutUsedByWindowActionWithoutAlreadyTakenError() {
        let (suiteName, userDefaults) = userDefaultsSuite()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let duplicateShortcut = shortcut(1, [.option, .command])
        save(duplicateShortcut, forKey: WindowAction.centerHalf.name, in: userDefaults)
        let validator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey, userDefaults: userDefaults)
        var explanation: NSString?

        let isTaken = validator.isShortcutAlreadyTaken(bySystem: duplicateShortcut, explanation: &explanation)

        XCTAssertFalse(validator.isShortcutValid(duplicateShortcut))
        XCTAssertFalse(isTaken)
        XCTAssertNil(explanation)
    }

    func testInvalidatesShortcutUsedByOtherTodoActionWithoutAlreadyTakenError() {
        let (suiteName, userDefaults) = userDefaultsSuite()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let duplicateShortcut = shortcut(1, [.option, .command])
        save(duplicateShortcut, forKey: TodoManager.reflowDefaultsKey, in: userDefaults)
        let validator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey, userDefaults: userDefaults)
        var explanation: NSString?

        let isTaken = validator.isShortcutAlreadyTaken(bySystem: duplicateShortcut, explanation: &explanation)

        XCTAssertFalse(validator.isShortcutValid(duplicateShortcut))
        XCTAssertFalse(isTaken)
        XCTAssertNil(explanation)
    }

    func testAllowsExistingShortcutForSameTodoAction() {
        let (suiteName, userDefaults) = userDefaultsSuite()
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let existingShortcut = shortcut(1, [.option, .command])
        save(existingShortcut, forKey: TodoManager.toggleDefaultsKey, in: userDefaults)
        let validator = TodoShortcutValidator(defaultsKey: TodoManager.toggleDefaultsKey, userDefaults: userDefaults)

        XCTAssertTrue(validator.isShortcutValid(existingShortcut))
        XCTAssertFalse(validator.isShortcutAlreadyTaken(bySystem: existingShortcut, explanation: nil))
    }
}

final class TodoDisplayChangeReflowTests: XCTestCase {

    private typealias Layout = TodoDisplayChangeReflow.ScreenLayout

    private final class SchedulerSpy {
        private(set) var scheduled = [DispatchWorkItem]()

        func schedule(_ work: DispatchWorkItem) {
            scheduled.append(work)
        }

        /// Fires everything that is due, skipping cancelled items the way a queue does.
        func settle() {
            let due = scheduled
            scheduled.removeAll()
            for work in due where !work.isCancelled {
                work.perform()
            }
        }
    }

    private final class Harness {
        let notificationCenter = NotificationCenter()
        let scheduler = SchedulerSpy()
        var layout: Layout
        var reflows = 0
        var reflow: TodoDisplayChangeReflow?

        init(initial: Layout) {
            layout = initial
            reflow = TodoDisplayChangeReflow(notificationCenter: notificationCenter,
                                             delay: 0,
                                             layout: { [unowned self] in self.layout },
                                             reflow: { [unowned self] in self.reflows += 1 },
                                             schedule: { [unowned self] _, work in self.scheduler.schedule(work) })
        }

        func post() {
            notificationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
    }

    private let laptopOnly = Layout(frames: [CGRect(x: 0, y: 0, width: 1728, height: 1117)],
                                    visibleFrames: [CGRect(x: 0, y: 0, width: 1728, height: 1084)])
    private let withExternal = Layout(frames: [CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                               CGRect(x: -99, y: 1117, width: 1920, height: 1080)],
                                      visibleFrames: [CGRect(x: 0, y: 0, width: 1728, height: 1084),
                                                      CGRect(x: -99, y: 1117, width: 1920, height: 1080)])

    func testADisplayChangeReflowsOnceAfterTheBurstSettles() {
        let harness = Harness(initial: laptopOnly)

        harness.layout = withExternal
        harness.post()
        harness.post()
        harness.post()
        XCTAssertEqual(harness.reflows, 0, "nothing until the notifications settle")

        harness.scheduler.settle()

        XCTAssertEqual(harness.reflows, 1)
    }

    func testNotificationsThatLeaveTheLayoutAloneDoNotReflow() {
        let harness = Harness(initial: laptopOnly)

        harness.post()
        harness.scheduler.settle()

        XCTAssertEqual(harness.reflows, 0)
    }

    func testADisplayUnpluggedAndPluggedBackInStillReflows() {
        let harness = Harness(initial: withExternal)

        harness.layout = laptopOnly
        harness.post()
        harness.layout = withExternal
        harness.post()
        harness.scheduler.settle()

        XCTAssertEqual(harness.reflows, 1, "macOS moved windows while the display was away")
    }

    func testOnlyANewLayoutReflowsAgain() {
        let harness = Harness(initial: laptopOnly)

        harness.layout = withExternal
        harness.post()
        harness.scheduler.settle()
        XCTAssertEqual(harness.reflows, 1)

        harness.post()
        harness.scheduler.settle()
        XCTAssertEqual(harness.reflows, 1, "the same layout again is not a change")

        harness.layout = laptopOnly
        harness.post()
        harness.scheduler.settle()
        XCTAssertEqual(harness.reflows, 2)
    }

    /// AppKit can still report the old visible frames when the notification
    /// arrives; the layout is read again once the burst has settled.
    func testALayoutThatOnlyDiffersOnceTheBurstSettlesStillReflows() {
        let harness = Harness(initial: laptopOnly)

        harness.post()
        harness.layout = withExternal
        harness.scheduler.settle()

        XCTAssertEqual(harness.reflows, 1)
    }

    func testStopsListeningWhenReleased() {
        let harness = Harness(initial: laptopOnly)

        harness.reflow = nil
        harness.layout = withExternal
        harness.post()

        XCTAssertTrue(harness.scheduler.scheduled.isEmpty)
        XCTAssertEqual(harness.reflows, 0)
    }
}
