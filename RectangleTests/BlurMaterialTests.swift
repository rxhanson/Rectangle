import XCTest
@testable import Rectangle

@MainActor
final class LiquidGlassBlurTests: XCTestCase {
    private var previousMaterial: Any?

    override func setUp() {
        previousMaterial = UserDefaults.standard.object(forKey: Defaults.overlayMaterial.key)
    }
    override func tearDown() {
        UserDefaults.standard.set(previousMaterial, forKey: Defaults.overlayMaterial.key)
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
        Defaults.overlayMaterial.value = .liquidGlass
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
        Defaults.overlayMaterial.value = .liquidGlass
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
        Defaults.overlayMaterial.value = .standard
        Notification.Name.blurStyleChanged.post()
        window.movePreview(to: right, duration: 0.24)
        try await Task.sleep(nanoseconds: 50_000_000)
        Defaults.overlayMaterial.value = .liquidGlass
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
        var policy = BlurSurfaceView.Presentation(material: .standard, appearance: nil)
        let notifications = NotificationCenter()
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), material: .popover,
                                      cornerRadius: 12, notifications: notifications,
                                      presentation: { policy })
        let host = NSWindow(contentRect: surface.frame, styleMask: .titled, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        defer { host.close() }
        host.contentView?.addSubview(surface)
        let editor = NSTextView(frame: CGRect(x: 5, y: 5, width: 150, height: 50))
        surface.content.addSubview(editor)
        XCTAssertTrue(host.makeFirstResponder(editor))
        XCTAssertEqual(surface.subviews.filter { $0 is NSVisualEffectView }.count, 1)
        for choice: OverlayMaterial in [.liquidGlass, .noBlur, .standard, .liquidGlass] {
            policy.material = choice
            notifications.post(name: .blurStyleChanged, object: nil)
            XCTAssertEqual(surface.effectiveMaterial, choice)
            XCTAssertTrue(editor.superview === surface.content)
            if choice == .liquidGlass {
                let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView)
                XCTAssertTrue(glass.contentView === surface.content)
                XCTAssertNil(glass.tintColor)
                XCTAssertEqual(glass.style, .regular)
                XCTAssertFalse(surface.subviews.contains { $0 is NSVisualEffectView })
                XCTAssertFalse(surface.layer?.masksToBounds ?? false)
            } else {
                XCTAssertTrue(surface.content.superview === surface)
                if choice == .standard {
                    XCTAssertEqual((surface.subviews.first as? NSVisualEffectView)?.material, .popover)
                } else {
                    XCTAssertFalse(surface.subviews.contains { $0 is NSVisualEffectView || $0 is NSGlassEffectView })
                    XCTAssertNotNil(surface.subviews.first?.layer?.backgroundColor)
                }
            }
            surface.setFrameSize(CGSize(width: 360, height: 210))
            surface.layoutSubtreeIfNeeded()
            XCTAssertEqual(surface.content.frame, surface.bounds)
        }
    }

    func testGlassHidesAtOnePointAndReappearsWhenTheSurfaceGrows() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Native glass requires macOS 26") }
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), material: .popover,
                                      cornerRadius: 12, presentation: { .init(material: .liquidGlass, appearance: nil) })
        let glass = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView)
        surface.setFrameSize(CGSize(width: 1, height: 1))
        surface.layoutSubtreeIfNeeded()
        XCTAssertTrue(glass.isHidden)
        surface.setFrameSize(CGSize(width: 360, height: 210))
        surface.layoutSubtreeIfNeeded()
        XCTAssertFalse(glass.isHidden)
        XCTAssertTrue(glass.contentView === surface.content)
        XCTAssertEqual(glass.frame, surface.bounds)
    }

    func testStandardAndUnsupportedMaterialsUseLegacyBlur() {
        var policy = BlurSurfaceView.Presentation(material: .standard, appearance: nil)
        let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 160, height: 80), material: .fullScreenUI,
                                      cornerRadius: 10, presentation: { policy })
        XCTAssertFalse(surface.usesLiquidGlass)
        XCTAssertEqual((surface.subviews.first as? NSVisualEffectView)?.material, .fullScreenUI)
        policy.material = .liquidGlass
        surface.refresh()
        if #available(macOS 26, *) {
            XCTAssertTrue(surface.subviews.contains { $0 is NSGlassEffectView })
        } else {
            XCTAssertFalse(surface.usesLiquidGlass)
            XCTAssertTrue(surface.subviews.contains { $0 is NSVisualEffectView })
        }
    }

    func testReduceTransparencyUsesThePlainFootprintWithGlassSelected() {
        Defaults.overlayMaterial.value = .liquidGlass
        var reduceTransparency = true
        let window = FootprintWindow(accessibility: { .init(reduceMotion: false, reduceTransparency: reduceTransparency) })
        defer { window.close() }
        XCTAssertFalse(window.usesLiquidGlass)
        XCTAssertFalse(window.presentation.usesBlur)
        XCTAssertFalse(window.presentation.fades)
        XCTAssertEqual(Defaults.overlayMaterial.value, .liquidGlass)
        reduceTransparency = false
        window.refreshAccessibility()
        XCTAssertTrue(window.presentation.usesBlur)
        XCTAssertEqual(window.usesLiquidGlass, OverlayMaterial.supportsLiquidGlass)
    }

    func testFootprintGlassIgnoresLegacyTintAndLetsSystemHandleTransparency() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Native glass requires macOS 26") }
        Defaults.overlayMaterial.value = .liquidGlass
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
        Defaults.overlayMaterial.value = .noBlur
        XCTAssertFalse(window.usesLiquidGlass)
        XCTAssertFalse(window.presentation.usesBlur)
    }

    func testStackListRetainsItsRowsAndSelectionAcrossOverlayMaterials() throws {
        let windows = ["First", "Second"].enumerated().map { index, title in
            StackBadgeStackedWindow(windowId: CGWindowID(index + 1), pid: getpid(), title: title)
        }
        let panel = StackBadgeListPanel(windows: windows, selectedWindowId: 2,
                                        listTop: CGPoint(x: 20, y: 200),
                                        screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                        onSelect: { _ in }, onDismiss: {}, onLostKey: {})
        defer { panel.close() }
        let hud = try XCTUnwrap(panel.contentView as? BlurSurfaceView)
        let rows = hud.content.subviews.compactMap { $0 as? StackBadgeRowView }
        XCTAssertEqual(rows.count, 2)
        let settings = AppSettingsViewModel()
        let savedAppearance = settings.blurAppearance
        defer { settings.blurAppearance = savedAppearance }
        for material: OverlayMaterial in [.noBlur, .standard, .liquidGlass] {
            settings.overlayMaterial = material
            XCTAssertTrue(panel.contentView === hud)
            try assertHUDMaterial(hud, requested: material)
            XCTAssertEqual(hud.content.subviews.compactMap { $0 as? StackBadgeRowView }, rows)
            XCTAssertEqual(panel.selectedWindow?.windowId, 2)
        }
        settings.overlayMaterial = .standard
        let selected = try XCTUnwrap(rows.last)
        for appearance: BlurAppearance in [.dark, .light, .system] {
            settings.blurAppearance = appearance
            var expected: CGColor?
            selected.effectiveAppearance.performAsCurrentDrawingAppearance {
                expected = NSColor.selectedContentBackgroundColor.cgColor
            }
            XCTAssertEqual(selected.layer?.backgroundColor, expected)
            XCTAssertNil(rows.first?.layer?.backgroundColor)
        }
        panel.moveSelection(by: -1)
        XCTAssertEqual(panel.selectedWindow?.windowId, 1)
    }

    func testMinimumSizeWarningRetainsItsLabelAndLayoutAcrossOverlayMaterials() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let warningPreference = Defaults.showMinimumWindowSizeWarning.toCodable()
        Defaults.showMinimumWindowSizeWarning.enabled = true
        defer { Defaults.showMinimumWindowSizeWarning.load(from: warningPreference) }
        let warning = WindowSizeWarning()
        defer { warning.hide(); warning.close() }
        let hud = try XCTUnwrap(warning.contentView as? BlurSurfaceView)
        let stack = try XCTUnwrap(hud.content.subviews.compactMap { $0 as? NSStackView }.first)
        let title = try XCTUnwrap(stack.arrangedSubviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertFalse(title.stringValue.isEmpty)
        let settings = AppSettingsViewModel()
        for material: OverlayMaterial in [.noBlur, .standard, .liquidGlass] {
            settings.overlayMaterial = material
            warning.show(on: screen)
            XCTAssertTrue(warning.contentView === hud)
            try assertHUDMaterial(hud, requested: material)
            XCTAssertTrue(title.isDescendant(of: hud))
            XCTAssertTrue(warning.ignoresMouseEvents)
            XCTAssertGreaterThan(warning.frame.width, 100)
            XCTAssertEqual(warning.frame.height, 48)
        }
    }

    private func assertHUDMaterial(_ surface: BlurSurfaceView, requested: OverlayMaterial,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = requested.effective(supportsLiquidGlass: OverlayMaterial.supportsLiquidGlass,
                                           reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        XCTAssertEqual(surface.effectiveMaterial, expected, file: file, line: line)
        switch expected {
        case .noBlur:
            let solid = try XCTUnwrap(surface.subviews.first, file: file, line: line)
            XCTAssertFalse(solid === surface.content, file: file, line: line)
            XCTAssertFalse(solid.isHidden, file: file, line: line)
            XCTAssertNotNil(solid.layer?.backgroundColor, file: file, line: line)
            XCTAssertFalse(surface.subviews.contains { $0 is NSVisualEffectView }, file: file, line: line)
            if #available(macOS 26, *) {
                XCTAssertFalse(surface.subviews.contains { $0 is NSGlassEffectView }, file: file, line: line)
            }
        case .standard:
            let effect = try XCTUnwrap(surface.subviews.first as? NSVisualEffectView, file: file, line: line)
            XCTAssertEqual(effect.material, .hudWindow, file: file, line: line)
            XCTAssertEqual(effect.blendingMode, .behindWindow, file: file, line: line)
            XCTAssertEqual(effect.state, .active, file: file, line: line)
            XCTAssertFalse(effect.isHidden, file: file, line: line)
        case .liquidGlass:
            if #available(macOS 26, *) {
                let effect = try XCTUnwrap(surface.subviews.first as? NSGlassEffectView, file: file, line: line)
                XCTAssertTrue(effect.contentView === surface.content, file: file, line: line)
                XCTAssertFalse(effect.isHidden, file: file, line: line)
            }
        }
    }
}

@MainActor
final class BlurAppearanceLiveTests: XCTestCase {
    private var savedMaterial: Any?
    private var savedAppearance = BlurAppearance.system

    override func setUp() {
        savedMaterial = UserDefaults.standard.object(forKey: Defaults.overlayMaterial.key)
        savedAppearance = Defaults.blurAppearance.value
    }

    override func tearDown() {
        UserDefaults.standard.set(savedMaterial, forKey: Defaults.overlayMaterial.key)
        Defaults.blurAppearance.value = savedAppearance
        Notification.Name.blurStyleChanged.post()
    }

    func testViewModelUpdatesExistingMaterialsAndRestoresInheritedAppearance() throws {
        Defaults.blurAppearance.value = .system
        let model = AppSettingsViewModel()
        for requestedMaterial: OverlayMaterial in [.standard, .liquidGlass] {
            let parent = NSView()
            parent.appearance = NSAppearance(named: .darkAqua)
            let surface = BlurSurfaceView(frame: CGRect(x: 0, y: 0, width: 300, height: 240), material: .fullScreenUI,
                                          cornerRadius: 12, presentation: {
                .init(material: requestedMaterial, appearance: model.blurAppearance.appearance)
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
        var policy = BlurSurfaceView.Presentation(material: .standard, appearance: NSAppearance(named: .darkAqua))
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
        Defaults.overlayMaterial.value = .liquidGlass
        Defaults.blurAppearance.value = .system
        let model = AppSettingsViewModel()
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
