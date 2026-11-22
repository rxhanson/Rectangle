import XCTest
@testable import Rectangle

@MainActor
final class LiquidGlassBlurTests: XCTestCase {
    private var previousMaterial: Any?
    private var previousBlur = false

    override func setUp() {
        previousMaterial = UserDefaults.standard.object(forKey: Defaults.blurMaterial.key)
        previousBlur = Defaults.footprintBlur.enabled
    }
    override func tearDown() {
        UserDefaults.standard.set(previousMaterial, forKey: Defaults.blurMaterial.key)
        Defaults.footprintBlur.enabled = previousBlur
        Notification.Name.blurStyleChanged.post()
    }

    func testGlassMaterialTracksColdAndRepeatedAnimatedPreview() async throws {
        guard #available(macOS 26, *), let screen = NSScreen.main else { throw XCTSkip("Requires native glass and a screen") }
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.blurMaterial.value = .liquidGlass
        Defaults.footprintBlur.enabled = true
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        for _ in 0..<2 {
            window.showPreview(in: target, from: CGPoint(x: target.minX + 4, y: target.midY), duration: 0.24)
            try await assertGlassTracksSurface(window, for: 0.32)
            window.orderOut(nil)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }

    func testGlassRetargetingStyleSwitchAndCloseRetireAnimation() async throws {
        guard #available(macOS 26, *), let screen = NSScreen.main else { throw XCTSkip("Requires native glass and a screen") }
        let duration = Defaults.footprintAnimationDurationMultiplier.toCodable()
        let fade = Defaults.footprintFade.toCodable()
        defer {
            Defaults.footprintAnimationDurationMultiplier.load(from: duration)
            Defaults.footprintFade.load(from: fade)
        }
        Defaults.blurMaterial.value = .liquidGlass
        Defaults.footprintBlur.enabled = true
        Defaults.footprintAnimationDurationMultiplier.value = 1
        Defaults.footprintFade.enabled = false
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        let area = screen.visibleFrame.insetBy(dx: 40, dy: 20)
        let left = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        let right = left.offsetBy(dx: left.width, dy: 0)
        window.showPreview(in: left, from: CGPoint(x: left.minX + 4, y: left.midY), duration: 0.24)
        try await assertGlassTracksSurface(window, for: 0.05)
        window.movePreview(to: right, duration: 0.24)
        try await assertGlassTracksSurface(window, for: 0.05)
        window.orderOut(nil)
        window.showPreview(in: left, from: CGPoint(x: left.minX + 4, y: left.midY), duration: 0.24)
        try await assertGlassTracksSurface(window, for: 0.05)
        Defaults.blurMaterial.value = .standard
        Notification.Name.blurStyleChanged.post()
        window.movePreview(to: right, duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        Defaults.blurMaterial.value = .liquidGlass
        Notification.Name.blurStyleChanged.post()
        try await assertGlassTracksSurface(window, for: 0.05)
        window.movePreview(to: left, duration: 0.24)
        window.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(window.realIsVisible)
    }

    @MainActor
    @available(macOS 26, *)
    private func assertGlassTracksSurface(_ window: FootprintWindow, for duration: TimeInterval,
                                         file: StaticString = #filePath, line: UInt = #line) async throws {
        func material(in view: NSView) -> BlurSurfaceView? {
            if let surface = view as? BlurSurfaceView { return surface }
            return view.subviews.lazy.compactMap { material(in: $0) }.first
        }
        let surface = try XCTUnwrap(window.contentView.flatMap { material(in: $0) }, file: file, line: line)
        let until = CACurrentMediaTime() + duration
        let presentationDeadline = until + 0.5
        var presentationSamples = 0
        repeat {
            try await Task.sleep(nanoseconds: 8_000_000)
            let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView, file: file, line: line)
            XCTAssertEqual(glass.frame.width, surface.bounds.width, accuracy: 1, file: file, line: line)
            XCTAssertEqual(glass.frame.height, surface.bounds.height, accuracy: 1, file: file, line: line)
            // A newly installed material may not have a presentation layer yet.
            // Never compare its model geometry with its parent's previous rendered frame.
            if let outer = surface.layer?.presentation()?.bounds,
               let inner = glass.layer?.presentation()?.frame {
                XCTAssertEqual(inner.width, outer.width, accuracy: 1, file: file, line: line)
                XCTAssertEqual(inner.height, outer.height, accuracy: 1, file: file, line: line)
                presentationSamples += 1
            }
        } while CACurrentMediaTime() < until
            || (presentationSamples == 0 && CACurrentMediaTime() < presentationDeadline)
        XCTAssertGreaterThan(presentationSamples, 0, "Glass must produce a rendered frame", file: file, line: line)
    }

    func testSwitchingMaterialRetainsContentAndResizesWithoutLegacyBlur() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Native glass requires macOS 26") }
        var policy = BlurSurfaceView.Presentation(usesLiquidGlass: false, appearance: nil)
        let notifications = NotificationCenter()
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), material: .popover,
                                      cornerRadius: 12, flipped: true, notifications: notifications,
                                      presentation: { policy })
        let button = NSButton(title: "Choose", target: nil, action: nil)
        surface.content.addSubview(button)
        XCTAssertEqual(surface.subviews.filter { $0 is NSVisualEffectView }.count, 1)
        for enabled in [true, false, true] {
            policy.usesLiquidGlass = enabled
            notifications.post(name: .blurStyleChanged, object: nil)
            XCTAssertEqual(surface.usesLiquidGlass, enabled)
            XCTAssertTrue(button.superview === surface.content)
            XCTAssertTrue(surface.content.isFlipped)
            if enabled {
                let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView)
                XCTAssertTrue(glass.contentView === surface.content)
                XCTAssertNil(glass.tintColor)
                XCTAssertEqual(glass.style, .regular)
                XCTAssertFalse(surface.subviews.contains { $0 is NSVisualEffectView })
                XCTAssertFalse(surface.layer?.masksToBounds ?? false)
            } else {
                XCTAssertTrue(surface.content.superview === surface)
                XCTAssertEqual((surface.subviews.first as? NSVisualEffectView)?.material, .popover)
            }
            surface.setFrameSize(CGSize(width: 360, height: 210))
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(surface.content.frame, surface.bounds)
            if enabled {
                surface.setFrameSize(CGSize(width: 1, height: 1))
                surface.layoutSubtreeIfNeeded()
                let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView)
                XCTAssertTrue(glass.isHidden, "Do not render native glass with degenerate animation geometry")
                surface.setFrameSize(CGSize(width: 360, height: 210))
            }
        }
    }

    func testStandardAndUnsupportedMaterialsUseLegacyBlur() {
        var policy = BlurSurfaceView.Presentation(usesLiquidGlass: false, appearance: nil)
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 160, height: 80), material: .fullScreenUI,
                                      cornerRadius: 10, presentation: { policy })
        XCTAssertFalse(surface.usesLiquidGlass)
        XCTAssertEqual((surface.subviews.first as? NSVisualEffectView)?.material, .fullScreenUI)
        policy.usesLiquidGlass = true
        surface.refresh()
        if #available(macOS 26, *) {
            XCTAssertTrue(surface.subviews.contains { $0 is NSGlassEffectView })
        } else {
            XCTAssertFalse(surface.usesLiquidGlass)
            XCTAssertTrue(surface.subviews.contains { $0 is NSVisualEffectView })
        }
    }

    func testReduceTransparencyUsesThePlainFootprintWithGlassSelected() {
        Defaults.blurMaterial.value = .liquidGlass
        Defaults.footprintBlur.enabled = true
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: true) })
        defer { window.close() }
        XCTAssertFalse(window.usesLiquidGlass)
        XCTAssertFalse(window.presentation.usesBlur)
        XCTAssertFalse(window.presentation.fades)
    }

    func testFootprintGlassIgnoresLegacyTintAndLetsSystemHandleTransparency() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Native glass requires macOS 26") }
        Defaults.blurMaterial.value = .liquidGlass
        Defaults.footprintBlur.enabled = true
        let window = FootprintWindow(accessibility: { .init(reduceMotion: true, reduceTransparency: false) })
        defer { window.close() }
        XCTAssertTrue(window.usesLiquidGlass)
        XCTAssertTrue(window.presentation.usesBlur)
        XCTAssertEqual(window.presentation.alpha, 1)
        XCTAssertFalse(window.presentation.fades)
        XCTAssertFalse(window.presentation.animates)
        window.showPreview(in: CGRect(x: 60, y: 60, width: 320, height: 260), from: nil, duration: 0)
        window.contentView?.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(window.contentView)
        XCTAssertTrue(window.childWindows?.allSatisfy { !$0.isVisible } ?? true, "Custom shadow must be hidden")
        XCTAssertFalse(root.layer?.masksToBounds ?? true)
        XCTAssertTrue(root.subviews.compactMap { $0 as? NSBox }.allSatisfy(\.isHidden))
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        let material = try XCTUnwrap(descendants(root).compactMap { $0 as? BlurSurfaceView }.first)
        let preview = try XCTUnwrap(material.superview)
        XCTAssertFalse(preview.layer?.masksToBounds ?? true)
        XCTAssertTrue(preview.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.allSatisfy(\.isHidden) ?? true)
        if preview !== root {
            XCTAssertTrue(root.subviews.filter { $0 !== preview }.allSatisfy(\.isHidden), "Custom shadow must be hidden")
        }
        XCTAssertTrue(material.subviews.first is NSGlassEffectView)
        XCTAssertFalse(material.subviews.contains { $0 is NSVisualEffectView })
        Defaults.footprintBlur.enabled = false
        XCTAssertFalse(window.usesLiquidGlass)
        XCTAssertFalse(window.presentation.usesBlur)
    }

    func testStackListKeepsItsNativeHUDRowsAndSelectionWhenFootprintMaterialChanges() throws {
        let windows = ["First", "Second"].enumerated().map { index, title in
            StackBadgeStackedWindow(windowId: CGWindowID(index + 1), pid: getpid(), title: title)
        }
        let panel = StackBadgeListPanel(windows: windows, selectedWindowId: 2,
                                        listTop: CGPoint(x: 20, y: 200),
                                        screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                        onSelect: { _ in }, onDismiss: {}, onLostKey: {})
        defer { panel.close() }
        let hud = try XCTUnwrap(panel.contentView as? NSVisualEffectView)
        let rows = hud.subviews.compactMap { $0 as? StackBadgeRowView }
        XCTAssertEqual(rows.count, 2)
        for material: BlurMaterial in [.liquidGlass, .standard] {
            Defaults.blurMaterial.value = material
            Notification.Name.blurStyleChanged.post()
            XCTAssertTrue(panel.contentView === hud)
            XCTAssertEqual(hud.material, .hudWindow)
            XCTAssertEqual(hud.blendingMode, .behindWindow)
            XCTAssertEqual(hud.state, .active)
            XCTAssertEqual(hud.subviews.compactMap { $0 as? StackBadgeRowView }, rows)
            XCTAssertEqual(panel.selectedWindow?.windowId, 2)
        }
        panel.moveSelection(by: -1)
        XCTAssertEqual(panel.selectedWindow?.windowId, 1)
    }

    func testMinimumSizeWarningKeepsItsNativeHUDAndLabelWhenFootprintMaterialChanges() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let warningPreference = Defaults.showMinimumWindowSizeWarning.toCodable()
        Defaults.showMinimumWindowSizeWarning.enabled = true
        defer { Defaults.showMinimumWindowSizeWarning.load(from: warningPreference) }
        let warning = WindowSizeWarning()
        defer { warning.hide(); warning.close() }
        let hud = try XCTUnwrap(warning.contentView as? NSVisualEffectView)
        let stack = try XCTUnwrap(hud.subviews.compactMap { $0 as? NSStackView }.first)
        let title = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertFalse(title.stringValue.isEmpty)
        for material: BlurMaterial in [.liquidGlass, .standard] {
            Defaults.blurMaterial.value = material
            Notification.Name.blurStyleChanged.post()
            warning.show(on: screen)
            XCTAssertTrue(warning.contentView === hud)
            XCTAssertEqual(hud.material, .hudWindow)
            XCTAssertEqual(hud.blendingMode, .behindWindow)
            XCTAssertEqual(hud.state, .active)
            XCTAssertTrue(title.isDescendant(of: hud))
            XCTAssertTrue(warning.ignoresMouseEvents)
            XCTAssertGreaterThan(warning.frame.width, 100)
            XCTAssertEqual(warning.frame.height, 48)
        }
    }

    func testPreferenceParticipatesInConfigAndViewModel() {
        Defaults.blurMaterial.value = .liquidGlass
        let preference = Defaults.array.first { $0.key == "blurMaterial" }
        XCTAssertNotNil(preference)
        XCTAssertEqual(preference?.toCodable().int, BlurMaterial.liquidGlass.rawValue)
        let model = SnapAreaViewModel()
        XCTAssertTrue(model.liquidGlassForBlurFootprint)
        model.liquidGlassForBlurFootprint = false
        XCTAssertEqual(Defaults.blurMaterial.value, .standard)
    }
}

@MainActor
final class BlurDefaultSelectionTests: XCTestCase {
    private var savedBlur = false
    private var storedBlur: Any?
    private var storedGlass: Any?
    override func setUp() {
        savedBlur = Defaults.footprintBlur.enabled
        storedBlur = UserDefaults.standard.object(forKey: Defaults.footprintBlur.key)
        storedGlass = UserDefaults.standard.object(forKey: Defaults.blurMaterial.key)
        Defaults.footprintBlur.enabled = false
        UserDefaults.standard.removeObject(forKey: Defaults.footprintBlur.key)
        UserDefaults.standard.removeObject(forKey: Defaults.blurMaterial.key)
    }
    override func tearDown() {
        Defaults.footprintBlur.enabled = savedBlur
        for (key, value) in [(Defaults.footprintBlur.key, storedBlur), (Defaults.blurMaterial.key, storedGlass)] {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        Notification.Name.blurStyleChanged.post()
    }
    func testOpeningAndReloadingSettingsDoesNotCreateMaterialChoices() {
        let model = SnapAreaViewModel()
        model.syncDefaults()
        XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.footprintBlur.key))
        XCTAssertNil(UserDefaults.standard.object(forKey: Defaults.blurMaterial.key))
    }
    func testExistingBlurWithoutAStoredMaterialStaysStandardWhenSettingsOpen() {
        Defaults.footprintBlur.enabled = true
        let model = SnapAreaViewModel()
        model.syncDefaults()
        XCTAssertTrue(model.footprintBlur)
        XCTAssertFalse(model.liquidGlassForBlurFootprint)
        XCTAssertFalse(Defaults.blurMaterial.hasSelection)
    }

    func testMissingMaterialIsOmittedFromExportUntilTheUserChooses() throws {
        let config = try XCTUnwrap(Defaults.encoded().flatMap { Defaults.convert(jsonString: $0) })
        XCTAssertNil(config.defaults[Defaults.blurMaterial.key])
    }

    func testInvalidStoredMaterialUsesTheFirstUseDefault() throws {
        let key = Defaults.blurMaterial.key
        for invalid: Any in [999, true, "1", 0.5] {
            let suite = "BlurMaterialTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.setPersistentDomain([key: invalid], forName: suite)
            let preference = BlurMaterialPreference(defaults: defaults)
            XCTAssertFalse(preference.hasSelection)
            XCTAssertEqual(preference.value, .standard)

            preference.value = .liquidGlass
            XCTAssertTrue(preference.hasSelection)
            XCTAssertEqual(preference.value, .liquidGlass)
        }
    }

    func testFirstUserEnablingBlurSelectsGlassOnlyOnSupportedSystems() {
        let model = SnapAreaViewModel()
        model.footprintBlur = true
        XCTAssertTrue(Defaults.footprintBlur.enabled)
        if #available(macOS 26, *) {
            XCTAssertTrue(model.liquidGlassForBlurFootprint)
            XCTAssertEqual(Defaults.blurMaterial.value, .liquidGlass)
        } else {
            XCTAssertFalse(model.liquidGlassForBlurFootprint)
            XCTAssertEqual(Defaults.blurMaterial.value, .standard)
        }
    }
    func testExplicitlyDisabledGlassSurvivesBlurOffOnAndReload() {
        let model = SnapAreaViewModel()
        model.footprintBlur = true
        model.liquidGlassForBlurFootprint = false
        model.footprintBlur = false
        model.syncDefaults()
        model.footprintBlur = true
        XCTAssertFalse(model.liquidGlassForBlurFootprint)
        XCTAssertEqual(Defaults.blurMaterial.value, .standard)
    }
    func testImportedDisabledChoiceIsRespectedBeforeFirstBlurToggle() {
        Defaults.blurMaterial.load(from: CodableDefault(int: BlurMaterial.standard.rawValue))
        let model = SnapAreaViewModel()
        model.footprintBlur = true
        XCTAssertFalse(model.liquidGlassForBlurFootprint)
        XCTAssertEqual(Defaults.blurMaterial.value, .standard)
    }
}

@MainActor
final class BlurAppearanceLiveTests: XCTestCase {
    private var savedMaterial: Any?
    private var savedAppearance = BlurAppearance.system
    private var savedBlur = false

    override func setUp() {
        savedMaterial = UserDefaults.standard.object(forKey: Defaults.blurMaterial.key)
        savedAppearance = Defaults.blurAppearance.value
        savedBlur = Defaults.footprintBlur.enabled
    }

    override func tearDown() {
        UserDefaults.standard.set(savedMaterial, forKey: Defaults.blurMaterial.key)
        Defaults.blurAppearance.value = savedAppearance
        Defaults.footprintBlur.enabled = savedBlur
        Notification.Name.blurStyleChanged.post()
    }

    func testViewModelUpdatesExistingMaterialsAndRestoresInheritedAppearance() throws {
        Defaults.blurAppearance.value = .system
        let model = SnapAreaViewModel()
        for glass in [false, true] {
            let parent = NSView()
            parent.appearance = NSAppearance(named: .darkAqua)
            let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 300, height: 240), material: .fullScreenUI,
                                          cornerRadius: 12, presentation: {
                .init(usesLiquidGlass: glass, appearance: model.blurAppearance.appearance)
            })
            parent.addSubview(surface)
            let content = surface.content
            let material = try XCTUnwrap(surface.subviews.first)
            var styleChanges = 0
            var appearanceChanges = 0
            surface.onStyleChange = { styleChanges += 1 }
            surface.onAppearanceChange = { appearanceChanges += 1 }
            for choice: BlurAppearance in [.light, .dark, .system] {
                model.blurAppearance = choice
                XCTAssertEqual(surface.appearance?.name, choice.appearance?.name)
                XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                               choice == .light ? .aqua : .darkAqua)
                XCTAssertTrue(surface.content === content)
                XCTAssertTrue(surface.subviews.first === material, "Appearance changes must not recreate the material")
            }
            XCTAssertEqual(styleChanges, 0, "Theme changes must not restart style/geometry transitions")
            XCTAssertEqual(appearanceChanges, 3)
        }
    }

    func testConfigImportClearsForcedMaterialAppearance() {
        var policy = BlurSurfaceView.Presentation(usesLiquidGlass: false, appearance: NSAppearance(named: .darkAqua))
        let notifications = NotificationCenter()
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 300, height: 240), material: .fullScreenUI,
                                      cornerRadius: 12, notifications: notifications, presentation: { policy })
        XCTAssertEqual(surface.appearance?.name, .darkAqua)
        policy.appearance = nil
        notifications.post(name: .configImported, object: nil)
        XCTAssertNil(surface.appearance)
    }

    func testLiveGlassFootprintUsesAllThreeAppearancesWithoutChangingItsFrame() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Requires native Glass") }
        Defaults.blurMaterial.value = .liquidGlass
        Defaults.footprintBlur.enabled = true
        Defaults.blurAppearance.value = .system
        let model = SnapAreaViewModel()
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: false) })
        defer { window.close() }
        window.showPreview(in: CGRect(x: 60, y: 60, width: 400, height: 300), from: nil, duration: 0)
        let original = window.frame
        for choice: BlurAppearance in [.dark, .light, .system] {
            model.blurAppearance = choice
            XCTAssertEqual(window.appearance?.name, choice.appearance?.name)
            XCTAssertTrue(window.usesLiquidGlass)
            XCTAssertEqual(window.frame, original)
            XCTAssertTrue(window.realIsVisible)
        }
    }
}
